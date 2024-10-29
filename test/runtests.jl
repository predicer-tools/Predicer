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
    "input_data_complete.xlsx" => -7138.42326815
    "input_data_bidcurve.xlsx" => -4371.579033779262
    "demo_model.xlsx" => -1095.5118308122817
    "example_model.xlsx" => -11014.1278942231
    "input_data_common_start.xlsx" => -1589.80385514
    "input_data_delays.xlsx" => 62.22222222222222
    "input_data_temps.xlsx" => 65388.35282275837
    "simple_building_model.xlsx" => 563.7841038762567
    "simple_dh_model.xlsx" => 7195.372539092246
    #"simple_hydropower_river_system.xlsx" => NaN
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

@testset "Predicer on $bn" for (bn, known_obj) in cases
    m = Model(Optimizer)
    #set_silent(m)
    inp = get_input(bn)
    mc = Predicer.generate_model(m, inp)
    @test m == mc["model"]
    Predicer.solve_model(mc)
    @test termination_status(m) == MOI.OPTIMAL
    rgap = relative_gap(m)
    # Apparently infinite for LP
    if rgap < 1e-8 || !isfinite(rgap)
        rgap = 1e-8
    end
    if !isnan(known_obj)
        @test objective_value(m) ≈ known_obj rtol=rgap
    end
    @show objective_value(m) known_obj relative_gap(m)
    s = scenarios(inp)[1]
    @test !isempty(Predicer.get_all_result_dataframes(mc, inp))
    @test !isempty(Predicer.get_costs_dataframe(mc, inp))
    @test !isempty(Predicer.get_costs_dataframe(mc, inp, "total_costs", s))
    @test !isempty([Predicer.get_process_balance(mc, inp, p, s) for p in collect(keys(inp.processes))])
    @test !isempty([Predicer.get_node_balance(mc, inp, n, s) for n in collect(keys(inp.nodes))])
    
end
