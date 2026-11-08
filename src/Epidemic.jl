"""
    Epidemic
 
Agent-based SEIRS epidemic model built on Agents.jl.
 
Extension points (implement from outside the module with the `Epidemic.` prefix):
 
- [`transmission_probability`](@ref): add a new [`TransmissionStrategy`](@ref).
- [`emission_factor`](@ref) / [`susceptibility_factor`](@ref): add a new agent type.
 
Quick start:
 
    using Epidemic, Agents
    model = initialize_model(n_agents = 150, n_doctors = 5)
    step!(model, 100)
"""
module Epidemic
 
using Agents
using Random
 
include("model_agent.jl")
 
# Public API: types
export HealthStatus, susceptible, exposed, infected, recovered
export Person, Doctor, ModelParams
 
# Public API: strategies (users subtype TransmissionStrategy to extend)
export TransmissionStrategy, BasicTransmission, ProtectedTransmission
export transmission_probability
 
# Public API: per-agent-type hooks (users add methods for their own agent types)
export emission_factor, susceptibility_factor
 
# Public API: model construction and stepping
export initialize_model, agent_step!
 
# Public API: individual dynamics steps
export random_step!, aging_and_death!, update_health!,
       transmit_infection!, reproduce!
 
end # module
 