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
    "input_data_bidcurve.xlsx" => -4371.579033779262
    "demo_model.xlsx" => -1095.5118308122817
    "example_model.xlsx" => -11014.1278942231
#FIXME Does not load    "input_data_common_start.xlsx" => -1589.8038551373697
    "input_data_complete.xlsx" => -7139.504323058706
    "input_data_delays.xlsx" => 70062.2222222222
    "input_data_temps.xlsx" => 65047.97271947195
    "simple_building_model.xlsx" => 717.8991524690073
    "simple_dh_model.xlsx" => 7195.372539092246
#FIXME Does not load    "simple_hydropower_river_system.xlsx" => NaN
    "two_stage_dh_model.xlsx" => 9508.652488524222
]

inputs = Dict{String, Predicer.InputData}()

get_input(bn) = get!(inputs, bn) do
    inp = Predicer.get_data(joinpath("..", "input_data", bn))
    Predicer.tweak_input!(inp)
end

include("../make-graph.jl")

@testset "make-graph on $bn" for (bn, _) in cases
    of = joinpath("..", "input_data",
                  replace(bn, r"[.][^.]*$" => "") * ".dot")
    println("$bn |-> $of")
    @test (write_graph(of, get_input(bn)); true)
end

@testset "Predicer on $bn" for (bn, obj) in cases
    m = Model(Optimizer)
    #set_silent(m)
    mc = Predicer.generate_model(m, get_input(bn))
    @test m == mc["model"]
    Predicer.solve_model(mc)
    @test termination_status(m) == MOI.OPTIMAL
    rgap = relative_gap(m)
    # Apparently infinite for LP
    if rgap < 1e-8 || !isfinite(rgap)
        rgap = 1e-8
    end
    if !isnan(obj)
        @test objective_value(m) ≈ obj rtol=rgap
    end
    @show objective_value(m) obj relative_gap(m)
end
