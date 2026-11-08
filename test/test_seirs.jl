using Epidemic
using Test
using Agents

# ------------------------------------------------------------
# A user-defined strategy, written OUTSIDE the Epidemic module.
# It must live at top level (struct definitions are not allowed
# inside local scopes) and extend the function with the `Epidemic.` prefix.
# ------------------------------------------------------------
struct QuarantineTransmission <: TransmissionStrategy end
Epidemic.transmission_probability(::QuarantineTransmission, source, target, params) = 0.0

@testset "SEIRS Model" begin

    @testset "Model Initialization" begin
        model = initialize_model()
        @test nagents(model) == 150
        @test count(a -> a.status == susceptible, allagents(model)) == 140
        @test count(a -> a.status == infected, allagents(model)) == 10
    end

    @testset "Parameter validation" begin
        @test_throws ArgumentError initialize_model(duration = -3)
        @test_throws ArgumentError initialize_model(infectiousness = 1.5)
        @test_throws ArgumentError initialize_model(initial_infected = 200)
        @test_throws ArgumentError initialize_model(n_doctors = -1)

        # Doctors count towards the carrying capacity
        @test_throws ArgumentError initialize_model(
            n_agents = 10, n_doctors = 5, initial_infected = 0, carrying_capacity = 12)

        # Doctors need max_age >= 25 to draw an age
        @test_throws ArgumentError initialize_model(
            n_agents = 10, n_doctors = 2, initial_infected = 0, max_age = 20)
    end

    @testset "Model with Doctors" begin
        model = initialize_model(n_agents = 10, n_doctors = 5, initial_infected = 2)
        @test nagents(model) == 15
        @test count(a -> a isa Doctor, allagents(model)) == 5
        # Doctors are masked and vaccinated by default
        for a in allagents(model)
            if a isa Doctor
                @test a.wearing_mask == true
                @test a.vaccinated == true
            end
        end
    end

    # Test function A: Move an agent randomly
    @testset "Movement" begin
        model = initialize_model(dims = (10, 10), n_agents = 1, initial_infected = 0)
        agent = first(allagents(model))
        random_step!(agent, model)
        @test all(1 <= agent.pos[i] <= 10 for i in 1:2)
    end

    # Test function B: Aging and natural death
    @testset "Aging and Death" begin
        model = initialize_model(n_agents = 1, initial_infected = 0, max_age = 100)
        agent = first(allagents(model))
        agent.age = 20
        @test aging_and_death!(agent, model) == false
        @test agent.age == 21

        agent.age = 99
        @test aging_and_death!(agent, model) == true
        @test nagents(model) == 0
    end

    # Test function C: Health state transitions
    @testset "Health transition" begin
        model = initialize_model(
            n_agents = 1,
            initial_infected = 0,
            latency_period = 3,
            duration = 2,
            chance_recover = 1.0,
            immunity_duration = 2,
        )
        agent = first(allagents(model))

        agent.status = exposed
        agent.exposure_timer = 2
        update_health!(agent, model)
        @test agent.status == infected

        agent.infection_timer = 1
        update_health!(agent, model)
        @test agent.status == recovered

        agent.immunity_timer = 1
        update_health!(agent, model)
        @test agent.status == susceptible
    end

    # Test function D: Transmission
    @testset "Transmission" begin
        model = initialize_model(
            n_agents = 2,
            initial_infected = 1,
            infectiousness = 1.0,
            mask_probability = 0.0,
            vaccination_probability = 0.0,
        )
        susceptible_agent = first(a for a in allagents(model) if a.status == susceptible)
        infected_agent = first(a for a in allagents(model) if a.status == infected)

        move_agent!(susceptible_agent, infected_agent.pos, model)
        transmit_infection!(infected_agent, model)

        @test susceptible_agent.status == exposed
    end

    # Test function E: Reproduction
    @testset "Reproduction" begin
        model = initialize_model(
            n_agents = 1,
            initial_infected = 0,
            birth_rate = 1.0,
            carrying_capacity = 2,
        )
        agent = first(allagents(model))
        reproduce!(agent, model)
        @test nagents(model) == 2

        reproduce!(agent, model)
        @test nagents(model) == 2
    end

    # Test the complete agent step
    @testset "Agent step" begin
        model = initialize_model(
            n_agents = 1,
            initial_infected = 0,
            max_age = 100,
            birth_rate = 0.0,
        )
        agent = first(allagents(model))
        agent.age = 20

        agent_step!(agent, model)
        @test agent.age == 21
        @test nagents(model) == 1

        agent.age = 99
        agent_step!(agent, model)
        @test nagents(model) == 0
    end

    # The population never exceeds the carrying capacity, doctors included
    @testset "Carrying capacity with doctors" begin
        cap = 40
        model = initialize_model(
            n_agents = 20, n_doctors = 5, initial_infected = 3,
            birth_rate = 0.5, carrying_capacity = cap,
        )
        within_cap = true
        for _ in 1:100
            step!(model)
            within_cap &= nagents(model) <= cap
        end
        @test within_cap
    end

    # ========================================================
    # Strategy tests
    # ========================================================

    @testset "ProtectedTransmission ≤ BasicTransmission" begin
        params = ModelParams(
            infectiousness = 0.8,
            mask_effectiveness = 0.5,
            vaccine_effectiveness = 0.7,
        )

        model = initialize_model(
            n_agents = 2,
            initial_infected = 1,
            mask_probability = 1.0,
            vaccination_probability = 1.0,
        )
        source = first(a for a in allagents(model) if a.status == infected)
        target = first(a for a in allagents(model) if a.status == susceptible)

        p_basic = transmission_probability(BasicTransmission(), source, target, params)
        p_protected = transmission_probability(ProtectedTransmission(), source, target, params)

        @test p_basic == params.infectiousness
        @test p_protected <= p_basic
        @test p_protected < p_basic  # strictly less when masks + vaccines are active
    end

    @testset "Unprotected agents: Protected == Basic" begin
        params = ModelParams(infectiousness = 0.8)
        model = initialize_model(n_agents = 0, initial_infected = 0)
        a = add_agent!(Person, model; wearing_mask = false, vaccinated = false)
        b = add_agent!(Person, model; wearing_mask = false, vaccinated = false)

        @test transmission_probability(ProtectedTransmission(), a, b, params) ≈
              transmission_probability(BasicTransmission(), a, b, params)
    end

    @testset "Custom strategy (extensibility proof)" begin
        params = ModelParams(strategy = QuarantineTransmission())
        model = initialize_model(n_agents = 2, initial_infected = 1)
        source = first(a for a in allagents(model) if a.status == infected)
        target = first(a for a in allagents(model) if a.status == susceptible)
        @test transmission_probability(QuarantineTransmission(), source, target, params) == 0.0

        # End-to-end: with total quarantine, nobody is ever exposed.
        model = initialize_model(
            n_agents = 30, initial_infected = 10, birth_rate = 0.0,
            infectiousness = 1.0, strategy = QuarantineTransmission(),
        )
        new_exposures = 0
        for _ in 1:30
            step!(model)
            new_exposures += count(a -> a.status == exposed, allagents(model))
        end
        @test new_exposures == 0
    end

    # ========================================================
    # Multiple dispatch tests (strategy × source type × target type)
    # ========================================================

    @testset "Doctor multiple dispatch (hand-computed values)" begin
        params = ModelParams(
            infectiousness = 0.8,
            mask_effectiveness = 0.5,
            vaccine_effectiveness = 0.7,
        )
        model = initialize_model(n_agents = 0, initial_infected = 0)
        person = add_agent!(Person, model; wearing_mask = true, vaccinated = true)
        doctor = add_agent!(Doctor, model)   # ppe_protection = 0.9 by default

        mask, vax, ppe = 1 - 0.5, 1 - 0.7, 1 - 0.9
        P = ProtectedTransmission()

        # Person -> Person: source mask, target mask + vaccine
        @test transmission_probability(P, person, person, params) ≈ 0.8 * mask * (mask * vax)
        # Person -> Doctor: source mask, target mask + vaccine + PPE
        @test transmission_probability(P, person, doctor, params) ≈ 0.8 * mask * (mask * vax * ppe)
        # Doctor -> Person: source mask + PPE, target mask + vaccine
        @test transmission_probability(P, doctor, person, params) ≈ 0.8 * (mask * ppe) * (mask * vax)
        # Doctor -> Doctor: both sides protected
        @test transmission_probability(P, doctor, doctor, params) ≈ 0.8 * (mask * ppe) * (mask * vax * ppe)

        # PPE gives extra protection
        @test transmission_probability(P, person, doctor, params) <
              transmission_probability(P, person, person, params)
    end

    @testset "Doctor fields are respected" begin
        params = ModelParams(infectiousness = 1.0, mask_effectiveness = 0.5)
        model = initialize_model(n_agents = 0, initial_infected = 0)
        unmasked_doctor = add_agent!(Doctor, model; wearing_mask = false)

        # Without a mask only the PPE factor remains
        @test emission_factor(unmasked_doctor, params) ≈ 1 - 0.9
    end

    @testset "Display" begin
        model = initialize_model(n_agents = 1, n_doctors = 1, initial_infected = 0)
        agents = collect(allagents(model))
        @test occursin("Person", sprint(show, first(a for a in agents if a isa Person)))
        @test occursin("Doctor", sprint(show, first(a for a in agents if a isa Doctor)))
    end
end