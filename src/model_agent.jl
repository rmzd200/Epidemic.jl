# ----------------------------------------------------
# 1. Agent Definition
# ----------------------------------------------------
@enum HealthStatus susceptible exposed infected recovered

@agent struct Person(GridAgent{2})
    status::HealthStatus = susceptible
    exposure_timer::Int = 0
    infection_timer::Int = 0
    immunity_timer::Int  = 0
    age::Int             = 0
    wearing_mask::Bool   = false 
    vaccinated::Bool    = false
end

#2. Transmission strategies
 abstract type TransmissionStrategy end
 struct BasicTransmission <:TransmissionStrategy end
 struct ProtectedTransmission <:TransmissionStrategy  end


# 3. Model Initialization
struct ModelParams
    infectiousness::Float64   # Probability of infection on contact 
    latency_period::Int       # Duration of exposure before infection
    duration::Int             # Duration of infection in ticks 
    chance_recover::Float64   # Probability of recovery vs death 
    immunity_duration::Int    # Ticks immune after recovery 
    birth_rate::Float64       # Probability of reproduction per tick 
    carrying_capacity::Int    # Max population cap 
    max_age::Int              # Max lifetime in ticks 
    mask_effectiveness::Float64 # Mask efficacity
    mask_probability::Float64 # Probabilty that a person wear a mask
    vaccine_effectiveness::Float64 # efficacity of the vaccine
    vaccination_probability::Float64
    strategy::Type{<:TransmissionStrategy}
end

#Paremter validation:
 function _require(condition:: Bool,message::AbstractString)
    condition || throw(ArgumentError(message))
    return nothing
 end
_is_probability(x::Real)=0<=x<=1

function initialize_model(;
    dims = (10, 10),
    n_agents = 150,
    initial_infected = 10,
    infectiousness = 0.65,
    latency_period= 8,
    duration = 25,
    chance_recover = 0.60,
    immunity_duration = 40,
    birth_rate = 0.015,
    carrying_capacity = 300,
    max_age = 110,
    seed = 42 ,
    mask_probability= 0.5 ,
    mask_effectiveness= 0.5,
    vaccine_effectiveness= 0.7 , 
    vaccination_probability= 0.6,
    strategy::Type{<:TransmissionStrategy}=ProtectedTransmission
)   

  
    
# validate population
_require(n_agents >= 0,"n_agents must be >= 0 (got $n_agents)")
_require(initial_infected >=0,"initial infected must be >=0(got $initial_infected)")
_require(initial_infected <= n_agents, "initial infected must be <=n_agents")
_require(n_agents <= carrying_capacity,"n_agents must be <=carrying_capacity")

#validate duration
_require(latency_period > 0,"letency_period must be positive(got $latency_period)")
_require(duration > 0, "duration must be positive(got $duration)")
_require(immunity_duration > 0,"imunity_duration must be positive (got $immunity_duration)")
_require(max_age > 0,"max age must be positive(got_max_age)")


#validate probabilities
for (name,value)in (
     ("infectiousness", infectiousness),
     ("chance_recover",chance_recover),    
     ("birth_rate",birth_rate),
     ("mask_probability",mask_probability),
     ("mask_effectiveness",mask_effectiveness),
     (" vaccination_probability", vaccination_probability),
     ("vaccine_effectiveness",vaccine_effectiveness)
)
   _require(_is_probability(value),
   "$name must be between o and 1 (got $value)")
end

    # NetLogo uses a periodic toroidal grid where multiple agents can share a patch
    space = GridSpace(dims; periodic = true)
    
    properties = ModelParams(
        infectiousness,
        latency_period,
        duration,
        chance_recover,
        immunity_duration,
        birth_rate,
        carrying_capacity,
        max_age,
        mask_effectiveness,
        mask_probability ,
        vaccine_effectiveness ,
        vaccination_probability,
        strategy
    )
    
    rng = Xoshiro(seed) # Create a reproducible random number generator
    model = StandardABM(Person, space; agent_step!, properties, rng)

    # Populate agents randomly
    for i in 1:n_agents
        status = (i <= initial_infected) ? infected : susceptible
        rand_age = rand(rng, 1:max_age)
        wears_mask=rand(rng)<mask_probability
        is_vaccinated=rand(rng)< vaccination_probability
        add_agent!(model; status = status, age = rand_age,wearing_mask=wears_mask,vaccinated=is_vaccinated)
    end

    return model
