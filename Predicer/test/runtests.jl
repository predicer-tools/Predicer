using Timesteps

@testset verbose = true "Predicer Tests" begin
    include("structures.jl")
    include("tuples.jl")
    include("model.jl")
end