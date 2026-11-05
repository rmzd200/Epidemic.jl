
using Epidemic
using Agents


# 1. Simulation settings
const N_TICKS = 50
const SEED = 42

# 2. Count agents by health status
function count_health_status(model)
    S = 0
    E = 0
    I = 0
    R = 0

    for agent in allagents(model)
        if agent.status == Epidemic.susceptible
            S += 1
        elseif agent.status == Epidemic.exposed
            E += 1
        elseif agent.status == Epidemic.infected
            I += 1
        elseif agent.status == Epidemic.recovered
            R += 1
        else
            error(
                "Unknown status for agent $(agent.id): $(agent.status)")
        end
    end

    N = nagents(model)

    # Every agent must belong to exactly one health state
    @assert S + E + I + R == N "Population count mismatch"

    return (S = S, E = E, I = I, R = R, N = N)
end

# 3. Run a SEIRS simulation

function run_simulation!(model, n_ticks::Int)
    n_ticks >= 0 || throw(ArgumentError("n_ticks must be positive"))
    strategy = abmproperties(model).strategy
    @show strategy
  

    initial = count_health_status(model)
    peak_infected = initial.I
    peak_tick = 0
    final = initial

    for tick in 0:n_ticks
        # Collect population statistics
        counts = count_health_status(model)

        # Display the current state
        if tick %5==0 || tick==n_ticks
        @show tick counts
        end
        # Track the maximum number of infected agents
        if counts.I > peak_infected
            peak_infected = counts.I
            peak_tick = tick
        end

        final = counts

        # Advance one tick, except after the final observation
        if tick < n_ticks
            step!(model, 1)
        end
    end

    # Simulation summary
    return (strategy=strategy ,final = final, peak_infected = peak_infected,peak_tick = peak_tick )
end


# 4. Initialize models

model_basic = initialize_model(
    seed = SEED,
    strategy = Epidemic.BasicTransmission
)

model_protected = initialize_model(
    seed = SEED,
    strategy = Epidemic.ProtectedTransmission
)


# 5. Run both simulations
basic_results = run_simulation!(model_basic, N_TICKS)
protected_results = run_simulation!(model_protected, N_TICKS)

# 6. Compare simulation results
@show basic_results
@show protected_results