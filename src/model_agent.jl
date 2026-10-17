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
# ----------------------------------------------------
# 2. Model Initialization
# ----------------------------------------------------
struct ModelParams
    infectiousness::Float64   # Probability of infection on contact (e.g., 0.65)
    latency_period::Int       # Duration of exposure before infection
    duration::Int             # Duration of infection in ticks (e.g., 20)
    chance_recover::Float64   # Probability of recovery vs death (e.g., 0.50)
    immunity_duration::Int    # Ticks immune after recovery (e.g., 50)
    birth_rate::Float64       # Probability of reproduction per tick (e.g., 0.01)
    carrying_capacity::Int    # Max population cap (e.g., 300)
    max_age::Int              # Max lifetime in ticks (e.g., 200)
    mask_effectiveness::Float64 # Mask efficacity
    mask_probability::Float64 # Probabilty that a person wear a mask
    vaccine_effectiveness::Float64 # efficacity of the vaccine
    vaccination_probability::Float64
end

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
    vaccination_probability= 0.6
)   
    # validate model parameters
    @assert 0 <= initial_infected <= n_agents <= carrying_capacity
    @assert latency_period>0
    @assert  duration >0
    @assert  immunity_duration>0 
    @assert max_age>0

    @assert  0<= infectiousness<=1
    @assert  0<= chance_recover<=1
    @assert  0<= birth_rate<=1
    @assert  0<= mask_probability<=1
    @assert  0<= mask_effectiveness<=1
    @assert  0<= vaccination_probability<=1  
    @assert  0<= vaccine_effectiveness<=1
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
        vaccination_probability
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
#function D: transmission of the virus 
function transmit_infection!(agent::Person , model)
    params = abmproperties(model) 
    if agent.status == infected
        # Find all agents occupying the same patch / grid cell
        for neighbor in agents_in_position(agent, model)
            if neighbor.status == susceptible 
                # Normal probabilty of transmission : 
                transmission_probability=params.infectiousness

                if agent.wearing_mask
                    transmission_probability*=(1-params.mask_effectiveness)
                end
                
                
                if neighbor.wearing_mask # If the susceptible person wear also a mask
                    transmission_probability*=(1-params.mask_effectiveness)
                end


                if neighbor.vaccinated  # If the susceptible  is vaccinated 
                    transmission_probability *=(1- params.vaccine_effectiveness)
                end    

    

                if rand(abmrng(model)) < transmission_probability   
                    neighbor.status = exposed
                    neighbor.exposure_timer = 0
                
                end
            end
        end
    end 
    
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
