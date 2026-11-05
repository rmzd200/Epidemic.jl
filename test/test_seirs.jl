using Epidemic
using Test
using Agents


@testset "SEIRS Model" begin

    @testset "Model Initialization " begin
        model=initialize_model()
        @test nagents(model)==150
        @test count(a -> a.status == susceptible, allagents(model))==140
        @test count(a -> a.status == infected, allagents(model))==10
        
        # Test invalide parameters
        @test_throws AssertionError initialize_model(duration= -3)
        @test_throws AssertionError initialize_model( infectiousness=1.5)
        @test_throws AssertionError initialize_model( initial_infected=200)

    end

    # Test function A:Move an agent randomly
    @testset "Movement" begin
         model=initialize_model( dims=(10,10),n_agents=1,initial_infected=0)
        
        agent=first(allagents(model))
        Epidemic.move_agent!(agent,model)

        @test all( 1<=agent.pos[i]<=10 for i in 1:2)   
    end

    #  Test function B: Aging and natural death
    @testset "Aging and Death " begin
        model=initialize_model(n_agents=1, initial_infected=0,max_age=100)
        agent=first(allagents(model))
        agent.age=20
        @test Epidemic.aging_and_death!(agent,model)==false
        @test agent.age==21
        
        agent.age=99
        @test Epidemic.aging_and_death!(agent,model)==true
        @test nagents(model)==0

    end

    # Test  function c: Update exposure, infection and immunity
    @testset "Health transition" begin
        model=initialize_model(n_agents=1,
        initial_infected=0,
        latency_period=3,
        duration=2,
        chance_recover=1.0,
        immunity_duration=2)
        agent=first(allagents(model))

        agent.status=exposed
        agent.exposure_timer=2
        Epidemic.update_health!(agent,model)
        @test agent.status==infected

        agent.infection_timer=1
        Epidemic.update_health!(agent,model)
        @test agent.status==recovered

        agent.immunity_timer=1 
        Epidemic.update_health!(agent,model)
        @test agent.status==susceptible
          
    end
     # Test function D: transmission of the virus 
    @testset "Transmission" begin
        
        model=initialize_model( n_agents=2,
        initial_infected=1,
        infectiousness=1.0,
        mask_probability=0.0,
        vaccination_probability=0.0)
        susceptible_agent=first(a for  a in allagents(model) if a.status==susceptible)  
        infected_agent=first(a for a in allagents(model) if a.status==infected)

        move_agent!(susceptible_agent,infected_agent.pos,model)  # Move the susceptible_agent to the postion of infected_agent
        Epidemic.transmit_infection!(infected_agent,model)

        @test susceptible_agent.status==exposed
        
    end

    # Test function E: Reproduction
    @testset "Reproduction" begin
        model=initialize_model( n_agents=1,
         initial_infected=0, 
         birth_rate=1.0,
         carrying_capacity=2)
        agent=first(allagents(model)) 
        Epidemic.reproduce!(agent,model)
        @test nagents(model)==2

        Epidemic.reproduce!(agent,model)
        @test nagents(model)==2
    end
   
    #Test the complete agent step
    @testset "Agent step" begin
        model=initialize_model(n_agents=1,
        initial_infected=0,
        max_age=100,
        birth_rate=0.0,
         )
        agent=first(allagents(model))
        agent.age=20

        Epidemic.agent_step!(agent,model)
        @test agent.age==21
        @test nagents(model)==1

        agent.age=99
        Epidemic.agent_step!(agent,model)
        @test nagents(model)==0


    end
end
