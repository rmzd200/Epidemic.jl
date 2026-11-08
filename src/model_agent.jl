# 1. Agent Definitions
@enum HealthStatus susceptible exposed infected recovered

@agent struct Person(GridAgent{2})
    status::HealthStatus = susceptible
    exposure_timer::Int = 0
    infection_timer::Int = 0
    immunity_timer::Int  = 0
    age::Int             = 0
    wearing_mask::Bool   = false
    vaccinated::Bool     = false
end

@agent struct Doctor(GridAgent{2})
    status::HealthStatus = susceptible
    exposure_timer::Int = 0
    infection_timer::Int = 0
    immunity_timer::Int  = 0
    age::Int             = 0
    wearing_mask::Bool   = true    # doctors always wear masks
    vaccinated::Bool     = true    # doctors always vaccinated
    ppe_protection::Float64 = 0.9  # PPE gives extra protection beyond masks
end

# 2. Transmission Strategies
abstract type TransmissionStrategy end
struct BasicTransmission <: TransmissionStrategy end
struct ProtectedTransmission <: TransmissionStrategy end

"""
    transmission_probability(strategy, source, target, params) -> Float64

Return the probability that `source` infects `target` under the given `strategy`.

To add a custom strategy, subtype [`TransmissionStrategy`](@ref) and implement
this method:

    struct MyStrategy <: TransmissionStrategy end
    Epidemic.transmission_probability(::MyStrategy, source, target, params) = ...
"""
function transmission_probability end

# --- BasicTransmission: raw infectiousness, ignores masks/vaccines ---

transmission_probability(::BasicTransmission, source, target, params) =
    params.infectiousness

# --- ProtectedTransmission × Person → Person ---

function transmission_probability(::ProtectedTransmission,
                                  source::Person, target::Person, params)
    p = params.infectiousness
    if source.wearing_mask
        p *= (1 - params.mask_effectiveness)
    end
    if target.wearing_mask
        p *= (1 - params.mask_effectiveness)
    end
    if target.vaccinated
        p *= (1 - params.vaccine_effectiveness)
    end
    return p
end

# --- ProtectedTransmission × Person to Doctor (doctor as target) ---
# Doctors wear PPE on top of mask + vaccine protection

function transmission_probability(::ProtectedTransmission,
                                  source::Person, target::Doctor, params)
    p = params.infectiousness
    if source.wearing_mask
        p *= (1 - params.mask_effectiveness)
    end
    # Doctor always has mask + vaccine + PPE
    p *= (1 - params.mask_effectiveness)
    p *= (1 - params.vaccine_effectiveness)
    p *= (1 - target.ppe_protection)
    return p
end

# --- ProtectedTransmission × Doctor to Person (doctor as source) ---
# Doctors' PPE also reduces outward transmission

function transmission_probability(::ProtectedTransmission,
                                  source::Doctor, target::Person, params)
    p = params.infectiousness
    # Doctor source: mask + PPE reduce outward spread
    p *= (1 - params.mask_effectiveness)
    p *= (1 - source.ppe_protection)
    if target.wearing_mask
        p *= (1 - params.mask_effectiveness)
    end
    if target.vaccinated
        p *= (1 - params.vaccine_effectiveness)
    end
    return p
end

# --- ProtectedTransmission × Doctor → Doctor ---

function transmission_probability(::ProtectedTransmission,
                                  source::Doctor, target::Doctor, params)
    p = params.infectiousness
    # Source doctor: mask + PPE
    p *= (1 - params.mask_effectiveness)
    p *= (1 - source.ppe_protection)
    # Target doctor: mask + vaccine + PPE
    p *= (1 - params.mask_effectiveness)
    p *= (1 - params.vaccine_effectiveness)
    p *= (1 - target.ppe_protection)
    return p
end

# 3. Model Parameters (parametric on strategy for type stability)
Base.@kwdef struct ModelParams{S <: TransmissionStrategy}
    infectiousness::Float64          = 0.65
    latency_period::Int              = 8
    duration::Int                    = 25
    chance_recover::Float64          = 0.60
    immunity_duration::Int           = 40
    birth_rate::Float64              = 0.015
    carrying_capacity::Int           = 300
    max_age::Int                     = 110
    mask_effectiveness::Float64      = 0.5
    mask_probability::Float64        = 0.5
    vaccine_effectiveness::Float64   = 0.7
    vaccination_probability::Float64 = 0.6
    strategy::S                      = ProtectedTransmission()
end

# 4. Agent Dynamics

# A. Movement
function random_step!(agent, model)
    randomwalk!(agent, model)
end

# B. Aging and natural death
function aging_and_death!(agent, model)
    agent.age += 1
    params = abmproperties(model)
    if agent.age >= params.max_age
        remove_agent!(agent, model)
        return true
    end
    return false
end

