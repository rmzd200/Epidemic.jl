module Epidemic

using Agents
using Random

include("model_agent.jl")

# Public API — types
export HealthStatus, susceptible, exposed, infected, recovered
export Person, Doctor, ModelParams

# Public API — strategies (users subtype TransmissionStrategy to extend)
export TransmissionStrategy, BasicTransmission, ProtectedTransmission
export transmission_probability

# Public API — functions
export initialize_model, agent_step!
export random_step!, aging_and_death!, update_health!,
       transmit_infection!, reproduce!

end
