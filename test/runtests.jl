#= In the project root directory:
    ]activate .
    ]test
=#

using Predicer
using Test
using JuMP

using HiGHS
optr = HiGHS.Optimizer

# Model definition files and objective values
cases = Dict(
    "input_data.xlsx" => -12031.87393643243,
    "demo_model.xlsx" => -1095.5118308122817)

@testset "Predicer on $bn" for (bn, obj) in cases
    inp = Predicer.get_data(joinpath("../input_data", bn))
    Predicer.tweak_input!(inp)
    m = Model(optr)
    mc = Predicer.generate_model(m, inp)
    @test m == mc["model"]
    Predicer.solve_model(mc)
    @test termination_status(m) == MOI.OPTIMAL
    @test objective_value(m) ≈ obj atol=1e-6
end
