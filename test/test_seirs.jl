using Epidemic
using Test
using Agents


@testset "SEIRS Model" begin

    @testset "Model Initialization" begin
        model = initialize_model()
        @test nagents(model) == 150
        @test count(a -> a.status == susceptible, allagents(model)) == 140
        @test count(a -> a.status == infected, allagents(model)) == 10

        # Test invalid parameters
        @test_throws AssertionError initialize_model(duration = -3)
        @test_throws AssertionError initialize_model(infectiousness = 1.5)
        @test_throws AssertionError initialize_model(initial_infected = 200)
    end

    @testset "Model with Doctors" begin
        model = initialize_model(n_agents = 10, n_doctors = 5, initial_infected = 2)
        @test nagents(model) == 15
        # All doctors should be masked and vaccinated
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

    # ========================================================
    # Strategy tests (Stage 2)
    # ========================================================

    @testset "ProtectedTransmission ≤ BasicTransmission" begin
        params = ModelParams(
            infectiousness = 0.8,
            mask_effectiveness = 0.5,
            vaccine_effectiveness = 0.7,
        )

        # Create a mock-like pair: masked + vaccinated target
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

    @testset "Custom strategy (extensibility proof)" begin
        # A user-defined strategy — defined outside the Epidemic module
        struct QuarantineTransmission <: TransmissionStrategy end

        # Quarantine: transmission is zero (total lockdown)
        Epidemic.transmission_probability(::QuarantineTransmission, source, target, params) = 0.0

        params = ModelParams(strategy = QuarantineTransmission())

        model = initialize_model(
            n_agents = 2,
            initial_infected = 1,
            strategy = QuarantineTransmission(),
            infectiousness = 1.0,
        )
        source = first(a for a in allagents(model) if a.status == infected)
        target = first(a for a in allagents(model) if a.status == susceptible)

        p = transmission_probability(QuarantineTransmission(), source, target, params)
        @test p == 0.0
    end

    # ========================================================
    # Multiple dispatch tests (Stage 3)
    # ========================================================

    @testset "Doctor multiple dispatch" begin
        params = ModelParams(
            infectiousness = 0.8,
            mask_effectiveness = 0.5,
            vaccine_effectiveness = 0.7,
        )

        model = initialize_model(
            n_agents = 2,
            n_doctors = 2,
            initial_infected = 1,
            mask_probability = 1.0,
            vaccination_probability = 1.0,
        )

        # Get one Person and one Doctor for testing
        person = first(a for a in allagents(model) if a isa Person && a.status == susceptible)
        infected_person = first(a for a in allagents(model) if a isa Person && a.status == infected)
        doctor = first(a for a in allagents(model) if a isa Doctor)

        # Person → Person
        p_pp = transmission_probability(ProtectedTransmission(), infected_person, person, params)
        # Person → Doctor (doctor has PPE, so should be lower)
        p_pd = transmission_probability(ProtectedTransmission(), infected_person, doctor, params)

        @test p_pd < p_pp  # doctor's PPE gives extra protection
    end
end