end

# function A:Move an agent randomly
function move_agent!(agent::Person,model)
    randomwalk!(agent,model)
end
# function B: Aging and natural death
function aging_and_death!(agent::Person,model)
         agent.age+=1
        params = abmproperties(model)
        if agent.age >= params.max_age
            remove_agent!(agent, model)
         return  true
       end

        return false
        
end 

# Function c: Update exposure, infection and immunity
function update_health!(agent::Person, model)
    params = abmproperties(model)

    # E -> I: End of exposure period
    if agent.status == exposed
        agent.exposure_timer += 1

        if agent.exposure_timer >= params.latency_period
            agent.status = infected
            agent.exposure_timer = 0
            agent.infection_timer = 0
        end

    # I -> R: Recovery or death
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

    # R -> S: Loss of immunity
    elseif agent.status == recovered
        agent.immunity_timer += 1

        if agent.immunity_timer >= params.immunity_duration
            agent.status = susceptible
            agent.immunity_timer = 0
        end
    end

    return false
end

# Same function for different type of infection 
function transmission_probability( 
    source::Person,  # Infected agent transmitting the virus
    target::Person,  # Susceptible agent at risk of infection
    params::ModelParams,
    ::Type{BasicTransmission}
)  
  return params.infectiousness
end
function transmission_probability( 
    source::Person,
    target::Person,
    params::ModelParams,
    ::Type{ProtectedTransmission}
    )
    infection_probability=params.infectiousness
    
    if source.wearing_mask
        infection_probability*=(1-params.mask_effectiveness)
    end
    if target.wearing_mask
        infection_probability*=(1-params.mask_effectiveness)
    end    
    if target.vaccinated
        infection_probability*=(1-params.vaccine_effectiveness)
    end    
    return infection_probability
end  


#function D: transmission of the virus 
function transmit_infection!(agent::Person , model)
    params = abmproperties(model) 
    if agent.status == infected
        # Find all agents occupying the same patch / grid cell
        for neighbor in agents_in_position(agent, model)
            if neighbor.status == susceptible 
                infection_probability=transmission_probability(agent,neighbor, params,params.strategy)
                if rand(abmrng(model))<infection_probability
                    neighbor.status=exposed
                    neighbor.exposure_timer=0
                end    
            end
        end
    end 
    return nothing
end    

# function E: Reproduction
function reproduce!(agent::Person,model) 
     params = abmproperties(model) 
    if nagents(model) < params.carrying_capacity
        if rand(abmrng(model)) < params.birth_rate
            wears_mask=rand(abmrng(model))<params.mask_probability
            is_vaccinated=rand(abmrng(model))<params.vaccination_probability

            # Newborn placed at the parent's position
            add_agent!(agent.pos, model; status = susceptible, age = 0,wearing_mask=wears_mask,vaccinated=is_vaccinated)

        end
    end
  return nothing 
end    
# ----------------------------------------------------
# 3. Agent Dynamics (Step Function)
# ----------------------------------------------------
function agent_step!(agent::Person, model)

    # A. Aging and Natural Death
    if  aging_and_death!(agent,model)
        return
   end 

    # B. Movement (Random walk to neighboring cells, including diagonals)
    move_agent!(agent,model)

    # C. Virus Progression & Recovery
    if update_health!(agent,model)
        return
    end
    # D. Transmission: An infected agent infects susceptible co-located neighbors /case of Wearing Mask 
     transmit_infection!(agent,model)
                
    # E. Reproduction (Demographic Birth)
    reproduce!(agent,model)
end
