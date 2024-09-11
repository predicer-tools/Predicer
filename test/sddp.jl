@testset "SDDP on $bn" for (bn, lower_bound) in sddp_cases
    known_obj = cases[bn]
    @assert lower_bound ≤ known_obj
    inp = get_input(bn)
    pg = Predicer.sddp_policy_graph(
        [inp]; lower_bound, optimizer=Optimizer)
    dem = SDDP.deterministic_equivalent(pg, Optimizer)
    silent && set_silent(dem)
    optimize!(dem)
    @test JuMP.termination_status(dem) == MOI.OPTIMAL
    if inp.setup.contains_risk
        @test(known_obj - objective_value(dem) ≥ -obj_rtol(dem),
              skip=isnan(known_obj))
    else
        @test(objective_value(dem) ≈ known_obj, rtol=obj_rtol(dem),
              skip=isnan(known_obj))
    end
    @test objective_value(dem) ≥ lower_bound
    @show(inp.setup.contains_risk, lower_bound,
          objective_value(dem), known_obj,
          relative_gap(dem))
    risk_measure = Predicer.sddp_risk_measure(inp)
    SDDP.train(pg; risk_measure,
               cut_type=SDDP.MULTI_CUT,
               print_level=silent ? 0 : 1,
               #iteration_limit=100,
               )
    obj_bound = SDDP.calculate_bound(pg; risk_measure)
    @test known_obj - obj_bound ≥ -1e-4
    @show obj_bound known_obj
end
