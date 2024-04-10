#= In the project root directory:
    ]activate .
    ]test
=#

using Predicer
using Test
using JuMP

# Model definition files and objective values
cases = Dict(
    "input_data.xlsx" => -12031.87393643243,
    "demo_model.xlsx" => -1095.5118308122817)

@testset "Predicer on $bn" for (bn, obj) in cases
    (mc, inp) = Predicer.generate_model(joinpath("../input_data", bn))
    Predicer.solve_model(mc)
    m = mc["model"]
    @test termination_status(m) == MOI.OPTIMAL
    @test objective_value(m) ≈ obj atol=1e-8
end
