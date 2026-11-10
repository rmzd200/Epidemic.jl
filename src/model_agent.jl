# ============================================================
# 1. Agent Definitions
# ============================================================
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
    wearing_mask::Bool   = true    # doctors wear a mask by default
    vaccinated::Bool     = true    # doctors are vaccinated by default
    ppe_protection::Float64 = 0.9  # PPE gives extra protection beyond masks
end

# Doctors are adults: this is the youngest age a doctor can be created with.
const DOCTOR_MIN_AGE = 25

# ============================================================
# 2. Transmission Strategies
# ============================================================
abstract type TransmissionStrategy end
struct BasicTransmission <: TransmissionStrategy end
struct ProtectedTransmission <: TransmissionStrategy end

"""
    transmission_probability(strategy, source, target, params) -> Float64

Return the probability that `source` infects `target` under the given `strategy`.

To add a custom strategy, subtype [`TransmissionStrategy`](@ref) and implement
this method (note the `Epidemic.` prefix, which is required to extend it
from outside the module):

    struct MyStrategy <: TransmissionStrategy end
    Epidemic.transmission_probability(::MyStrategy, source, target, params) = ...
"""
function transmission_probability end

"""
    emission_factor(agent, params) -> Float64

Multiplier (in [0, 1]) applied to the infection probability because of the
protection worn by the *infected* agent (it reduces outward spread).
Implement one method per agent type.
"""
function emission_factor end

"""
    susceptibility_factor(agent, params) -> Float64

Multiplier (in [0, 1]) applied to the infection probability because of the
protection of the *susceptible* agent (it reduces how easily it is infected).
Implement one method per agent type.
"""
function susceptibility_factor end

# --- Building blocks shared by all agent types (they only read fields) ---
mask_factor(agent, params)    = agent.wearing_mask ? 1 - params.mask_effectiveness : 1.0
vaccine_factor(agent, params) = agent.vaccinated   ? 1 - params.vaccine_effectiveness : 1.0

# --- Dispatch on the agent type: one method per agent type ---
emission_factor(agent::Person, params) = mask_factor(agent, params)
emission_factor(agent::Doctor, params) =
    mask_factor(agent, params) * (1 - agent.ppe_protection)

susceptibility_factor(agent::Person, params) =
    mask_factor(agent, params) * vaccine_factor(agent, params)
susceptibility_factor(agent::Doctor, params) =
    mask_factor(agent, params) * vaccine_factor(agent, params) * (1 - agent.ppe_protection)

# --- Strategy × source type × target type ---

# BasicTransmission: raw infectiousness, ignores masks/vaccines/PPE
transmission_probability(::BasicTransmission, source, target, params) =
    params.infectiousness

# ProtectedTransmission: combines the factors of both agents. Adding a new
# agent type only requires its own emission_factor / susceptibility_factor.
transmission_probability(::ProtectedTransmission, source, target, params) =
    params.infectiousness *
    emission_factor(source, params) *
    susceptibility_factor(target, params)

# ============================================================
# 3. Model Parameters (parametric on strategy for type stability)
# ============================================================
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

# ============================================================
# 4. Agent Dynamics
# ============================================================

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
            # Any adult agent (Person or Doctor) can be a parent;
            # newborns are always Person.
            add_agent!(agent.pos, Person, model;
                       status = susceptible, age = 0,
                       wearing_mask = wears_mask, vaccinated = is_vaccinated)
        end
    end
    return nothing
end

# ============================================================
# 5. Main Step Function
# ============================================================
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

# ============================================================
# 6. Model Initialization
# ============================================================

# Throw an ArgumentError (not @assert, which can be compiled out and has
# poor messages) when a parameter check fails.
_require(cond::Bool, msg::AbstractString) = cond || throw(ArgumentError(msg))
_is_probability(x) = 0 <= x <= 1

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
    # --- Validate parameters ---
    _require(n_agents >= 0, "n_agents must be ≥ 0 (got $n_agents)")
    _require(n_doctors >= 0, "n_doctors must be ≥ 0 (got $n_doctors)")
    _require(0 <= initial_infected <= n_agents,
             "initial_infected must be between 0 and n_agents (got $initial_infected, n_agents = $n_agents)")
    _require(n_agents + n_doctors <= carrying_capacity,
             "n_agents + n_doctors ($(n_agents + n_doctors)) must not exceed carrying_capacity ($carrying_capacity)")
    _require(latency_period > 0, "latency_period must be > 0 (got $latency_period)")
    _require(duration > 0, "duration must be > 0 (got $duration)")
    _require(immunity_duration > 0, "immunity_duration must be > 0 (got $immunity_duration)")
    _require(max_age > 0, "max_age must be > 0 (got $max_age)")
    _require(n_doctors == 0 || max_age >= DOCTOR_MIN_AGE,
             "max_age must be ≥ $DOCTOR_MIN_AGE when n_doctors > 0 (got $max_age)")
    _require(_is_probability(infectiousness), "infectiousness must be in [0, 1] (got $infectiousness)")
    _require(_is_probability(chance_recover), "chance_recover must be in [0, 1] (got $chance_recover)")
    _require(_is_probability(birth_rate), "birth_rate must be in [0, 1] (got $birth_rate)")
    _require(_is_probability(mask_probability), "mask_probability must be in [0, 1] (got $mask_probability)")
    _require(_is_probability(mask_effectiveness), "mask_effectiveness must be in [0, 1] (got $mask_effectiveness)")
    _require(_is_probability(vaccination_probability), "vaccination_probability must be in [0, 1] (got $vaccination_probability)")
    _require(_is_probability(vaccine_effectiveness), "vaccine_effectiveness must be in [0, 1] (got $vaccine_effectiveness)")

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

    # Populate Doctor agents (masked and vaccinated by default)
    for _ in 1:n_doctors
        rand_age = rand(rng, DOCTOR_MIN_AGE:max_age)
        add_agent!(Doctor, model; status = susceptible, age = rand_age)
    end

    return model
end
