# Simulation d'épidémie avec une interface web


using Epidemic
using Agents
using Bonito
using WGLMakie

WGLMakie.activate!()
set_theme!(theme_dark())

# ---------- Le style (CSS) ----------
css = """
/* La page : fond sombre avec un peu de violet en haut à gauche */
body { margin:0; padding:30px; color:white; font-family:Arial, sans-serif;
       background:linear-gradient(135deg, #2a1a5e, #0d1230 40%, #0b1026); }

/* L'en-tête avec le logo et le titre */
.entete { display:flex; align-items:center; padding-bottom:25px; margin-bottom:25px;
          border-bottom:1px solid #2c3260; }
.logo { width:90px; height:90px; font-size:50px; text-align:center; line-height:90px;
        background:#1d2447; border:1px solid #5b4b9a; border-radius:22px; margin-right:25px; }
.titre { margin:0; font-size:56px; color:#b8a4f0; }
.sous-titre { margin:5px 0 0 0; color:#aab4d4; letter-spacing:1px; text-transform:uppercase; }

/* Les cartes */
.carte { background:#131a3a; border:1px solid #3a3f78; border-radius:24px;
         padding:20px; margin-bottom:20px; }
.carte-titre { margin:0 0 20px 0; font-size:15px; color:#a99bf0;
               text-transform:uppercase; letter-spacing:2px; }

/* Les curseurs */
.val { float:right; background:#1d2a4d; color:#7dd3f0; padding:2px 10px;
       border-radius:10px; font-weight:bold; }
input[type=range] { width:100%; accent-color:#7dd3f0; }

/* Les boutons */
button { background:#1e2547 !important; color:white !important; border:1px solid #353b66 !important;
         border-radius:14px !important; padding:14px 26px !important; margin-right:10px;
         font-size:18px !important; font-weight:bold !important; cursor:pointer; }
button:hover { background:#2a3262 !important; }
.violet button { background:linear-gradient(#6d3fe0, #8a5cf0) !important; border:none !important; }
.violet button:hover { opacity:0.85; }

/* L'état de la simulation */
.pill { display:inline-block; padding:8px 16px; border-radius:20px;
        background:#1a2144; border:1px solid #4a4f80; font-weight:bold; }
.message { font-size:20px; font-weight:bold; border:2px solid #5a50a8; }

/* Les cartes de chiffres */
.stat { flex:1; margin-bottom:0; padding:15px; border-top:4px solid; }
.emoji { font-size:30px; }
.chiffre { font-size:50px; font-weight:bold; }
.nom { font-size:13px; color:#aab4d4; text-transform:uppercase; letter-spacing:2px; }
"""

# ---------- Fonctions ----------

# Compte les agents dans chaque état : [sains, exposés, infectés, guéris]
function compter(model)
    n = [0, 0, 0, 0]
    for a in allagents(model)
        n[Int(a.status) + 1] += 1
    end
    return n
end

# Couleur de chaque état (pour la grille)
couleur_etat = Dict(susceptible => :deepskyblue, exposed => :orange,
                    infected => :crimson, recovered => :mediumseagreen)

# Message qui résume la situation
function message_etat(n)
    if sum(n) == 0
        return "💀 Toute la population a disparu"
    elseif n[2] + n[3] == 0
        return "L'épidémie est terminée"
    elseif n[3] > 0.3 * sum(n)
        return "🚨 Pic épidémique : plus de 30 % d'infectés !"
    else
        return "Épidémie en cours"
    end
end

# Un curseur avec son nom et sa valeur
function curseur(nom, plage, defaut)
    s = Bonito.Slider(plage; value = defaut)
    ligne = DOM.div(nom, DOM.span(map(string, s.value); class = "val"), s;
                    style = "margin-bottom:22px;")
    return s, ligne
end

# Une carte de chiffre : emoji + nombre + nom, avec une couleur
function carte_stat(emoji, nom, couleur, nombre)
    return DOM.div(
        DOM.div(emoji; class = "emoji"),
        DOM.div(nombre; class = "chiffre",
                style = "color:$couleur; text-shadow:0 0 15px $couleur;"),
        DOM.div(nom; class = "nom");
        class = "carte stat",
        style = "border-top-color:$couleur;",
    )
