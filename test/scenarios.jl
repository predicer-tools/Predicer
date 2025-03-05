@testset "Scenarios on $bn" for (bn, known_obj) in cases
    inp = get_input(bn)
    mcs = [Predicer.generate_model(Model(Optimizer),
                                   Predicer.scen_subproblem(inp, sc))
           for sc in keys(inp.scenarios)]
    ms = getindex.(mcs, "model")
    set_silent.(ms)
    Predicer.solve_model.(mcs)
    @test all(JuMP.termination_status.(ms) .== MOI.OPTIMAL)
    min_obj, max_obj = extrema(objective_value.(ms))
    lower_bound = get(sddp_cases, bn, -Inf)
    @test min_obj ≥ lower_bound
    @test known_obj - min_obj ≥ -max(obj_rtol.(ms)...) skip=isnan(known_obj)
    @show lower_bound min_obj known_obj max_obj
end
