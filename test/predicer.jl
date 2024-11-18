@testset "Predicer on $bn" for (bn, known_obj) in cases
    m = Model(Optimizer)
    silent && set_silent(m)
    inp = get_input(bn)
    mc = Predicer.generate_model(m, inp)
    @test m == mc["model"]
    Predicer.solve_model(mc)
    @test JuMP.termination_status(m) == MOI.OPTIMAL
    @test objective_value(m) ≈ known_obj rtol=obj_rtol(m) skip=isnan(known_obj)
    @show objective_value(m) known_obj relative_gap(m)
    @test !isempty(Predicer.get_all_result_dataframes(mc, inp))
    @test !isempty(Predicer.get_costs_dataframe(mc, inp))
    s = scenarios(inp)[1]
    @test !isempty(Predicer.get_costs_dataframe(mc, inp, "total_costs", s))
    #XXX What are these supposed to test?
    @test !isempty([Predicer.get_process_balance(mc, inp, p, s)
                    for p in keys(inp.processes)])
    @test !isempty([Predicer.get_node_balance(mc, inp, n, s)
                    for n in keys(inp.nodes)])
end
