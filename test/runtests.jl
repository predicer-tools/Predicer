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
cases = [
#FIXME Does not load    "input_data.xlsx" => -12031.87393643243
    "demo_model.xlsx" => -1095.5118308122817
    "simple_building_model.xlsx" => 563.7841038762567
    "example_model.xlsx" => -11014.127894223102
    "input_data_common_start.xlsx" => -1593.5748049230276
    "input_data_delays.xlsx" => 62.22222222222222
    "input_data_temps.xlsx" => 65388.35282275837
]

@testset "Predicer on $bn" for (bn, obj) in cases
    inp = Predicer.get_data(joinpath("../input_data", bn))
    inp = Predicer.tweak_input!(inp)
    m = Model(optr)
    mc = Predicer.generate_model(m, inp)
    @test m == mc["model"]
    Predicer.solve_model(mc)
    @test termination_status(m) == MOI.OPTIMAL
    @test objective_value(m) ≈ obj atol=1e-6
end
