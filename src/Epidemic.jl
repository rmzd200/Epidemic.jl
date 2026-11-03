module Epidemic

using Agents
using Random      

include("agent_model.jl")

export initialize_model, Person, HealthStatus,
       susceptible, exposed, infected, recovered

end