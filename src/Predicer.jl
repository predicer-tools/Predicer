module Predicer
    include("structures.jl")
    include("model.jl")
    include("tuples.jl")
    include("variables.jl")
    include("constraints.jl")
    include("validate_data.jl")
    include("init.jl")

    include("import_input_data.jl")

    
    

    export Initialize,
    solve_model,
    export_model_contents,
    get_result_dataframe,
    write_bid_matrix,
    resolve_delays,
    resolve_market_nodes

    export Node,
    Process, 
    TimeSeries,
    State,
    Market,
    Topology,
    ConFactor,
    GenConstraint,
    InputData,
    Temporals

    export add_inflow,
    add_state, 
    add_node_to_reserve,
    convert_to_commodity,
    convert_to_market,
    add_cost,
    MarketProcess,
    TransferProcess,
    add_fixed_eff,
    add_piecewise_eff,
    add_online,
    add_eff,
    add_cf,
    add_process_to_reserve,
    add_topology,
    add_load_limits

    export create_tuples,
    reserve_nodes,
    reserve_market_directional_tuples,
    process_topology_tuples,
    online_process_tuples,
    reserve_groups,
    reserve_process_tuples,
    nodegroup_reserves,
    node_reserves,
    producer_reserve_process_tuples,
    consumer_reserve_process_tuples,
    state_node_tuples,
    balance_node_tuples,
    balance_process_tuples,
    operative_slot_process_tuples,
    piecewise_efficiency_process_tuples,
    cf_process_topology_tuples,
    fixed_limit_process_topology_tuples,
    transport_process_topology_tuples,
    reserve_node_tuples,
    up_down_reserve_market_tuples,
    reserve_market_tuples,
    fixed_market_tuples,
    process_topology_ramp_times_tuples,
    scenarios,
    create_delay_process_tuple,
    create_balance_market_tuple,
    state_reserves,
    create_reserve_limits,
    setpoint_tuples,
    block_tuples,
    create_group_tuples


    export create_variables,
    create_v_flow,
    create_v_load,
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

    export validate_data
    
end