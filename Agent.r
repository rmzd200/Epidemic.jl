# ----------------------------------------------------
# 1. Agent Definition
# ----------------------------------------------------

# ----------------------------------------------------
# 2. Model Initialization
# ----------------------------------------------------

initialize_model = function(
    dims = c(35, 35),
    n_agents = 150,
    initial_infected = 10,
    infectiousness = 0.65,
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
    vaccination_probability = 0.6
) {
  
  
  
  set.seed(seed)
  
  properties = list(
    infectiousness = infectiousness,
    duration = duration,
    chance_recover = chance_recover,
    immunity_duration = immunity_duration,
    birth_rate = birth_rate,
    carrying_capacity = carrying_capacity,
    max_age = max_age,
    mask_effectiveness = mask_effectiveness,
    mask_probability = mask_probability,
    vaccine_effectiveness = vaccine_effectiveness,
    vaccination_probability = vaccination_probability,
    dims = dims
  )
  
  # Populate agents randomly
  
  agents = data.frame(
    id = 1:n_agents, 
    x = sample(1:dims[1], n_agents, replace = TRUE), # on donne à chaque agent une position x aleatoire entre 1 et 35
    y = sample(1:dims[2], n_agents, replace = TRUE),
    status = ifelse(
      1:n_agents <= initial_infected,
      "infected",
      "susceptible"
    ),
    infection_timer = 0,
    immunity_timer = 0,
    age = sample(1:max_age, n_agents, replace = TRUE), #    age aleatoire entre 1 et 110
    wearing_mask = runif(n_agents) < mask_probability, # r unif car on genere des nobmre des nobres entre 0 et 1 c ets la lois uniforme 
    vaccinated = runif(n_agents) < vaccination_probability
  )
  
  model = list(
    agents = agents,
    properties = properties,
    next_id = n_agents + 1
  )
  
  return(model)
}


# ----------------------------------------------------
# 3. Agent Dynamics (Step Function)
# ----------------------------------------------------

agent_step = function(agent_id, model) {
  
  params = model$properties
  
  index = which(model$agents$id == agent_id)
  
  # A. Aging and Natural Death
  
  model$agents$age[index] <- model$agents$age[index] + 1
  
  if (model$agents$age[index] >= params$max_age) {
    
    model$agents <- model$agents[-index, , drop = FALSE]
    
    return(model)
  }
  
  
  # B. Movement (Random walk to neighboring cells)
  
  dx <- sample(c(-1, 0, 1), 1) # -1 à gauche , 0 ne bouge pas , 1 à gauche 
  dy <- sample(c(-1, 0, 1), 1)
  
  model$agents$x[index] <-
    ((model$agents$x[index] - 1 + dx) %% params$dims[1]) + 1
  
  model$agents$y[index] <-
    ((model$agents$y[index] - 1 + dy) %% params$dims[2]) + 1
  
  
  # C. Virus Progression & Recovery
  
  if (model$agents$status[index] == "infected") {
    
    model$agents$infection_timer[index] <-
      model$agents$infection_timer[index] + 1
    
    if (model$agents$infection_timer[index] >= params$duration) {
      
      if (runif(1) < params$chance_recover) {
        
        model$agents$status[index] <- "immune"
        model$agents$infection_timer[index] <- 0
        model$agents$immunity_timer[index] <- 0
        
      } else {
        
        model$agents <- model$agents[-index, , drop = FALSE]
        
        return(model)
      }
    }
    
  } else if (model$agents$status[index] == "immune") {
    
    model$agents$immunity_timer[index] <-
      model$agents$immunity_timer[index] + 1
    
    if (model$agents$immunity_timer[index] >= params$immunity_duration) {
      
      model$agents$status[index] <- "susceptible"
      model$agents$immunity_timer[index] <- 0
    }
  }
  
  
  # D. Transmission: An infected agent infects susceptible
  # co-located neighbors / case of Wearing Mask
  
  if (model$agents$status[index] == "infected") {
    
    # Find all agents occupying the same patch / grid cell
    
    neighbors <- which(
      model$agents$x == model$agents$x[index] &
      model$agents$y == model$agents$y[index]
    )
    
    for (neighbor_index in neighbors) {
      
      if (model$agents$status[neighbor_index] == "susceptible") {
        
        # Normal probability of transmission
        
        transmission_probability <- params$infectiousness
        
        if (model$agents$wearing_mask[index]) {
          
          transmission_probability <-
            transmission_probability *
            (1 - params$mask_effectiveness)
        }
        
        
        if (model$agents$wearing_mask[neighbor_index]) {
          
          transmission_probability <-
            transmission_probability *
            (1 - params$mask_effectiveness)
        }
        
        
        if (model$agents$vaccinated[neighbor_index]) {
          
          transmission_probability <-
            transmission_probability *
            (1 - params$vaccine_effectiveness)
        }
        
        
        if (runif(1) < transmission_probability) {
          
          model$agents$status[neighbor_index] <- "infected"
          model$agents$infection_timer[neighbor_index] <- 0
        }
      }
    }
  }
  
  
  # E. Reproduction (Demographic Birth)
  
  if (nrow(model$agents) < params$carrying_capacity) {
    
    if (runif(1) < params$birth_rate) {
      
      # Newborn placed at the parent's position
      
      new_agent <- data.frame(
        id = model$next_id,
        x = model$agents$x[index],
        y = model$agents$y[index],
        status = "susceptible",
        infection_timer = 0,
        immunity_timer = 0,
        age = 0,
        wearing_mask = FALSE,
        vaccinated = FALSE
      )
      
      model$agents <- rbind(model$agents, new_agent)
      
      model$next_id <- model$next_id + 1
    }
  }
  
  return(model)
}

