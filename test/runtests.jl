#= In the project root directory:
    ]activate .
    ]test
=#

using Predicer
using Test
using JuMP

using HiGHS: Optimizer
#using Cbc: Optimizer
#using CPLEX: Optimizer

# Model definition files and objective values.  obj = NaN to disable
# comparison.
cases = [
    "input_data.xlsx" => -10985.034456374564
    "input_data_complete.xlsx" => -7139.999025659914
    "input_data_bidcurve.xlsx" => -4371.579033779262
    "demo_model.xlsx" => -1095.5118308122817
    "example_model.xlsx" => -11014.1278942231
    "input_data_common_start.xlsx" => -1574.9410327933133
    "input_data_delays.xlsx" => 62.22222222222222
    "input_data_temps.xlsx" => 65388.35282275837
    "simple_building_model.xlsx" => 563.7841038762567
    "simple_dh_model.xlsx" => 7195.372539092246
    #"simple_hydropower_river_system.xlsx" => NaN
    "two_stage_dh_model.xlsx" => 9508.652488524222
]

function testrunner(cases)
    test_results = Dict()
    for _filename in map(x -> x[1], cases)
        test_results[_filename] = []
        mc, id = Predicer.generate_model(joinpath(pwd(), "..", "input_data", _filename));
        Predicer.solve_model(mc)
        if JuMP.termination_status(mc["model"]) == MOI.OPTIMAL
            rgap = relative_gap(mc["model"])
            if rgap < 1e-8 || !isfinite(rgap)
                rgap = 1e-8
            end
            push!(test_results[_filename], (true, JuMP.objective_value(mc["model"]), rgap))
        else
            push!(test_results[_filename], (false, JuMP.termination_status(mc["model"]), ""))
        end
    end
    return test_results
end

test_results = testrunner(cases)

@testset "Predicer on $bn" for (bn, obj) in cases
    @test test_results[bn][1][1]
    @test test_results[bn][1][2] ≈ obj rtol=(test_results[bn][1][3])
    model_obj_val = test_results[bn][1][2]
    expected_val = obj
    rgap = test_results[bn][1][3]
    @show model_obj_val expected_val rgap
end