end

# ---------- L'application ----------
app = App() do session

    # Les curseurs
    s_agents,   l_agents   = curseur("Nombre d'agents",      10:300,       150)
    s_infectes, l_infectes = curseur("Infectés au départ",   0:50,         10)
    s_contag,   l_contag   = curseur("Contagiosité",         0.0:0.01:1.0, 0.65)
    s_latence,  l_latence  = curseur("Période de latence",   1:30,         8)
    s_duree,    l_duree    = curseur("Durée de l'infection", 1:60,         25)
    s_guerison, l_guerison = curseur("Proba. de guérison",   0.0:0.01:1.0, 0.6)
    s_immunite, l_immunite = curseur("Durée de l'immunité",  1:150,        40)
    s_masque,   l_masque   = curseur("Proba. de masque",     0.0:0.01:1.0, 0.5)
    s_vaccin,   l_vaccin   = curseur("Proba. de vaccin",     0.0:0.01:1.0, 0.6)
    s_mort,     l_mort     = curseur("Mortalité des infectés (‰ par pas)", 0:200, 20)
    s_vitesse,  l_vitesse  = curseur("Vitesse (pas/seconde)", 1:30,        10)

    # Les boutons
    btn_lancer = Bonito.Button("▶ Lancer")
    btn_pause  = Bonito.Button("⏸ Pause")
    btn_pas    = Bonito.Button("⏭ 1 pas")
    btn_reset  = Bonito.Button("↺ Réinitialiser")

    # Créer un modèle avec les valeurs des curseurs
    function creer_modele()
        return initialize_model(
            n_agents                = s_agents.value[],
            initial_infected        = min(s_infectes.value[], s_agents.value[]),
            infectiousness          = s_contag.value[],
            latency_period          = s_latence.value[],
            duration                = s_duree.value[],
            chance_recover          = s_guerison.value[],
            immunity_duration       = s_immunite.value[],
            mask_probability        = s_masque.value[],
            vaccination_probability = s_vaccin.value[],
            seed                    = rand(1:10^6),
        )
    end

    # Variables de la simulation
    model     = Ref(creer_modele())
    temps     = Ref(0)
    en_marche = Ref(false)
    deces     = Ref(0)

    # Ce que la page affiche
    points  = Observable(Point2f[])
    cols    = Observable(Symbol[])
    courbes = [Observable(Point2f[]) for _ in 1:4]
    nombres = [Observable("0") for _ in 1:6]    # 4 états + population + décès
    titre   = Observable("Temps : 0")
    message = Observable("")
    etat    = Observable("⏸ En pause")
    erreur  = Observable("")

    # Les graphiques
    fig = Figure(size = (1000, 450), backgroundcolor = RGBAf(0.06, 0.08, 0.19, 1))
    ax1 = Axis(fig[1, 1]; title = titre, aspect = DataAspect())
    hidedecorations!(ax1)
    limits!(ax1, 0.5, 10.5, 0.5, 10.5)
    scatter!(ax1, points; color = cols, markersize = 13)

    ax2 = Axis(fig[1, 2]; title = "Évolution de l'épidémie", xlabel = "Temps", ylabel = "Agents")
    noms = ["Sains", "Exposés", "Infectés", "Guéris"]
    couleurs = [:deepskyblue, :orange, :crimson, :mediumseagreen]
    for i in 1:4
        lines!(ax2, courbes[i]; color = couleurs[i], linewidth = 3, label = noms[i])
    end
    axislegend(ax2; position = :rt)

    # Met à jour tout l'affichage
    function mettre_a_jour()
        n = compter(model[])
        for i in 1:4
            push!(courbes[i][], Point2f(temps[], n[i]))
            notify(courbes[i])
            nombres[i][] = string(n[i])
        end
        nombres[5][] = string(sum(n))
        nombres[6][] = string(deces[])
        points[] = [Point2f(a.pos[1] + 0.35 * sin(7 * a.id),
                            a.pos[2] + 0.35 * cos(13 * a.id)) for a in allagents(model[])]
        cols[] = [couleur_etat[a.status] for a in allagents(model[])]
        titre[] = "Temps : $(temps[])"
        message[] = message_etat(n)
        autolimits!(ax2)
    end

    # Les infectés peuvent mourir
    function faire_mourir()
        for a in collect(allagents(model[]))
            if a.status == infected && rand() < s_mort.value[] / 1000
                remove_agent!(a, model[])
                deces[] += 1
            end
        end
    end

    # Les actions
    function un_pas()
        Agents.step!(model[], 1)
        faire_mourir()
        temps[] += 1
        mettre_a_jour()
    end

    function arreter()
        en_marche[] = false
        etat[] = "⏸ En pause"
    end

    function reinitialiser()
        arreter()
        model[] = creer_modele()
        temps[] = 0
        deces[] = 0
        for c in courbes
            c[] = Point2f[]
        end
        mettre_a_jour()
    end

    function lancer()
        if en_marche[]
            return
        end
        en_marche[] = true
        etat[] = "● En cours"
        @async begin
            try
                while en_marche[]
                    un_pas()
                    sleep(1 / s_vitesse.value[])
                end
            catch e
                arreter()
                erreur[] = "Erreur : " * sprint(showerror, e)
            end
        end
    end

    # Affiche l'erreur dans la page au lieu de planter
    function essayer(action)
        erreur[] = ""
        try
            action()
        catch e
            arreter()
            erreur[] = "Erreur : " * sprint(showerror, e)
        end
    end

    # Ce que font les boutons
    on(session, btn_lancer.value) do _
        essayer(lancer)
    end
    on(session, btn_pause.value) do _
        arreter()
    end
    on(session, btn_pas.value) do _
        essayer(un_pas)
    end
    on(session, btn_reset.value) do _
        essayer(reinitialiser)
    end

    mettre_a_jour()

    # ----- La mise en page -----
    entete = DOM.div(
        DOM.div("🦠"; class = "logo"),
        DOM.div(
            DOM.h1("EPIDEMIC"; class = "titre"),
            DOM.p("Laboratoire de simulation · Modèle SEIRS"; class = "sous-titre"),
        );
        class = "entete",
    )

    gauche = DOM.div(
        DOM.div(DOM.h4("🌍 Population"; class = "carte-titre"), l_agents, l_infectes;
                class = "carte"),
        DOM.div(DOM.h4("🦠 Dynamique du virus"; class = "carte-titre"),
                l_contag, l_latence, l_duree, l_guerison, l_immunite; class = "carte"),
        DOM.div(DOM.h4("🛡️ Protection"; class = "carte-titre"), l_masque, l_vaccin;
                class = "carte"),
        DOM.div(DOM.h4("💀 Décès"; class = "carte-titre"), l_mort; class = "carte"),
        DOM.div(btn_reset);
        style = "width:320px; margin-right:30px; flex-shrink:0;",
    )

    stats = DOM.div(
        carte_stat("🙂", "Sains",      "#4cc9f0", nombres[1]),
        carte_stat("😷", "Exposés",    "#ffb703", nombres[2]),
        carte_stat("🤒", "Infectés",   "#ff4d6d", nombres[3]),
        carte_stat("💪", "Guéris",     "#2ec4b6", nombres[4]),
        carte_stat("👥", "Population", "#c7d0ff", nombres[5]),
        carte_stat("💀", "Décès",      "#adb5bd", nombres[6]);
        style = "display:flex; flex-wrap:wrap; gap:15px; margin-bottom:20px;",
    )

    droite = DOM.div(
        DOM.div(DOM.span(btn_lancer; class = "violet"), btn_pause, btn_pas,
                DOM.span(etat; class = "pill")),
        DOM.div(l_vitesse; style = "width:420px; margin-top:25px;"),
        DOM.div(message; class = "carte message"),
        DOM.div(erreur; style = "color:#ff8fa3; margin-bottom:10px;"),
        stats,
        DOM.div(fig; class = "carte");
        style = "flex:1; min-width:0;",
    )

    return DOM.div(
        DOM.style(css),
        entete,
        DOM.div(gauche, droite; style = "display:flex; align-items:flex-start;"),
    )
end

# ---------- Lancer le serveur ----------
server = Bonito.Server(app, "127.0.0.1", 8080)
println("Ouvre http://127.0.0.1:8080 dans ton navigateur (Ctrl+C pour arrêter)")
wait(server)