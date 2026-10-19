using Epidemic 
using Agents

# Create the model
model = initialize_model()

# Count the total number of agents
println("Total population: ", nagents(model))

# Count agents by health status
S = count(a -> a.status == susceptible, allagents(model))
E=count(a-> a.status==exposed,allagents(model) )
I = count(a -> a.status == infected, allagents(model))
R = count(a -> a.status == recovered, allagents(model))

println("Susceptible: ", S)
println("Exposed: ",E)
println("Infected: ", I)
println("Recovered: ", R)

# Check if the population count is correct
println("Population check: ", S + I + E + R == nagents(model))

# Run the simulation for 50 ticks
for t in 1:50
  # Move the simulation forward by one tick
    step!(model, 1)    
  # Count agents by health status
    local S = count(a -> a.status == susceptible, allagents(model))
    local E=count(a->a.status==exposed,allagents(model))
   local I = count(a -> a.status == infected, allagents(model))
   local R = count(a -> a.status == recovered, allagents(model))  
 #Total Agents
   N=nagents(model)
 #check population consistency
 @assert S+I+R+E == N
 # Display the results
    println("Tick: ", t," | S: ", S," | E: ", E," | I: ", I," | R: ", R," | Total: ", N)
end  