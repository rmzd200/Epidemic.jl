using Epidemic
using Agents: run!, allagents
using CairoMakie

# ----------------------------------------------------
# 1. Aggregation & Data Collection
# ----------------------------------------------------
# Each metric takes exactly one argument: the model
susceptible_count(m) = count(a -> a.status == susceptible, allagents(m))
exposed_count(m)     = count(a -> a.status == exposed,     allagents(m))
infected_count(m)    = count(a -> a.status == infected,    allagents(m))
recovered_count(m)   = count(a -> a.status == recovered,   allagents(m))

# ----------------------------------------------------
# 2. Run the Simulation
# ----------------------------------------------------
model = initialize_model()

n_steps = 300

mdata = [susceptible_count, exposed_count, infected_count, recovered_count]

_, df_model = run!(model, n_steps; mdata)

println("Columns: ", names(df_model))
println(first(df_model, 5))

# ----------------------------------------------------
# 3. Visualization with CairoMakie
# ----------------------------------------------------
fig = Figure(size = (900, 500))
ax  = Axis(
    fig[1, 1];
    xlabel = "Step",
    ylabel = "Agent Count",
    title  = "SEIRS Epidemic Simulation (Masks & Vaccines Active)",
)

lines!(ax, df_model.time, df_model.susceptible_count;
       label = "Susceptible", color = :royalblue, linewidth = 2.5)
lines!(ax, df_model.time, df_model.exposed_count;
       label = "Exposed",     color = :orange,    linewidth = 2.5)
lines!(ax, df_model.time, df_model.infected_count;
       label = "Infected",    color = :crimson,   linewidth = 2.5)
lines!(ax, df_model.time, df_model.recovered_count;
       label = "Recovered",   color = :seagreen,  linewidth = 2.5)

axislegend(ax; position = :rt)

save("seirs_simulation.png", fig)
println("Simulation complete — saved to seirs_simulation.png")