# C. Health state transitions (SEIRS)
function update_health!(agent, model)
    params = abmproperties(model)

    # E → I: End of exposure period
    if agent.status == exposed
        agent.exposure_timer += 1
        if agent.exposure_timer >= params.latency_period
            agent.status = infected
            agent.exposure_timer = 0
            agent.infection_timer = 0
        end

    # I → R: Recovery or death
    elseif agent.status == infected
        agent.infection_timer += 1
        if agent.infection_timer >= params.duration
            if rand(abmrng(model)) < params.chance_recover
                agent.status = recovered
                agent.infection_timer = 0
                agent.immunity_timer = 0
            else
                remove_agent!(agent, model)
                return true
            end
        end

    # R → S: Loss of immunity
    elseif agent.status == recovered
        agent.immunity_timer += 1
        if agent.immunity_timer >= params.immunity_duration
            agent.status = susceptible
            agent.immunity_timer = 0
        end
    end

    return false
end

# D. Transmission of the virus
function transmit_infection!(agent, model)
    params = abmproperties(model)
    if agent.status == infected
        for neighbor in agents_in_position(agent, model)
            neighbor.id == agent.id && continue
            if neighbor.status == susceptible
                p = transmission_probability(params.strategy, agent, neighbor, params)
                if rand(abmrng(model)) < p
                    neighbor.status = exposed
                    neighbor.exposure_timer = 0
                end
            end
        end
    end
    return nothing
end

# E. Reproduction
function reproduce!(agent, model)
    params = abmproperties(model)
    if nagents(model) < params.carrying_capacity
        if rand(abmrng(model)) < params.birth_rate
            wears_mask = rand(abmrng(model)) < params.mask_probability
            is_vaccinated = rand(abmrng(model)) < params.vaccination_probability
            # Newborns are always Person (doctors are specialists, not born into it)
            add_agent!(agent.pos, Person, model;
                       status = susceptible, age = 0,
                       wearing_mask = wears_mask, vaccinated = is_vaccinated)
        end
    end
    return nothing
end

# 5. Main Step Function

function agent_step!(agent, model)
    # A. Aging and Natural Death
    if aging_and_death!(agent, model)
        return
    end

    # B. Movement
    random_step!(agent, model)

    # C. Virus Progression & Recovery
    if update_health!(agent, model)
        return
    end

    # D. Transmission
    transmit_infection!(agent, model)

    # E. Reproduction
    reproduce!(agent, model)
end

# 6. Model Initialization

function initialize_model(;
    dims = (10, 10),
    n_agents = 150,
    n_doctors = 0,
    initial_infected = 10,
    infectiousness = 0.65,
    latency_period = 8,
    duration = 25,
    chance_recover = 0.60,
    immunity_duration = 40,
    birth_rate = 0.015,
    carrying_capacity = 300,
    max_age = 110,
    seed = 42,
    mask_probability = 0.5,
    mask_effectiveness = 0.5,
    vaccine_effectiveness = 0.7,
    vaccination_probability = 0.6,
    strategy::TransmissionStrategy = ProtectedTransmission(),
)
    # Validate parameters
    @assert 0 <= initial_infected <= n_agents <= carrying_capacity
    @assert latency_period > 0
    @assert duration > 0
    @assert immunity_duration > 0
    @assert max_age > 0
    @assert 0 <= infectiousness <= 1
    @assert 0 <= chance_recover <= 1
    @assert 0 <= birth_rate <= 1
    @assert 0 <= mask_probability <= 1
    @assert 0 <= mask_effectiveness <= 1
    @assert 0 <= vaccination_probability <= 1
    @assert 0 <= vaccine_effectiveness <= 1

    space = GridSpace(dims; periodic = true)

    properties = ModelParams(;
        infectiousness,
        latency_period,
        duration,
        chance_recover,
        immunity_duration,
        birth_rate,
        carrying_capacity,
        max_age,
        mask_effectiveness,
        mask_probability,
        vaccine_effectiveness,
        vaccination_probability,
        strategy,
    )

    rng = Xoshiro(seed)
    model = StandardABM(Union{Person, Doctor}, space; agent_step!, properties, rng)

    # Populate Person agents
    for i in 1:n_agents
        status = (i <= initial_infected) ? infected : susceptible
        rand_age = rand(rng, 1:max_age)
        wears_mask = rand(rng) < mask_probability
        is_vaccinated = rand(rng) < vaccination_probability
        add_agent!(Person, model;
                   status, age = rand_age,
                   wearing_mask = wears_mask, vaccinated = is_vaccinated)
    end

    # Populate Doctor agents (always masked, always vaccinated)
    for _ in 1:n_doctors
        rand_age = rand(rng, 25:max_age)  # doctors are at least 25
        add_agent!(Doctor, model;
                   status = susceptible, age = rand_age,
                   wearing_mask = true, vaccinated = true)
    end

    return model
end

# 7. Display
function Base.show(io::IO, p::ModelParams)
    print(io, "ModelParams(strategy=$(p.strategy), infectiousness=$(p.infectiousness), ",
          "latency=$(p.latency_period), duration=$(p.duration), ",
          "recover=$(p.chance_recover), immunity=$(p.immunity_duration))")
end
