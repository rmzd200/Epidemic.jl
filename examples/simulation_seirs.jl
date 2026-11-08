using Epidemic
using Agents
using Printf
using Statistics


# 1. Simulation settings

const N_TICKS     = 100   # length of each simulation
const PRINT_EVERY = 10    # print one row of the table every N ticks
const SEED        = 42    # seed of the detailed single runs
const N_SEEDS     = 20    # number of seeds for the multi-seed comparison

# 2. Count agents by health status
function count_health_status(model)
    S = E = I = R = 0

    for agent in allagents(model)
        if agent.status == susceptible
            S += 1
        elseif agent.status == exposed
            E += 1
        elseif agent.status == infected
            I += 1
        elseif agent.status == recovered
            R += 1
        end
    end

    N = nagents(model)

    # Every agent must belong to exactly one health state
    S + E + I + R == N || error("Population count mismatch: S+E+I+R = $(S + E + I + R) but N = $N")

    return (S = S, E = E, I = I, R = R, N = N)
end

# 3. Run one SEIRS simulation
function run_simulation!(model, n_ticks::Int; label = "", verbose = true)
    n_ticks >= 0 || throw(ArgumentError("n_ticks must be ≥ 0 (got $n_ticks)"))
    strategy = abmproperties(model).strategy

    if verbose
        println("\n=== ", label, "  [", nameof(typeof(strategy)), "] ===")
        @printf("%5s %6s %6s %6s %6s %6s\n", "tick", "S", "E", "I", "R", "N")
    end

    # Attack rate bookkeeping: which agents were ever non-susceptible,
    # separately for Person and Doctor (initial cases are excluded).
    initial_cases = Set(a.id for a in allagents(model) if a.status != susceptible)
    seen = Dict{Int,Symbol}()   # every agent observed (id => :person / :doctor)
    hit  = Dict{Int,Symbol}()   # agents observed exposed, infected or recovered

    final = count_health_status(model)
    peak_infected = final.I
    peak_tick = 0

    for tick in 0:n_ticks
        counts = count_health_status(model)

        if verbose && (tick % PRINT_EVERY == 0 || tick == n_ticks)
            @printf("%5d %6d %6d %6d %6d %6d\n",
                    tick, counts.S, counts.E, counts.I, counts.R, counts.N)
        end

        # Track the maximum number of infected agents
        if counts.I > peak_infected
            peak_infected = counts.I
            peak_tick = tick
        end
        final = counts

        for a in allagents(model)
            a.id in initial_cases && continue
            k = a isa Doctor ? :doctor : :person
            seen[a.id] = k
            a.status != susceptible && (hit[a.id] = k)
        end

        # Advance one tick, except after the final observation
        tick < n_ticks && step!(model, 1)
    end

    function attack_rate(k)
        n = count(==(k), values(seen))
        return n == 0 ? NaN : count(==(k), values(hit)) / n
    end

    return (
        strategy = nameof(typeof(strategy)),
        final = final,
        peak_infected = peak_infected,
        peak_tick = peak_tick,
        attack_person = attack_rate(:person),
        attack_doctor = attack_rate(:doctor),
    )
end

# 4. Scenarios to compare
scenarios = [
    ("Basic transmission",     (strategy = BasicTransmission(),)),
    ("Protected transmission", (strategy = ProtectedTransmission(),)),
    ("Protected + 20 doctors", (strategy = ProtectedTransmission(), n_doctors = 20)),
]

# 5. Detailed single run per scenario (one seed, full table)
println("#"^60)
println("# PART 1: detailed runs (seed = $SEED, $N_TICKS ticks)")
println("#"^60)

single_results = Dict{String,Any}()
for (label, kw) in scenarios
    model = initialize_model(; seed = SEED, kw...)
    single_results[label] = run_simulation!(model, N_TICKS; label = label)
end

println("\nSummary of the detailed runs:")
for (label, _) in scenarios
    r = single_results[label]
    @printf("  %-24s peak I = %3d (tick %3d) | final: S=%d E=%d I=%d R=%d N=%d\n",
            label, r.peak_infected, r.peak_tick,
            r.final.S, r.final.E, r.final.I, r.final.R, r.final.N)
end

# 6. Multi-seed comparison (a single run is noisy)
println("\n", "#"^60)
println("# PART 2: $N_SEEDS seeds per scenario (mean ± sd)")
println("#"^60)

avg(f, runs) = (xs = filter(!isnan, [f(r) for r in runs]); isempty(xs) ? NaN : mean(xs))
pct(x) = isnan(x) ? "    -" : @sprintf("%5.1f%%", 100x)

multi_results = Dict{String,Any}()
for (label, kw) in scenarios
    multi_results[label] = [
        run_simulation!(initialize_model(; seed = s, kw...), N_TICKS; verbose = false)
        for s in 1:N_SEEDS
    ]
end

@printf("\n%-24s %14s %10s %8s %9s %9s\n",
        "scenario", "peak infected", "peak tick", "final N", "attack P", "attack D")
for (label, _) in scenarios
    runs = multi_results[label]
    peaks = [r.peak_infected for r in runs]
    @printf("%-24s %6.1f ± %5.1f %10.1f %8.1f %9s %9s\n",
            label, mean(peaks), std(peaks),
            avg(r -> r.peak_tick, runs),
            avg(r -> r.final.N, runs),
            pct(avg(r -> r.attack_person, runs)),
            pct(avg(r -> r.attack_doctor, runs)))
end
println("\n(attack P / D = share of Persons / Doctors that were ever exposed, initial cases excluded)")

# 7. Sanity checks: what a working model should show
println("\n", "#"^60)
println("# PART 3: sanity checks")
println("#"^60)

check(cond, msg) = println(cond ? "  ✓ " : "  ✗ ", msg)

peak_of(label) = mean(r.peak_infected for r in multi_results[label])

check(peak_of("Protected transmission") < peak_of("Basic transmission"),
      "Masks + vaccines lower the mean epidemic peak")

check(all(r.final.N <= 300 for runs in values(multi_results) for r in runs),
      "Population never exceeds the carrying capacity (300)")

doc_runs = multi_results["Protected + 20 doctors"]
check(avg(r -> r.attack_doctor, doc_runs) < avg(r -> r.attack_person, doc_runs),
      "Doctors (mask + vaccine + PPE) are exposed less often than Persons")

check(all(r.peak_infected > 0 for runs in values(multi_results) for r in runs),
      "Every run has infected agents (the epidemic starts)")