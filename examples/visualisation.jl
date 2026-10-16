# =====================================================================
# Visualisations de la simulation SEIRS
#
# Lancer depuis la racine du projet :
#     julia --project=. examples/visualisation.jl
#
# Produit 4 fichiers dans examples/figures/ :
#   1. courbes_seirs.png        : évolution des 4 compartiments + population
#   2. snapshots_grille.png     : la grille à 4 moments différents
#   3. comparaison_scenarios.png: effet des masques et des vaccins
#   4. animation.mp4            : film de la simulation
# =====================================================================

using Epidemic
using Agents
using CairoMakie

const DIMS = (10, 10)
const OUT  = joinpath(@__DIR__, "figures")
mkpath(OUT)

# ----------------------------------------------------
# Couleurs et noms communs à toutes les figures
# ----------------------------------------------------
const STATUS_ORDER  = [susceptible, exposed, infected, recovered]
const STATUS_LABELS = ["Susceptible", "Exposé", "Infecté", "Guéri"]
const STATUS_COLORS = Dict(
    susceptible => :royalblue,
    exposed     => :orange,
    infected    => :crimson,
    recovered   => :seagreen,
)

# ----------------------------------------------------
# Fonctions de comptage (un seul argument : le modèle)
# ----------------------------------------------------
susceptible_count(m) = count(a -> a.status == susceptible, allagents(m))
exposed_count(m)     = count(a -> a.status == exposed,     allagents(m))
infected_count(m)    = count(a -> a.status == infected,    allagents(m))
recovered_count(m)   = count(a -> a.status == recovered,   allagents(m))
population(m)        = nagents(m)

# ----------------------------------------------------
# Outils pour dessiner les agents sur la grille
# Plusieurs agents peuvent être sur la même case : on décale
# légèrement chaque agent (selon son id) pour les voir tous.
# ----------------------------------------------------
function agent_points(model)
    return [Point2f(a.pos[1] + 0.35 * sin(7.0 * a.id),
                    a.pos[2] + 0.35 * cos(13.0 * a.id)) for a in allagents(model)]
end

agent_colors(model) = [STATUS_COLORS[a.status] for a in allagents(model)]

# `title` peut être un String ou un Observable{String}
function grid_axis(pos; title = "")
    ax = Axis(pos; title, aspect = DataAspect())
    limits!(ax, 0.5, DIMS[1] + 0.5, 0.5, DIMS[2] + 0.5)
    hidedecorations!(ax)
    return ax
end

function status_legend!(pos)
    elements = [MarkerElement(color = STATUS_COLORS[s], marker = :circle, markersize = 14)
                for s in STATUS_ORDER]
    Legend(pos, elements, STATUS_LABELS; orientation = :horizontal)
end

# =====================================================================
# 1. Courbes SEIRS au cours du temps
# =====================================================================
function plot_courbes(; n_steps = 300)
    model = initialize_model(dims = DIMS)
    mdata = [susceptible_count, exposed_count, infected_count,
             recovered_count, population]
    _, df = run!(model, n_steps; mdata)

    fig = Figure(size = (900, 500))
    ax = Axis(fig[1, 1];
        xlabel = "Pas de temps", ylabel = "Nombre d'agents",
        title = "Simulation SEIRS (masques et vaccins actifs)")

    lines!(ax, df.time, df.susceptible_count; label = "Susceptible", color = :royalblue, linewidth = 2.5)
    lines!(ax, df.time, df.exposed_count;     label = "Exposé",      color = :orange,    linewidth = 2.5)
    lines!(ax, df.time, df.infected_count;    label = "Infecté",     color = :crimson,   linewidth = 2.5)
    lines!(ax, df.time, df.recovered_count;   label = "Guéri",       color = :seagreen,  linewidth = 2.5)
    lines!(ax, df.time, df.population;        label = "Population totale",
           color = :gray40, linewidth = 2, linestyle = :dash)

    axislegend(ax; position = :rt)
    save(joinpath(OUT, "courbes_seirs.png"), fig)
    println("✓ courbes_seirs.png")
