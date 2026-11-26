---
pagetitle: "Simulation d'une épidémie SEIRS avec Julia"
lang: fr
engine: julia
format:
  html:
    toc: true
    toc-title: "Sommaire"
    number-sections: true
    embed-resources: true
execute:
  warning: false
---

```{=html}
<div style="text-align:center; padding:3rem 0 4rem 0;">
  <img src="logo-uga.png" alt="Logo UGA" style="max-width:260px;" onerror="this.style.display='none'">
  <p style="margin-top:3rem; font-size:1.2rem;">Rapport du projet</p>
  <p style="font-size:1.2rem;">Thème :</p>
  <h1 style="font-size:2.4rem; margin:0.5rem 0; border:none;">Simulation d'une épidémie SEIRS avec Julia</h1>
  <p style="margin-top:4rem; font-size:1.2rem;"><strong>Membres du groupe :</strong></p>
  <p style="font-size:1.2rem; line-height:1.8;">Ramez Dahouathi<br>Mastene Ouchebbouk<br>Melissa Bouarour</p>
  <p style="margin-top:4rem;">Année universitaire 2026/2027</p>
</div>
```

# Introduction

{{< pagebreak >}}



# Introduction

Ce rapport présente Epidemic.jl, un package Julia qui simule la propagation d’une épidémie à l’aide d’un modèle 
à base d’agents (ABM), construit avec la bibliothèque Agents.jl.Chaque personne est un agent qui se déplace sur 
une grille et peut infecter ses voisins. On observe ensuite ce qui se passe à l’échelle de la population.

## Objectif du projet

L’objectif de ce projet est de modéliser la propagation d’une maladie infectieuse au sein d’une population afin
 d’étudier comment des règles simples à l’échelle individuelle (déplacement, contact, transmission, guérison) 
 produisent une dynamique collective, comme le pic épidémique ou la proportion finale d’individus touchés. 
 Conformément à la consigne, ce travail consiste à implémenter, avec Agents.jl, un package Julia complet et reproductible,
 puis à analyser l’effet de ses principaux paramètres sur l’évolution de l’épidémie.

## Le modèle SEIRS

Le modèle SEIRS répartit la population en quatre compartiments :

- **S** (*Susceptible*) : individu sain, pouvant être infecté ;
- **E** (*Exposed*) : individu infecté mais pas encore contagieux (période d'incubation) ;
- **I** (*Infectious*) : individu infecté et contagieux ;
- **R** (*Recovered*) : individu guéri, temporairement immunisé.
