module AbstractModel
    include("tuples.jl")
    include("variables.jl")
    include("constraints.jl")
    include("model.jl")
    include("structures.jl")

    export Initialize,
    solve_model,
    export_model_contents,
    get_result_dataframe,
    write_bid_matrix

    export Node,
    Process, 
    TimeSeries,
    State,
    Market,
    Topology,
    ConFactor,
    GenConstraint

    export create_tuples,
    create_res_nodes_tuple,
    create_res_tuple,
    create_process_tuple,
    create_res_potential_tuple,
    create_proc_online_tuple,
    create_res_pot_prod_tuple,
    create_res_pot_cons_tuple,
    create_node_state_tuple,
    create_node_balance_tuple,
    create_proc_potential_tuple,
    create_proc_balance_tuple,
    create_proc_op_balance_tuple,
    create_proc_op_tuple,
    create_cf_balance_tuple,
    create_lim_tuple,
    create_trans_tuple,
    create_res_eq_tuple,
    create_res_eq_updn_tuple,
    create_res_final_tuple,
    create_fixed_value_tuple,
    create_ramp_tuple

    export create_variables,
    create_v_flow,
    create_v_online,
    create_v_reserve,
    create_v_state,
    create_v_flow_op

    export create_constraints,
    setup_node_balance,
    setup_process_online_balance,
    setup_process_balance,
    setup_processes_limits,
    setup_reserve_balances,
    setup_ramp_constraints,
    setup_fixed_values,
    setup_bidding_constraints,
    setup_generic_constraints,
    setup_cost_calculations,
    setup_objective_function
    
end