end

# =====================================================================
# 2. Snapshots de la grille à plusieurs moments
# =====================================================================
function plot_snapshots(; snap_times = [0, 20, 60, 150])
    model = initialize_model(dims = DIMS)
    fig = Figure(size = (1000, 1100))

    t_now = 0
    for (k, t) in enumerate(snap_times)
        t > t_now && step!(model, t - t_now)
        t_now = t

        row, col = fldmod1(k, 2)
        ax = grid_axis(fig[row, col]; title = "t = $t  ($(nagents(model)) agents)")
        scatter!(ax, agent_points(model); color = agent_colors(model), markersize = 11)
    end

    status_legend!(fig[3, 1:2])
    save(joinpath(OUT, "snapshots_grille.png"), fig)
    println("✓ snapshots_grille.png")
end

# =====================================================================
# 3. Comparaison de scénarios : effet des masques et des vaccins
#    Moyenne sur plusieurs graines aléatoires pour lisser le hasard.
# =====================================================================
function mean_infected(; nreps = 10, n_steps = 300, kwargs...)
    curves = zeros(n_steps + 1, nreps)
    for r in 1:nreps
        m = initialize_model(; dims = DIMS, seed = r, kwargs...)
        _, df = run!(m, n_steps; mdata = [infected_count])
        curves[:, r] = df.infected_count
    end
    return vec(sum(curves; dims = 2) ./ nreps)
end

function plot_scenarios(; n_steps = 300)
    scenarios = [
        "Aucune protection"   => (mask_probability = 0.0, vaccination_probability = 0.0),
        "Masques seulement"   => (mask_probability = 0.5, vaccination_probability = 0.0),
        "Vaccins seulement"   => (mask_probability = 0.0, vaccination_probability = 0.6),
        "Masques + vaccins"   => (mask_probability = 0.5, vaccination_probability = 0.6),
    ]
    colors = [:crimson, :orange, :royalblue, :seagreen]

    fig = Figure(size = (900, 500))
    ax = Axis(fig[1, 1];
        xlabel = "Pas de temps", ylabel = "Infectés (moyenne sur 10 simulations)",
        title = "Effet des masques et des vaccins")

    for ((name, params), c) in zip(scenarios, colors)
        curve = mean_infected(; n_steps, params...)
        lines!(ax, 0:n_steps, curve; label = name, color = c, linewidth = 2.5)
    end

    axislegend(ax; position = :rt)
    save(joinpath(OUT, "comparaison_scenarios.png"), fig)
    println("✓ comparaison_scenarios.png")
end

# =====================================================================
# 4. Animation de la grille (mp4)
#    CORRECTION : l'Observable `title` est passé directement à l'Axis
#    à la création (au lieu de `ax.title = title`, interdit par Makie).
# =====================================================================
function make_animation(; n_frames = 200, framerate = 15)
    model = initialize_model(dims = DIMS)

    pts   = Observable(agent_points(model))
    cols  = Observable(agent_colors(model))
    title = Observable("t = 0")

    fig = Figure(size = (750, 820))
    ax = grid_axis(fig[1, 1]; title = title)
    scatter!(ax, pts; color = cols, markersize = 11)
    status_legend!(fig[2, 1])

    record(fig, joinpath(OUT, "animation.mp4"), 1:n_frames; framerate) do t
        step!(model, 1)
        pts[]   = agent_points(model)
        cols[]  = agent_colors(model)
        title[] = "t = $t   |   infectés : $(infected_count(model))   |   population : $(nagents(model))"
    end
    println("✓ animation.mp4")
end

# =====================================================================
# Lancer tout (mets un # devant les lignes que tu ne veux pas)
# =====================================================================
plot_courbes()
plot_snapshots()
plot_scenarios()
make_animation()

println("Terminé. Les figures sont dans : ", OUT) 