#= In the project root directory:
    ]activate .
    ]test
=#

using Predicer
using Test
using JuMP

using HiGHS: Optimizer
#using Cbc: Optimizer

# Model definition files and objective values.  obj = NaN to disable
# comparison.
cases = [
    "input_data.xlsx" => -10984.374666617387
    "input_data_bidcurve.xlsx" => -4371.579033779262
#FIXME Does not load    "demo_model.xlsx" => -1095.5118308122817
#FIXME Does not load    "example_model.xlsx" => -11014.127894223102
#FIXME Does not load    "input_data_common_start.xlsx" => -1593.5748049230276
#FIXME Does not load    "input_data_delays.xlsx" => 62.22222222222222
#FIXME Does not load    "input_data_temps.xlsx" => 65388.35282275837
#FIXME Does not load    "simple_building_model.xlsx" => 563.7841038762567
#FIXME Does not load    "simple_dh_model.xlsx" => NaN
#FIXME Does not load    "simple_hydropower_river_system.xlsx" => NaN
#FIXME Does not load    "two_stage_dh.model.xlsx" => NaN
]

@testset "Predicer on $bn" for (bn, obj) in cases
    inp = Predicer.get_data(joinpath("../input_data", bn))
    inp = Predicer.tweak_input!(inp)
    m = Model(Optimizer)
    #set_silent(m)
    mc = Predicer.generate_model(m, inp)
    @test m == mc["model"]
    Predicer.solve_model(mc)
    @test termination_status(m) == MOI.OPTIMAL
    if isnan(obj)
        @show objective_value(m)
    else
        @test objective_value(m) ≈ obj atol=1e-6
    end
end
