##using Epedimc #erreur 
using Agents
using Random
using CairoMakie
using DataFrames
# ----------------------------------------------------
# 1. Agent Definition
# ----------------------------------------------------
@enum HealthStatus susceptible infected immune

@agent struct Person(GridAgent{2})
    status::HealthStatus = susceptible
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
    dims = (35, 35),
    n_agents = 150,
    initial_infected = 10,
    infectiousness = 0.65,
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
    # NetLogo uses a periodic toroidal grid where multiple agents can share a patch
    space = GridSpace(dims; periodic = true)
    
    properties = ModelParams(
        infectiousness,
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
    
    rng = Xoshiro(seed) # Generate randomly
    model = StandardABM(Person, space; agent_step!, properties, rng)

    # Populate agents randomly
    for i in 1:n_agents
        status = (i <= initial_infected) ? infected : susceptible
        rand_age = rand(rng, 1:max_age)
        wears_mask=rand(rng)<mask_probability
        is_vaccinated=rand(rng)< vaccination_probability
        add_agent_single!(model; status = status, age = rand_age,wearing_mask=wears_mask,vaccinated=is_vaccinated)
    end

    return model
end

# function 1:Move an agent randomly
 function move_agent!(agent::Person,model)
    randomwalk!(agent,model)
 end
# function 2: Aging and natural death
function aging_and_death!(agent::Person,model)
         agent.age+=1
        params = abmproperties(model)
        if agent.age >= params.max_age
            remove_agent!(agent, model)
         return  true
       end

        return false
        
 end 
#function 3 : update infection and immunity 
function update_health!(agent::Person,model)
    params = abmproperties(model) # agent based model propreties
   if agent.status == infected
        agent.infection_timer += 1
      if agent.infection_timer >= params.duration
            if rand(abmrng(model)) < params.chance_recover
                agent.status = immune
                agent.infection_timer = 0
                agent.immunity_timer = 0
            else
                remove_agent!(agent, model)
                return true
            end
        end    
      elseif agent.status == immune
         agent.immunity_timer += 1
         if agent.immunity_timer >= params.immunity_duration
            agent.status = susceptible
            agent.immunity_timer = 0
         end    
        end
        return false
    end    
#function 4: transmission of the virus 
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
                    neighbor.status = infected
                    neighbor.infection_timer = 0
                
                end
            end
        end
    end 
    
end    
# function 5: Reproduction
function reproduce!(agent::Person,model) 
     params = abmproperties(model) 
    if nagents(model) < params.carrying_capacity
        if rand(abmrng(model)) < params.birth_rate
            # Newborn placed at the parent's position
            add_agent!(agent.pos, model; status = susceptible, age = 0,wearing_mask=false,vaccinated=false)
        end
    end 
end    
# ----------------------------------------------------
# 3. Agent Dynamics (Step Function)
# ----------------------------------------------------
function agent_step!(agent::Person, model)
  params = abmproperties(model) 

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

# Create the model
model = initialize_model()

# Count the total number of agents
println("Total population: ", nagents(model))

# Count agents by health status
S = count(a -> a.status == susceptible, allagents(model))
I = count(a -> a.status == infected, allagents(model))
R = count(a -> a.status == immune, allagents(model))

println("Susceptible: ", S)
println("Infected: ", I)
println("Immune: ", R)

# Check if the population count is correct
println("Population check: ", S + I + R == nagents(model))

# Run the simulation for 50 ticks
for t in 1:50
  # Move the simulation forward by one tick
    step!(model, 1)    
  # Count agents by health status
  local S = count(a -> a.status == susceptible, allagents(model))
  local I = count(a -> a.status == infected, allagents(model))
 local R = count(a -> a.status == immune, allagents(model))  
 #Total Agents
  local N=nagents(model)
 #check population consistency
 @assert S+I+R == N
 # Display the results
    println("Tick: ", t," | S: ", S," | I: ", I," | R: ", R," | Total: ", N)
end

