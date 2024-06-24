using DataStructures
using JuMP

"""
    create_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)

Create all constraints used in the model.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function create_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)
    setup_reserve_realisation(model_contents, input_data)
    setup_node_balance(model_contents, input_data)
    setup_process_online_balance(model_contents, input_data)
    setup_process_balance(model_contents, input_data)
    setup_node_delay_flow_limits(model_contents, input_data)
    setup_process_limits(model_contents, input_data)
    setup_reserve_balances(model_contents, input_data)
    setup_ramp_constraints(model_contents, input_data)
    setup_bidding_curve_constraints(model_contents, input_data)
    setup_bidding_constraints(model_contents, input_data)
    setup_bidding_volume_constraints(model_contents, input_data)
    setup_fixed_values(model_contents, input_data)
    setup_generic_constraints(model_contents, input_data)
    setup_cost_calculations(model_contents, input_data)
    setup_cvar_element(model_contents, input_data)
    setup_objective_function(model_contents, input_data)
    setup_reserve_participation(model_contents, input_data)
    setup_inflow_blocks(model_contents, input_data)
end


"""
    setup_node_balance(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup node balance constraints used in the model.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_node_balance(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    process_tuple = process_topology_tuples(input_data)
    block_tuples = Predicer.block_tuples(input_data)
    
    node_state_tuple = state_node_tuples(input_data)
    node_balance_tuple = balance_node_tuples(input_data)
    prev_times = previous_times(input_data)
    v_flow = model_contents["variable"]["v_flow"]
    v_block = model_contents["variable"]["v_block"]
    if input_data.setup.contains_states
        v_state = model_contents["variable"]["v_state"]
    end
    if input_data.setup.contains_reserves
        v_res_real = model_contents["expression"]["v_res_real"]
        node_res = node_reserves(input_data)
    end

    

    if input_data.setup.use_node_dummy_variables
        vq_state_up = model_contents["variable"]["vq_state_up"]
        vq_state_dw = model_contents["variable"]["vq_state_dw"]
    end
    temporals = input_data.temporals  
    nodes = input_data.nodes


    #######
    ## Setup inflow expression
    inflow_expr =  model_contents["expression"]["inflow_expr"] = OrderedDict()
    for n in collect(keys(nodes))
        for s in scenarios(input_data), t in temporals.t
            inflow_expr[(n, s, t)] = AffExpr(0.0)
            if nodes[n].is_inflow
                add_to_expression!(inflow_expr[(n, s, t)], nodes[n].inflow(s, t))
            end
            for b_tup in filter(x -> x[2] == n && x[3] == s && x[4] == t, block_tuples) # get tuples with blocks
                v_tup = (b_tup[1], b_tup[2], Predicer.validate_tuple(model_contents,(b_tup[3],input_data.inflow_blocks[b_tup[1]].start_time),1)[1])
                add_to_expression!(inflow_expr[(n, s, t)], input_data.inflow_blocks[b_tup[1]].data(s,t) * v_block[v_tup])
            end
            if nodes[n].is_state
                if nodes[n].state.is_temp
                    inflow_expr[(n, s, t)] = inflow_expr[(n, s, t)] * nodes[n].state.T_E_conversion
                end
            end
        end
    end

    e_node_diff = model_contents["expression"]["e_node_diff"] = OrderedDict()
    e_node_delay = model_contents["expression"]["e_node_delay"] = OrderedDict()
    e_node_history = model_contents["expression"]["e_node_history"] = OrderedDict()
    e_prod = model_contents["expression"]["e_prod"] = OrderedDict()
    e_cons = model_contents["expression"]["e_cons"] = OrderedDict()
    e_state = model_contents["expression"]["e_state"] = OrderedDict()
    for tup in node_balance_tuple
        e_node_diff[tup] = AffExpr(0.0)
        e_node_delay[tup] = AffExpr(0.0)
        e_node_history[tup] = AffExpr(0.0)
        e_prod[tup] = AffExpr(0.0)
        e_cons[tup] = AffExpr(0.0)
        e_state[tup] = AffExpr(0.0)
    end

    #setup diffusion expression
    if input_data.setup.contains_diffusion
        for d_tup in node_diffusion_tuple(input_data)
            d_node = d_tup[1]
            s = d_tup[2]
            t = d_tup[3]

            d_node_state = v_state[validate_tuple(model_contents, d_tup, 2)]
            if !nodes[d_node].state.is_temp
                d_node_state /= nodes[d_node].state.T_E_conversion
            end

            from_diff = filter(x -> x.node1 == d_node, input_data.node_diffusion)
            to_diff = filter(x -> x.node2 == d_node, input_data.node_diffusion)

            for from_node in from_diff
                c = from_node.coefficient(s, t)
                n_ = from_node.node2
                n_node_state = v_state[validate_tuple(model_contents, (n_, s, t), 2)]
                if !nodes[n_].state.is_temp
                    n_node_state /= nodes[n_].state.T_E_conversion
                end
                add_to_expression!(e_node_diff[d_tup], - c * (d_node_state - n_node_state))
            end
            for to_node in to_diff
                c = to_node.coefficient(s, t)
                n_ = to_node.node1
                n_node_state = v_state[validate_tuple(model_contents, (n_, s, t), 2)]
                if !nodes[n_].state.is_temp
                    n_node_state /= nodes[n_].state.T_E_conversion
                end
                add_to_expression!(e_node_diff[d_tup], c * (n_node_state - d_node_state))
            end
        end
    end

    # setup delay expression
    if input_data.setup.contains_delay
        v_node_delay = model_contents["variable"]["v_node_delay"]
        delay_tups = node_delay_tuple(input_data)
        for tup in node_balance_tuple
            cons_delays = filter(x -> x[1] == tup[1] && x[3] == tup[2] && x[4] == tup[3], delay_tups) # Get delay flows "out" of node
            prod_delays = filter(x -> x[2] == tup[1] && x[3] == tup[2] && x[5] == tup[3], delay_tups) # Get delay flows "in" to node
            for d in cons_delays
                # consuming flows as negative
                add_to_expression!(e_node_delay[tup], -1, v_node_delay[d])
            end
            for d in prod_delays
                # producing flows as positive
                add_to_expression!(e_node_delay[tup], v_node_delay[d])
            end
        end
    end

    # setup node history expression
    for n in collect(keys(input_data.node_histories))
        for ts_data in input_data.node_histories[n].steps.ts_data
            for ts in ts_data.series
                add_to_expression!(e_node_history[(n, ts_data.scenario, ts[1])], ts[2])
            end
        end
    end


    # Balance constraints
    # gather data in dicts, e_prod, etc, now point to a Dict()
    e_prod = model_contents["expression"]["e_prod"] = OrderedDict()
    e_cons = model_contents["expression"]["e_cons"] = OrderedDict()
    e_state = model_contents["expression"]["e_state"] = OrderedDict()
    e_state_losses = model_contents["expression"]["e_state_losses"] = OrderedDict()

    proc_tup_reduced = unique(map(x -> (x[1:3]), process_tuple))
    for n in unique(map(x -> x[1], node_balance_tuple))

        # n of form (node)
        # process tuple of form (process_name, source, sink)
        cons_procs = unique(filter(x -> x[2] == n, proc_tup_reduced))
        prod_procs = unique(filter(x -> x[3] == n, proc_tup_reduced))

        for s in scenarios(input_data), t in temporals.t
            tu = (n, s, t)
            cons_procs_with_s_and_t = map(x -> (x[1], x[2], x[3], s, t), cons_procs)
            prod_procs_with_s_and_t = map(x -> (x[1], x[2], x[3], s, t), prod_procs)

            e_prod[tu] = AffExpr(0.0)
            e_cons[tu] = AffExpr(0.0)
            e_state[tu] = AffExpr(0.0)
            e_state_losses[tu] = AffExpr(0.0)

            if input_data.setup.use_node_dummy_variables
                add_to_expression!(e_cons[tu], -vq_state_dw[validate_tuple(model_contents, tu, 2)])
                add_to_expression!(e_prod[tu], vq_state_up[validate_tuple(model_contents, tu, 2)])
            end
            add_to_expression!(e_cons[tu], inflow_expr[tu])
            add_to_expression!(e_prod[tu], e_node_diff[tu])
            add_to_expression!(e_prod[tu], e_node_delay[tu])
            add_to_expression!(e_prod[tu], e_node_history[tu])
            if input_data.setup.contains_reserves && tu in node_res
                add_to_expression!(e_cons[tu], -v_res_real[tu])
            end
    
            if !isempty(cons_procs_with_s_and_t)
                add_to_expression!(e_cons[tu], -sum(v_flow[validate_tuples(model_contents, cons_procs_with_s_and_t, 4)]))
            end
            if !isempty(prod_procs_with_s_and_t)
                add_to_expression!(e_prod[tu], sum(v_flow[validate_tuples(model_contents, prod_procs_with_s_and_t, 4)]))
            end
    
            if nodes[tu[1]].is_state
                add_to_expression!(e_state[tu], v_state[validate_tuple(model_contents, tu, 2)])
                prev_st = (tu[3] == temporals.t[1]
                           ? nodes[tu[1]].state.initial_state
                           : v_state[validate_tuple(
                                model_contents,
                                (tu[1 : 2]..., prev_times[tu[3]]), 2)])
                add_to_expression!(e_state[tu], -1, prev_st)
                add_to_expression!(
                    e_state_losses[tu],
                    nodes[tu[1]].state.state_loss_proportional * temporals(tu[3]),
                    prev_st)
                if nodes[tu[1]].state.is_temp
                    e_state[tu] *= nodes[tu[1]].state.T_E_conversion
                    e_state_losses[tu] *= nodes[tu[1]].state.T_E_conversion
                end
            end
        end
    end

    node_bal_eq = @constraint(model, node_bal_eq[tup in node_balance_tuple], temporals(tup[3]) * (e_prod[tup] + e_cons[tup]) == e_state[tup] + e_state_losses[tup])
    node_state_max_up = @constraint(model, node_state_max_up[tup in node_state_tuple], e_state[tup] <= nodes[tup[1]].state.in_max * temporals(tup[3]))
    node_state_max_dw = @constraint(model, node_state_max_dw[tup in node_state_tuple], -e_state[tup] <= nodes[tup[1]].state.out_max * temporals(tup[3]))  
    model_contents["constraint"]["node_bal_eq"] = node_bal_eq
    model_contents["constraint"]["node_state_max_up"] = node_state_max_up
    model_contents["constraint"]["node_state_max_dw"] = node_state_max_dw
    for tu in node_state_tuple
        set_upper_bound(v_state[validate_tuple(model_contents, tu, 2)], nodes[tu[1]].state.state_max)
        set_lower_bound(v_state[validate_tuple(model_contents, tu, 2)], nodes[tu[1]].state.state_min)
    end
end


"""
    setup_process_online_balance(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup necessary functionalities for processes with binary online variables.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_process_online_balance(model_contents::OrderedDict, input_data::Predicer.InputData)
    if input_data.setup.contains_online
        proc_online_tuple = online_process_tuples(input_data)
        if !isempty(proc_online_tuple)
            model = model_contents["model"]
            v_start = model_contents["variable"]["v_start"]
            v_stop = model_contents["variable"]["v_stop"]
            v_online = model_contents["variable"]["v_online"]
            
            processes = input_data.processes
            scenarios = collect(keys(input_data.scenarios))
            temporals = input_data.temporals
            # Dynamic equations for start/stop online variables
            online_expr = model_contents["expression"]["online_expr"] = OrderedDict()
            for (i,tup) in enumerate(proc_online_tuple)
                if tup[3] == temporals.t[1]
                    online_expr[tup] = @expression(model,v_start[validate_tuple(model_contents, tup, 2)]-v_stop[validate_tuple(model_contents, tup, 2)]-v_online[validate_tuple(model_contents, tup, 2)] + Int(processes[tup[1]].initial_state))
                else
                    online_expr[tup] = @expression(model,v_start[validate_tuple(model_contents, tup, 2)]-v_stop[validate_tuple(model_contents, tup, 2)]-v_online[validate_tuple(model_contents, tup, 2)]+v_online[validate_tuple(model_contents, proc_online_tuple[i-1], 2)])
                end
            end
            online_dyn_eq =  @constraint(model,online_dyn_eq[tup in proc_online_tuple], online_expr[tup] == 0)
            model_contents["constraint"]["online_dyn_eq"] = online_dyn_eq

            ## setup constraints for scenario independent online processes
            # v_online[s1] == v_online[s2]
            # v_online[s2] == v_online[s3]
            # v_online[s3] == v_online[s1]
            #e_scenario_independence = OrderedDict()
            #for sip in filter(p -> processes[p].is_scenario_independent, collect(keys(processes)))
            #    p_tups = unique(filter(x -> x[1] == sip, proc_online_tuple))
            #    for s in scenarios(input_data)
            #        e_scenario_independence[(sip, s)] = Dict()
            #        tups = filter(x -> x[2] == s, p_tups)
            #        for tup in tups
            #            e_scenario_independence[(sip, s)][]
            #        end
            #        # set all online variables in tups equal
            #    end
            #end

            # Minimum and maximum online and offline periods
            min_online_rhs = OrderedDict()
            min_online_lhs = OrderedDict()
            min_offline_rhs = OrderedDict()
            min_offline_lhs = OrderedDict()
            max_online_rhs = OrderedDict()
            max_online_lhs = OrderedDict()
            max_offline_rhs = OrderedDict()
            max_offline_lhs = OrderedDict()


            ts_as_zdt = OrderedDict()
            for x in temporals.t
                ts_as_zdt[x] = ZonedDateTime(x, temporals.ts_format)
            end

            for p in unique(map(x -> x[1], proc_online_tuple))
                min_online = processes[p].min_online * Dates.Minute(60)
                min_offline = processes[p].min_offline * Dates.Minute(60)


                for s in scenarios
                    for t in temporals.t
                        # get all timesteps that are within min_online/min_offline after t.
                        min_on_hours = filter(x-> Dates.Minute(0) <= ts_as_zdt[x] - ts_as_zdt[t] <= min_online, temporals.t)
                        min_off_hours = filter(x-> Dates.Minute(0) <= ts_as_zdt[x] - ts_as_zdt[t] <= min_offline, temporals.t)

                        if processes[p].max_online == 0.0
                            max_on_hours = []
                        else
                            max_online = processes[p].max_online * Dates.Minute(60)
                            max_on_hours = filter(x-> Dates.Minute(0) <= ts_as_zdt[x] - ts_as_zdt[t] <= max_online, temporals.t)
                        end
                        if processes[p].max_offline == 0.0
                            max_off_hours = []
                        else
                            max_offline = processes[p].max_offline * Dates.Minute(60)
                            max_off_hours = filter(x-> Dates.Minute(0) <= ts_as_zdt[x] - ts_as_zdt[t] <= max_offline, temporals.t)
                        end

                        for h in min_on_hours
                            min_online_rhs[(p, s, t, h)] = v_start[validate_tuple(model_contents, (p,s,t), 2)]
                            min_online_lhs[(p, s, t, h)] = v_online[validate_tuple(model_contents, (p,s,h), 2)]
                        end
                        for h in min_off_hours
                            min_offline_rhs[(p, s, t, h)] = (1-v_stop[validate_tuple(model_contents, (p,s,t), 2)])
                            min_offline_lhs[(p, s, t, h)] = v_online[validate_tuple(model_contents, (p,s,h), 2)]
                        end

                        max_online_rhs[(p, s, t)] = processes[p].max_online
                        max_offline_rhs[(p, s, t)] = 1
                        if length(max_on_hours) > processes[p].max_online 
                            max_online_lhs[(p, s, t)] = AffExpr(0.0)
                            for h in max_on_hours
                                add_to_expression!(max_online_lhs[(p, s, t)], v_online[validate_tuple(model_contents, (p,s,h), 2)])
                            end
                        end
                        if length(max_off_hours) > processes[p].max_offline
                            max_offline_lhs[(p, s, t)] = AffExpr(0.0)
                            for h in max_off_hours
                                add_to_expression!(max_offline_lhs[(p, s, t)], v_online[validate_tuple(model_contents, (p,s,h), 2)])
                            end
                        end
                    end
                end
            end

            min_online_con = @constraint(model, min_online_con[tup in keys(min_online_lhs)], min_online_lhs[tup] >= min_online_rhs[tup])
            min_offline_con = @constraint(model, min_offline_con[tup in keys(min_offline_lhs)], min_offline_lhs[tup] <= min_offline_rhs[tup])

            max_online_con = @constraint(model, max_online_con[tup in keys(max_online_lhs)], sum(max_online_lhs[tup]) <= max_online_rhs[tup])
            max_offline_con = @constraint(model, max_offline_con[tup in keys(max_offline_lhs)], sum(max_offline_lhs[tup]) >= max_offline_rhs[tup])

            model_contents["constraint"]["min_online_con"] = min_online_con
            model_contents["constraint"]["min_offline_con"] = min_offline_con
            model_contents["constraint"]["max_online_con"] = max_online_con
            model_contents["constraint"]["max_offline_con"] = max_offline_con
        end
    end
end


"""
    setup_process_balance(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup constraints used in process balance calculations. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_process_balance(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    proc_balance_tuple = balance_process_tuples(input_data)
    process_tuple = process_topology_tuples(input_data)
    if input_data.setup.contains_piecewise_eff
        proc_op_tuple = piecewise_efficiency_process_tuples(input_data)
        proc_op_balance_tuple = operative_slot_process_tuples(input_data)
        v_flow_op_out = model_contents["variable"]["v_flow_op_out"]
        v_flow_op_in = model_contents["variable"]["v_flow_op_in"]
        v_flow_op_bin = model_contents["variable"]["v_flow_op_bin"]
    end
    v_flow = model_contents["variable"]["v_flow"]
    processes = input_data.processes

    # Fixed efficiency case:
    nod_eff = OrderedDict()
    proc_bal_tup_reduced = unique(map(x -> x[1], proc_balance_tuple))
    proc_tuple_reduced = unique(map(x -> (x[1:3]), process_tuple))
    for p in proc_bal_tup_reduced
        sources = filter(x -> (x[1] == p && x[3] == p), proc_tuple_reduced)
        sinks = filter(x -> (x[1] == p && x[2] == p), proc_tuple_reduced)
        for s in scenarios(input_data), t in input_data.temporals.t
            # fixed eff value
            if isempty(processes[p].eff_ts)
                eff = processes[p].eff
            else
                #ts-based eff value
                eff = processes[p].eff_ts(s, t)
            end

            tup = (p, s, t)
            sources_with_s_and_t = map(x -> (x[1], x[2], x[3], s, t), sources)
            sinks_with_s_and_t = map(x -> (x[1], x[2], x[3], s, t), sinks)
            nod_eff[tup] = sum(v_flow[validate_tuples(model_contents, sinks_with_s_and_t, 4)]) - (length(sources_with_s_and_t) > 0 ? eff * sum(v_flow[validate_tuples(model_contents, sources_with_s_and_t, 4)]) : 0)
        end
    end

    process_bal_eq = @constraint(model, process_bal_eq[tup in proc_balance_tuple], nod_eff[tup] == 0)
    model_contents["constraint"]["process_bal_eq"] = process_bal_eq

    if input_data.setup.contains_piecewise_eff
        # Piecewise linear efficiency curve case:
        op_min = OrderedDict()
        op_max = OrderedDict()
        op_eff = OrderedDict()

        for tup in proc_op_balance_tuple
            p = tup[1]
            cap = sum(map(x->x.capacity,filter(x->x.source == p,processes[p].topos)))

            i = parse(Int64,replace(tup[4], "op"=>""))# Clunky solution, how to improve?
            if i == 1 
                op_min[tup] = 0.0
            else
                op_min[tup] = processes[p].eff_fun[i-1][1]*cap
            end
            op_max[tup] = processes[p].eff_fun[i][1]*cap
            op_eff[tup] = processes[p].eff_fun[i][2]
        end

        flow_op_out_sum = @constraint(model,flow_op_out_sum[tup in proc_op_tuple],sum(v_flow_op_out[validate_tuples(model_contents, filter(x->x[1:3]==tup,proc_op_balance_tuple), 2)]) == sum(v_flow[validate_tuples(model_contents, filter(x->x[2]==tup[1] && x[4] == tup[2] && x[5] == tup[3],process_tuple), 4)]))
        flow_op_in_sum = @constraint(model,flow_op_in_sum[tup in proc_op_tuple],sum(v_flow_op_in[validate_tuples(model_contents, filter(x->x[1:3]==tup,proc_op_balance_tuple), 2)]) == sum(v_flow[validate_tuples(model_contents, filter(x->x[3]==tup[1] && x[4] == tup[2] && x[5] == tup[3],process_tuple), 4)]))
        model_contents["constraint"]["flow_op_out_sum"] = flow_op_out_sum
        model_contents["constraint"]["flow_op_in_sum"] = flow_op_in_sum

        flow_op_lo = @constraint(model,flow_op_lo[tup in proc_op_balance_tuple], v_flow_op_out[validate_tuple(model_contents, tup, 2)] >= v_flow_op_bin[validate_tuple(model_contents, tup, 2)] .* op_min[tup])
        flow_op_up = @constraint(model,flow_op_up[tup in proc_op_balance_tuple], v_flow_op_out[validate_tuple(model_contents, tup, 2)] <= v_flow_op_bin[validate_tuple(model_contents, tup, 2)] .* op_max[tup])
        flow_op_ef = @constraint(model,flow_op_ef[tup in proc_op_balance_tuple], v_flow_op_out[validate_tuple(model_contents, tup, 2)] == op_eff[tup] .* v_flow_op_in[validate_tuple(model_contents, tup, 2)])
        flow_bin = @constraint(model,flow_bin[tup in proc_op_tuple], sum(v_flow_op_bin[validate_tuples(model_contents, filter(x->x[1:3] == tup, proc_op_balance_tuple), 2)]) == 1)
        model_contents["constraint"]["flow_op_lo"] = flow_op_lo
        model_contents["constraint"]["flow_op_up"] = flow_op_up
        model_contents["constraint"]["flow_op_ef"] = flow_op_ef
        model_contents["constraint"]["flow_bin"] = flow_bin
    end
end

"""
    setup_node_delay_flow_limits(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup upper and lower limits for a delay flow between two nodes. 
"""
function setup_node_delay_flow_limits(model_contents::OrderedDict, input_data::Predicer.InputData)
    if input_data.setup.contains_delay
        v_node_delay = model_contents["variable"]["v_node_delay"]
        node_delay_tups = node_delay_tuple(input_data)
        for input in input_data.node_delay
            tups = filter(x -> x[1] == input[1] && x[2] == input[2], node_delay_tups)
            for tup in tups
                JuMP.set_lower_bound(v_node_delay[tup], input[4])
                JuMP.set_upper_bound(v_node_delay[tup], input[5])
            end
        end
    end
end

"""
    setup_process_limits(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup constraints used for process limitations, such as min/max loads, unit starts and participation in reserves.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_process_limits(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    trans_tuple = transport_process_topology_tuples(input_data)
    lim_tuple = fixed_limit_process_topology_tuples(input_data)
    cf_balance_tuple = cf_process_topology_tuples(input_data)
    v_flow = model_contents["variable"]["v_flow"]
    processes = input_data.processes

    # Transport processes
    for tup in trans_tuple
        set_upper_bound(v_flow[validate_tuple(model_contents, tup, 4)], filter(x -> x.sink == tup[3], processes[tup[1]].topos)[1].capacity)
    end

    # cf processes
    cf_fac_fix = model_contents["expression"]["cf_fac_fix"] = OrderedDict()
    cf_fac_up = model_contents["expression"]["cf_fac_up"] = OrderedDict()
    for tup in cf_balance_tuple
        cf_fac_fix[tup] = AffExpr(0.0)
        cf_fac_up[tup] = AffExpr(0.0)
        cf_val = processes[tup[1]].cf(tup[4], tup[5])
        cap = filter(x -> (x.sink == tup[3]), processes[tup[1]].topos)[1].capacity
        if processes[tup[1]].is_cf_fix
            add_to_expression!(cf_fac_fix[tup], sum(v_flow[validate_tuple(model_contents, tup, 4)]) - cf_val * cap)
        else
            add_to_expression!(cf_fac_up[tup], sum(v_flow[validate_tuple(model_contents, tup, 4)]) - cf_val * cap)
        end
    end

    cf_fix_bal_eq = @constraint(model, cf_fix_bal_eq[tup in collect(keys(cf_fac_fix))], cf_fac_fix[tup] == 0)
    cf_up_bal_eq = @constraint(model, cf_up_bal_eq[tup in collect(keys(cf_fac_up))], cf_fac_up[tup] <= 0)
    model_contents["constraint"]["cf_fix_bal_eq"] = cf_fix_bal_eq
    model_contents["constraint"]["cf_up_bal_eq"] = cf_up_bal_eq

    # Base expressions as Dict:
    e_lim_max = model_contents["expression"]["e_lim_max"] = OrderedDict()
    e_lim_min = model_contents["expression"]["e_lim_min"] = OrderedDict()
    e_lim_res_max = model_contents["expression"]["e_lim_res_max"] = OrderedDict()
    e_lim_res_min = model_contents["expression"]["e_lim_res_min"] = OrderedDict()
    
    for tup in lim_tuple
        e_lim_max[tup] = AffExpr(0.0)
        e_lim_min[tup] = AffExpr(0.0)
        e_lim_res_max[tup] = AffExpr(0.0)
        e_lim_res_min[tup] = AffExpr(0.0)
    end

    # online processes
    if input_data.setup.contains_online
        proc_online_tuple = online_process_tuples(input_data)
        p_online = filter(x -> processes[x[1]].is_online, lim_tuple)
        
        if !isempty(proc_online_tuple)
            v_online = model_contents["variable"]["v_online"]
            for tup in p_online
                topo = filter(x->x.sink == tup[3] && x.source == tup[2], processes[tup[1]].topos)[1]
                if isempty(topo.cap_ts)
                    cap = topo.capacity
                else
                    cap = topo.cap_ts(tup[4], tup[5])
                end
                add_to_expression!(e_lim_max[tup], -processes[tup[1]].load_max * cap * v_online[validate_tuple(model_contents, (tup[1], tup[4], tup[5]), 2)])
                add_to_expression!(e_lim_min[tup], -processes[tup[1]].load_min * cap * v_online[validate_tuple(model_contents, (tup[1], tup[4], tup[5]), 2)])
            end
        end
    end

    # non-online, non-cf processes
    p_offline = filter(x -> !(processes[x[1]].is_online), lim_tuple)
    for tup in p_offline
        topo = filter(x->x.sink == tup[3] && x.source == tup[2], processes[tup[1]].topos)[1]
        if isempty(topo.cap_ts)
            cap = topo.capacity
        else
            cap = topo.cap_ts(tup[4], tup[5])
        end
        add_to_expression!(e_lim_max[tup], -cap)
    end

    # reserve processes
    if input_data.setup.contains_reserves
        v_load = model_contents["variable"]["v_load"]
        res_p_tuples = unique(map(x -> x[3:end], reserve_process_tuples(input_data)))
        res_pot_cons_tuple = unique(map(x -> (x[1:5]), consumer_reserve_process_tuples(input_data)))
        res_pot_prod_tuple = unique(map(x -> (x[1:5]), producer_reserve_process_tuples(input_data)))
        v_reserve = model_contents["variable"]["v_reserve"]
        res_lim_tuple = unique(map(y -> (y[1:3]), filter(x -> input_data.processes[x[1]].is_res, lim_tuple)))

        for tup in res_lim_tuple
            p_reserve_cons_up = filter(x ->x[1] == "res_up" && x[3:end] == tup, res_pot_cons_tuple)
            p_reserve_prod_up = filter(x ->x[1] == "res_up" && x[3:end] == tup, res_pot_prod_tuple)
            p_reserve_cons_down = filter(x ->x[1] == "res_down" && x[3:end] == tup, res_pot_cons_tuple)
            p_reserve_prod_down = filter(x ->x[1] == "res_down" && x[3:end] == tup, res_pot_prod_tuple)

            for s in scenarios(input_data), t in input_data.temporals.t
                index_tup = (tup[1], tup[2], tup[3], s, t)
                p_r_c_up = map(x -> (x[1], x[2], x[3], x[4], x[5], s, t), p_reserve_cons_up)
                p_r_p_up = map(x -> (x[1], x[2], x[3], x[4], x[5], s, t), p_reserve_prod_up)
                p_r_c_down = map(x -> (x[1], x[2], x[3], x[4], x[5], s, t), p_reserve_cons_down)
                p_r_p_down = map(x -> (x[1], x[2], x[3], x[4], x[5], s, t), p_reserve_prod_down)
                if !isempty(p_reserve_cons_up)
                    add_to_expression!(e_lim_res_min[index_tup], -sum(v_reserve[validate_tuples(model_contents, p_r_c_up, 6)]))
                end
                if !isempty(p_reserve_prod_up)
                    add_to_expression!(e_lim_res_max[index_tup], sum(v_reserve[validate_tuples(model_contents, p_r_p_up, 6)]))
                end
                if !isempty(p_reserve_cons_down)
                    add_to_expression!(e_lim_res_max[index_tup], sum(v_reserve[validate_tuples(model_contents, p_r_c_down, 6)]))
                end
                if !isempty(p_reserve_prod_down)
                    add_to_expression!(e_lim_res_min[index_tup], -sum(v_reserve[validate_tuples(model_contents, p_r_p_down, 6)]))
                end
            end
        end

        v_load_max_eq = @constraint(model, v_load_max_eq[tup in res_p_tuples], v_load[validate_tuple(model_contents, tup, 4)] + e_lim_max[tup] + e_lim_res_max[tup] <= 0)
        v_load_min_eq = @constraint(model, v_load_min_eq[tup in res_p_tuples], v_load[validate_tuple(model_contents, tup, 4)] + e_lim_min[tup] + e_lim_res_min[tup] >= 0)
        model_contents["constraint"]["v_load_max_eq"] = v_load_max_eq
        model_contents["constraint"]["v_load_min_eq"] = v_load_min_eq
    end 

    v_flow_max_eq = @constraint(model, v_flow_max_eq[tup in collect(keys(e_lim_max))], v_flow[validate_tuple(model_contents, tup, 4)] + e_lim_max[tup] <= 0)
    v_flow_min_eq = @constraint(model, v_flow_min_eq[tup in collect(keys(e_lim_min))], v_flow[validate_tuple(model_contents, tup, 4)] + e_lim_min[tup] >= 0)

    model_contents["constraint"]["v_flow_max_eq"] = v_flow_max_eq
    model_contents["constraint"]["v_flow_min_eq"] = v_flow_min_eq
end



"""
    setup_reserve_realisation(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup constraints for reserve realisation. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_reserve_realisation(model_contents::OrderedDict, input_data::Predicer.InputData)
    if input_data.setup.contains_reserves
        model = model_contents["model"]

        markets = input_data.markets

        v_res_final = model_contents["variable"]["v_res_final"]
        v_flow = model_contents["variable"]["v_flow"]
        v_load = model_contents["variable"]["v_load"]

        v_res_real_tot = model_contents["expression"]["v_res_real_tot"] = OrderedDict()
        v_res_real = model_contents["expression"]["v_res_real"] = OrderedDict()
        v_res_real_node = model_contents["expression"]["v_res_real_node"] = OrderedDict()
        v_res_real_flow = model_contents["expression"]["v_res_real_flow"] = OrderedDict()
        v_res_real_flow_tot = model_contents["expression"]["v_res_real_flow_tot"] = OrderedDict()
    
        res_market_dir_tups = reserve_market_directional_tuples(input_data)
        res_market_tuples = reserve_market_tuples(input_data)
        nodegroup_res = nodegroup_reserves(input_data)
        node_res = node_reserves(input_data)
        res_process_tuples = reserve_process_tuples(input_data)
        process_tuples = process_topology_tuples(input_data)
        res_groups = reserve_groups(input_data)
        groups = create_group_tuples(input_data)

        rpt = unique(map(x -> (x[3:end]), res_process_tuples))
        rpt_begin = unique(map(x -> (x[3:5]), res_process_tuples))
        reduced_process_tuples = unique(map(x -> (x[1:3]), process_tuples))   

        # if no reserve realisation in the model. 
        # set v_flow == v_load for all reserve processes. 
        if !input_data.setup.reserve_realisation
            no_res_real_con = @constraint(model, no_res_real_con[tup in rpt], v_flow[validate_tuple(model_contents, tup, 4)] == v_load[validate_tuple(model_contents, tup, 4)])
            model_contents["constraint"]["no_res_real_con"] = no_res_real_con
        end

        # Set realisation within nodegroup to be equal to total reserve * realisation
        for tup in nodegroup_res
            v_res_real_tot[tup] = AffExpr(0.0)
            v_res_real_node[tup] = AffExpr(0.0)
            for res_tup in filter(x -> x[2] == tup[1] && x[4] == tup[2] && x[5] == tup[3], res_market_dir_tups)
                res_final_tup = (res_tup[1], res_tup[4:5]...)
                real = markets[res_tup[1]].realisation(res_tup[4])(res_tup[5])
                if res_tup[3] == "res_up"
                    add_to_expression!(v_res_real_tot[tup], real * v_res_final[validate_tuple(model_contents, res_final_tup, 2)])
                elseif res_tup[3] == "res_down"
                    add_to_expression!(v_res_real_tot[tup], -1.0 * real * v_res_final[validate_tuple(model_contents, res_final_tup, 2)])
                end
            end
        end

        # create process-wise reserve_realisation expression "v_res_real_flow"
        for p_tup in reduced_process_tuples
            res_p_tup = unique(filter(x -> x == p_tup, rpt_begin))
            for s in scenarios(input_data), t in input_data.temporals.t
                p_tup_with_s_and_t = (p_tup[1], p_tup[2], p_tup[3], s, t)
                v_res_real_flow[p_tup_with_s_and_t] = AffExpr(0.0)
                if !isempty(res_p_tup)
                    add_to_expression!(
                        v_res_real_flow[p_tup_with_s_and_t],
                        v_flow[validate_tuple(model_contents, p_tup_with_s_and_t, 4)]
                        - v_load[validate_tuple(model_contents, p_tup_with_s_and_t, 4)])
                end
            end
        end

        # create expression for node-wise realisation
        for n_tup in node_res
            n = n_tup[1]
            s = n_tup[2]
            t = n_tup[3]
            v_res_real[n_tup] = AffExpr(0.0)
            prod_tups = unique(filter(x -> x[3] == n && x[4] == s && x[5] == t, rpt))
            cons_tups = unique(filter(x -> x[2] == n && x[4] == s && x[5] == t, rpt))
            for pt in prod_tups
                add_to_expression!(v_res_real[n_tup], v_res_real_flow[pt])
            end
            for ct in cons_tups
                add_to_expression!(v_res_real[n_tup], -v_res_real_flow[ct])
            end
        end



        # set realisation within nodegroup to be equal to node-wise realisation within members of the nodegroup
        # real(ng) == sumof real n for n in ng
        for ng_tup in nodegroup_res
            for n in unique(map(x -> x[3], filter(y -> y[2] == ng_tup[1], groups)))
                add_to_expression!(v_res_real_node[ng_tup], v_res_real[(n, ng_tup[2], ng_tup[3])])
            end
        end

        res_real_eq = @constraint(model, res_real_eq[tup in nodegroup_res], v_res_real_tot[tup] == v_res_real_node[tup])
        model_contents["constraint"]["res_real_eq"] = res_real_eq


        # ensure that the realisation of reserve rp is equal to the realisation of processes in the processgroup of the reserve
        # Ensures that the realisation is done by the "correct" processes. 
        # reserve-specific realisation = sumof process_realisation for p in reserve processgroup. 
        
        for res in unique(map(x -> x[1], res_market_tuples))
            res_ng = input_data.markets[res].node
            res_ns = unique(map(x -> x[3], filter(y -> y[2] == res_ng, groups)))
            res_ps = unique(map(y -> y[5], filter(x -> x[3] == res, res_groups)))

            for res_p in res_ps
                prod_tups = filter(x -> x[1] == res_p && x[3] in res_ns, rpt_begin)
                cons_tups = filter(x -> x[1] == res_p && x[2] in res_ns, rpt_begin)
                for s in scenarios(input_data), t in input_data.temporals.t
                    v_res_real_flow_tot[(res_ng, s, t)] = AffExpr(0.0)
                    prod_tups_with_s_and_t = map(x -> (x[1], x[2], x[3], s, t), prod_tups)
                    cons_tups_with_s_and_t = map(x -> (x[1], x[2], x[3], s, t), cons_tups)
                    for pt in prod_tups_with_s_and_t
                        add_to_expression!(v_res_real_flow_tot[(res_ng, s, t)], v_res_real_flow[pt])
                    end
                    for ct in cons_tups_with_s_and_t
                        add_to_expression!(v_res_real_flow_tot[(res_ng, s, t)], -1.0 * v_res_real_flow[ct])
                    end
                end
            end
        end
        
        res_production_eq = @constraint(model, res_production_eq[tup in nodegroup_res], v_res_real_tot[tup] == v_res_real_flow_tot[tup])
        model_contents["constraint"]["res_production_eq"] = res_production_eq
    end
end


"""
    setup_reserve_balances(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup constraints for reserves. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_reserve_balances(model_contents::OrderedDict, input_data::Predicer.InputData)
    if input_data.setup.contains_reserves
        model = model_contents["model"]
        res_nodegroup = reserve_nodegroup_tuples(input_data)
        group_tuples = create_group_tuples(input_data)
        res_potential_tuple = reserve_process_tuples(input_data)
        res_tuple = reserve_market_directional_tuples(input_data)
        res_dir = model_contents["res_dir"]
        res_eq_updn_tuple = up_down_reserve_market_tuples(input_data)
        res_final_tuple = reserve_market_tuples(input_data)
        res_nodes_tuple = reserve_nodes(input_data)
        node_state_tuple = state_node_tuples(input_data)
        state_reserve_tuple = state_reserves(input_data)  
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        markets = input_data.markets
        nodes = input_data.nodes
        processes = input_data.processes
        v_reserve = model_contents["variable"]["v_reserve"]
        v_res = model_contents["variable"]["v_res"]
        v_res_final = model_contents["variable"]["v_res_final"]
        # state reserve balances
        if input_data.setup.contains_states
            for s_node in unique(map(x -> x[1], state_reserve_tuple))
                state_max = nodes[s_node].state.state_max
                state_min = nodes[s_node].state.state_min
                state_max_in = nodes[s_node].state.in_max
                state_max_out = nodes[s_node].state.out_max
                for s in scenarios, t in temporals.t
                    state_tup = filter(x -> x[1] == s_node && x[2] == s && x[3] == t, node_state_tuple)[1]
                    # Each storage node should have one process in and one out from the storage
                    dtf = temporals(t)
                    p_out_tup = filter(x -> x[1] == s_node && x[2] == "res_up" && x[4] == x[5] && x[7] == s && x[8] == t, state_reserve_tuple)
                    p_in_tup = filter(x -> x[1] == s_node && x[2] == "res_down" && x[4] == x[6] && x[7] == s && x[8] == t, state_reserve_tuple)
                    #TODO Name the constraints.
                    if !isempty(p_out_tup)
                        p_out_eff = processes[p_out_tup[1][4]].eff
                        # State in/out limit
                        @constraint(model, v_reserve[validate_tuple(model_contents, p_out_tup[1][2:end], 6)] <= state_max_out * p_out_eff)
                        # State value limit
                        @constraint(model, v_reserve[validate_tuple(model_contents, p_out_tup[1][2:end], 6)] <= (model_contents["variable"]["v_state"][validate_tuple(model_contents, state_tup, 2)] -  state_min) * p_out_eff / dtf)
                    end
                    if !isempty(p_in_tup)
                        p_in_eff = processes[p_in_tup[1][4]].eff
                        # State in/out limit
                        @constraint(model, v_reserve[validate_tuple(model_contents, p_in_tup[1][2:end], 6)] <= state_max_in / p_in_eff)
                        # State value limit
                        @constraint(model, v_reserve[validate_tuple(model_contents, p_in_tup[1][2:end], 6)] <= (state_max - model_contents["variable"]["v_state"][validate_tuple(model_contents, state_tup, 2)]) / p_in_eff / dtf)
                    end
                end
            end
        end

        # Reserve balances (from reserve potential to reserve product):
        e_res_bal_up = model_contents["expression"]["e_res_bal_up"] = OrderedDict()
        e_res_bal_dn = model_contents["expression"]["e_res_bal_up"] = OrderedDict()
        for tup in res_nodegroup
            ng = tup[1]
            r = tup[2]
            s = tup[3]
            t = tup[4]
            e_res_bal_up[tup] = AffExpr(0.0)
            e_res_bal_dn[tup] = AffExpr(0.0)

            res_u = filter(x -> x[3] == "res_up" && markets[x[1]].reserve_type == r && x[4] == s && x[5] == t && x[2] == ng, res_tuple)
            res_d = filter(x -> x[3] == "res_down" && markets[x[1]].reserve_type == r && x[4] == s && x[5] == t && x[2] == ng, res_tuple)
            if !isempty(res_u)
                add_to_expression!(e_res_bal_up[tup], -sum(v_res[validate_tuples(model_contents, res_u, 4)]))
            end
            if !isempty(res_d)
                add_to_expression!(e_res_bal_dn[tup], -sum(v_res[validate_tuples(model_contents, res_d, 4)]))
            end

            for n in unique(map(y -> y[3], filter(x -> x[2] == ng, group_tuples)))
                if n in res_nodes_tuple
                    res_pot_u = filter(x -> x[1] == "res_up" && x[2] == r && x[6] == s && x[7] == t && (x[4] == n || x[5] == n), res_potential_tuple)
                    res_pot_d = filter(x -> x[1] == "res_down" && x[2] == r && x[6] == s && x[7] == t && (x[4] == n || x[5] == n), res_potential_tuple)
                    if !isempty(res_pot_u)
                        add_to_expression!(e_res_bal_up[tup], sum(v_reserve[validate_tuples(model_contents, res_pot_u, 6)]))
                    end
                    if !isempty(res_pot_d)
                        add_to_expression!(e_res_bal_dn[tup], sum(v_reserve[validate_tuples(model_contents, res_pot_d, 6)]))
                    end
                end
            end
        end            

        # res_tuple is the tuple use for v_res (market, n, res_dir, s, t)
        # res_eq_updn_tuple (market, s, t)
        # the previously used tuple is res_eq_tuple, of form (ng, rt, s, t)
        res_eq_updn = @constraint(model, res_eq_updn[tup in res_eq_updn_tuple], v_res[validate_tuple(model_contents, (tup[1], markets[tup[1]].node, res_dir[1], tup[2], tup[3]), 4)] - v_res[validate_tuple(model_contents, (tup[1], markets[tup[1]].node, res_dir[2], tup[2], tup[3]), 4)] == 0)
        res_eq_up = @constraint(model, res_eq_up[tup in res_nodegroup], e_res_bal_up[tup] == 0)
        res_eq_dn = @constraint(model, res_eq_dn[tup in res_nodegroup], e_res_bal_dn[tup] == 0)
        model_contents["constraint"]["res_eq_updn"] = res_eq_updn
        model_contents["constraint"]["res_eq_up"] = res_eq_up
        model_contents["constraint"]["res_eq_dn"] = res_eq_dn

        # Final reserve product:
        # res_final_tuple (m, s, t)
        # r_tup = res_tuple = (m, n, res_dir, s, t)
        reserve_final_exp = model_contents["expression"]["reserve_final_exp"] = OrderedDict()
        for tup in res_final_tuple
            if markets[tup[1]].direction == "up" || markets[tup[1]].direction == "res_up"
                r_tup = filter(x -> x[1] == tup[1] && x[4] == tup[2] && x[5] == tup[3] && x[3] == "res_up", res_tuple)
            elseif markets[tup[1]].direction == "down" || markets[tup[1]].direction == "res_down" 
                r_tup = filter(x -> x[1] == tup[1] && x[4] == tup[2] && x[5] == tup[3] && x[3] == "res_down", res_tuple)
            elseif markets[tup[1]].direction == "up_down" || markets[tup[1]].direction == "res_up_down"
                r_tup = filter(x -> x[1] == tup[1] && x[4] == tup[2] && x[5] == tup[3], res_tuple)
            end
            reserve_final_exp[tup] = @expression(model, sum(v_res[validate_tuples(model_contents, r_tup, 4)]) .* (markets[tup[1]].direction == "up_down" ? 0.5 : 1.0) .- v_res_final[validate_tuple(model_contents, tup, 2)])
        end
        reserve_final_eq = @constraint(model, reserve_final_eq[tup in res_final_tuple], reserve_final_exp[tup] == 0)
        model_contents["constraint"]["reserve_final_eq"] = reserve_final_eq
    end
end


"""
    setup_ramp_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup process ramp constraints, based on ramp limits defined in input data and participation in reserves.  

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_ramp_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    ramp_tuple = Predicer.process_topology_ramp_times_tuples(input_data)
    v_flow = model_contents["variable"]["v_flow"]

    processes = input_data.processes
    temporals = input_data.temporals

    ramp_expr_up = model_contents["expression"]["ramp_expr_up"] = OrderedDict()
    ramp_expr_down = model_contents["expression"]["ramp_expr_down"] = OrderedDict()

    if input_data.setup.contains_reserves
        v_load = model_contents["variable"]["v_load"]
        res_proc_tuples =  unique(map(y -> y[3:end], Predicer.reserve_process_tuples(input_data)))
        res_nodes_tuple = Predicer.reserve_nodes(input_data)
        res_potential_tuple = Predicer.reserve_process_tuples(input_data)
        v_reserve = model_contents["variable"]["v_reserve"]
        reserve_types = input_data.reserve_type
        ramp_expr_res_up = model_contents["expression"]["ramp_expr_res_up"] = OrderedDict()
        ramp_expr_res_down = model_contents["expression"]["ramp_expr_res_down"] = OrderedDict()
        reduced_res_pot_tuple = unique(map(x -> (x[1:5]), res_potential_tuple))
        reduced_res_proc_tuple = unique(map(x -> (x[1:3]), res_proc_tuples))
    end

    if input_data.setup.contains_online
        v_start = model_contents["variable"]["v_start"]
        v_stop = model_contents["variable"]["v_stop"]
    end

    if input_data.setup.use_ramp_dummy_variables
        vq_ramp_up = model_contents["variable"]["vq_ramp_up"]
        vq_ramp_dw = model_contents["variable"]["vq_ramp_dw"]
    end

    previous_ts = Predicer.get_previous_t(input_data.temporals)
    previous_proc_tups = Predicer.previous_process_topology_tuples(input_data)
    reduced_ramp_tuple = unique(map(x -> (x[1:3]), ramp_tuple))

    for red_tup in reduced_ramp_tuple
        if processes[red_tup[1]].conversion == 1 && !processes[red_tup[1]].is_cf
            topo = filter(x -> x.source == red_tup[2] && x.sink == red_tup[3], processes[red_tup[1]].topos)[1]
            # if reserve process
            if processes[red_tup[1]].is_res && input_data.setup.contains_reserves && red_tup in reduced_res_proc_tuple
                res_tup_up = filter(x->x[1]=="res_up" && x[3:end]==red_tup, reduced_res_pot_tuple)
                res_tup_down = filter(x->x[1]=="res_down" && x[3:end]==red_tup, reduced_res_pot_tuple)
            end
            for s in scenarios(input_data), t in input_data.temporals.t
                tup = (red_tup[1], red_tup[2], red_tup[3], s, t)
                ramp_expr_up[tup] = AffExpr(0.0)
                ramp_expr_down[tup] = AffExpr(0.0)
                ramp_up_cap = topo.ramp_up * topo.capacity * temporals(tup[5])
                ramp_dw_cap = topo.ramp_down * topo.capacity * temporals(tup[5])

                # add ramp rate limit
                add_to_expression!(ramp_expr_up[tup], ramp_up_cap) 
                add_to_expression!(ramp_expr_down[tup], - ramp_dw_cap)

                # add ramp dummys if they are used
                if input_data.setup.use_ramp_dummy_variables
                    add_to_expression!(ramp_expr_up[tup], vq_ramp_up[validate_tuple(model_contents, tup, 4)])
                    add_to_expression!(ramp_expr_down[tup], -vq_ramp_dw[validate_tuple(model_contents, tup, 4)])
                end

                # if online process
                if processes[tup[1]].is_online
                    start_cap = max(0,processes[tup[1]].load_min-topo.ramp_up)*topo.capacity
                    stop_cap = max(0,processes[tup[1]].load_min-topo.ramp_down)*topo.capacity
                    add_to_expression!(ramp_expr_up[tup], start_cap * v_start[validate_tuple(model_contents, (tup[1], tup[4], tup[5]), 2)]) 
                    add_to_expression!(ramp_expr_down[tup], - stop_cap * v_stop[validate_tuple(model_contents, (tup[1], tup[4], tup[5]), 2)])
                end

                # if reserve process
                if processes[tup[1]].is_res && input_data.setup.contains_reserves && red_tup in reduced_res_proc_tuple
                    ramp_expr_res_up[tup] = AffExpr(0.0)
                    ramp_expr_res_down[tup] = AffExpr(0.0)
                    res_tup_up_with_s_and_t = map(x -> (x[1], x[2], x[3], x[4], x[5], s, t), res_tup_up)
                    res_tup_down_with_s_and_t = map(x -> (x[1], x[2], x[3], x[4], x[5], s, t), res_tup_down)
                    if red_tup[2] in res_nodes_tuple #consumer from node
                        for rtd in res_tup_down_with_s_and_t
                            add_to_expression!(ramp_expr_res_up[tup], -1 * sum(reserve_types[rtd[2]] .* v_reserve[validate_tuple(model_contents, rtd, 6)]))
                        end
                        for rtu in res_tup_up_with_s_and_t
                            add_to_expression!(ramp_expr_res_down[tup], sum(reserve_types[rtu[2]] .* v_reserve[validate_tuple(model_contents, rtu, 6)]))
                        end
                    elseif red_tup[3] in res_nodes_tuple #producer to node
                        for rtu in res_tup_up_with_s_and_t
                            add_to_expression!(ramp_expr_res_up[tup], -1 * sum(reserve_types[rtu[2]] .* v_reserve[validate_tuple(model_contents, rtu, 6)])) 
                        end
                        for rtd in res_tup_down_with_s_and_t
                            add_to_expression!(ramp_expr_res_down[tup], sum(reserve_types[rtd[2]] .* v_reserve[validate_tuple(model_contents, rtd, 6)])) 
                        end
                    end
                end
            end
        end
    end

    if input_data.setup.contains_reserves
        e_ramp_v_load = model_contents["expression"]["e_ramp_v_load"] = OrderedDict()
        for tup in res_proc_tuples
            e_ramp_v_load[tup] = AffExpr(0.0)
            if tup[5] == input_data.temporals.t[1]
                topo = filter(x -> tup[2] == x.source && tup[3] == x.sink, input_data.processes[tup[1]].topos)[1]
                add_to_expression!(e_ramp_v_load[tup], v_load[validate_tuple(model_contents, tup, 4)] - (topo.initial_load * topo.capacity))
            else
                add_to_expression!(e_ramp_v_load[tup], v_load[validate_tuple(model_contents, tup, 4)] - v_load[validate_tuple(model_contents, previous_proc_tups[tup], 4)])
            end
        end
    end

    e_ramp_v_flow = model_contents["expression"]["e_ramp_v_flow"] = OrderedDict()
    for tup in ramp_tuple
        e_ramp_v_flow[tup] = AffExpr(0.0)
        if tup[5] == input_data.temporals.t[1]
            topo = filter(x -> tup[2] == x.source && tup[3] == x.sink, input_data.processes[tup[1]].topos)[1]
            add_to_expression!(e_ramp_v_flow[tup], v_flow[validate_tuple(model_contents, tup, 4)] - (topo.initial_flow * topo.capacity))
        else
            add_to_expression!(e_ramp_v_flow[tup], v_flow[validate_tuple(model_contents, tup, 4)] - v_flow[validate_tuple(model_contents, previous_proc_tups[tup], 4)])
        end
    end

    if input_data.setup.contains_reserves
        if !isempty(ramp_expr_res_up)
            ramp_up_eq_v_load = @constraint(model, ramp_up_eq_v_load[tup in res_proc_tuples], e_ramp_v_load[tup] <= ramp_expr_up[tup] + ramp_expr_res_up[tup])
            ramp_down_eq_v_load = @constraint(model, ramp_down_eq_v_load[tup in res_proc_tuples], e_ramp_v_load[tup] >= ramp_expr_down[tup] + ramp_expr_res_down[tup])
            model_contents["constraint"]["ramp_up_eq_v_load"] = ramp_up_eq_v_load
            model_contents["constraint"]["ramp_down_eq_v_load"] = ramp_down_eq_v_load
        end
    end
        
    ramp_up_eq_v_flow = @constraint(model, ramp_up_eq_v_flow[tup in ramp_tuple], e_ramp_v_flow[tup] <= ramp_expr_up[tup])
    ramp_down_eq_v_flow = @constraint(model, ramp_down_eq_v_flow[tup in ramp_tuple], e_ramp_v_flow[tup] >= ramp_expr_down[tup])
    model_contents["constraint"]["ramp_up_eq_v_flow"] = ramp_up_eq_v_flow
    model_contents["constraint"]["ramp_down_eq_v_flow"] = ramp_down_eq_v_flow
end


"""
    setup_fixed_values(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup constraints for setting fixed process values at certain timesteps.   

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_fixed_values(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    fixed_value_tuple = fixed_market_tuples(input_data)
    v_bid = model_contents["expression"]["v_bid"]
    markets = input_data.markets
    scenarios = collect(keys(input_data.scenarios))
    
    if input_data.setup.contains_reserves
        v_res_final = model_contents["variable"]["v_res_final"]
    end
    
    fix_expr = model_contents["expression"]["fix_expr"] = OrderedDict()
    for m in keys(markets)
        if !isempty(markets[m].fixed)
            temps = map(x->x[1],markets[m].fixed)
            fix_vec = map(x->x[2],markets[m].fixed)

            if markets[m].type == "energy"
                for (t, fix_val) in zip(temps, fix_vec)
                    for s in scenarios
                        fix_expr[(m, s, t)] = @expression(model,v_bid[(m,s,t)]-fix_val)
                    end
                end
            elseif markets[m].type == "reserve" && input_data.setup.contains_reserves
                for (t, fix_val) in zip(temps, fix_vec)
                    for s in scenarios
                        fix(v_res_final[validate_tuple(model_contents, (m, s, t), 2)], fix_val; force=true)
                    end
                end
            end
        end
    end
    fixed_value_eq = @constraint(model, fixed_value_eq[tup in fixed_value_tuple], fix_expr[tup] == 0)
    model_contents["constraint"]["fixed_value_eq"] = fixed_value_eq
end


"""
    setup_bidding_curve_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup constraints for market bidding curves.   

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_bidding_curve_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    markets = input_data.markets
    b_slots = input_data.bid_slots
    bid_scen_tuple = bid_scenario_tuples(input_data)
    process_tuple = process_topology_tuples(input_data)
    balance_process_tuple = create_balance_market_tuple(input_data)
    v_flow = model_contents["variable"]["v_flow"]
    v_flow_bal = model_contents["variable"]["v_flow_bal"]
    v_bid_vol = model_contents["variable"]["v_bid_volume"]

    v_bid = model_contents["expression"]["v_bid"] = OrderedDict()
    e_bid_slot = OrderedDict()

    for tup in bid_scen_tuple
        v_bid[tup] = AffExpr(0.0)
        e_bid_slot[tup] = AffExpr(0.0)
        if markets[tup[1]].type == "energy"
            add_to_expression!(v_bid[tup],v_flow[filter(x->x[3]==tup[1] && x[5]==tup[3] && x[4]==tup[2],process_tuple)[1]],1.0)
            add_to_expression!(v_bid[tup],v_flow_bal[filter(x->x[1]==tup[1] && x[2]=="up" && x[4]==tup[3] && x[3]==tup[2],balance_process_tuple)[1]],1.0)
            add_to_expression!(v_bid[tup],v_flow[filter(x->x[2]==tup[1] && x[5]==tup[3] && x[4]==tup[2],process_tuple)[1]],-1.0)
            add_to_expression!(v_bid[tup],v_flow_bal[filter(x->x[1]==tup[1] && x[2]=="dw" && x[4]==tup[3] && x[3]==tup[2],balance_process_tuple)[1]],-1.0)
        else
            add_to_expression!(v_bid[tup],v_res_final[tup],1.0)
        end
        bn0 = b_slots[tup[1]].market_price_allocation[(tup[2],tup[3])][1]
        bn1 = b_slots[tup[1]].market_price_allocation[(tup[2],tup[3])][2]
        p0 = b_slots[tup[1]].prices[(tup[3],bn0)]
        p1 = b_slots[tup[1]].prices[(tup[3],bn1)]
        ps = markets[tup[1]].price(tup[2],tup[3])
        add_to_expression!(e_bid_slot[tup],v_bid_vol[(tup[1],bn0,tup[3])],1-(ps-p0)/(p1-p0))
        add_to_expression!(e_bid_slot[tup],v_bid_vol[(tup[1],bn1,tup[3])],(ps-p0)/(p1-p0))
    end
    bid_slot_eq = @constraint(model, bid_slot_eq[tup in bid_scen_tuple], v_bid[tup] == e_bid_slot[tup])
    model_contents["constraint"]["bid_slot_eq"] = bid_slot_eq
end

"""
    setup_bidding_volume_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup constraints for market bidding volumes.   

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_bidding_volume_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)
    tups = ((m, bs.slots[i - 1], bs.slots[i], t)
            for (m, bs) in input_data.bid_slots
            for i in 2 : length(bs.slots) for t in bs.time_steps)
    v_bid_vol = model_contents["variable"]["v_bid_volume"]
    @constraint(model_contents["model"], bid_vol[(m, s0, s1, t) = tups],
                v_bid_vol[(m, s1, t)] ≥ v_bid_vol[(m, s0, t)])
end

"""
    setup_bidding_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup constraints for market bidding.   

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_bidding_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    markets = input_data.markets
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    process_tuple = process_topology_tuples(input_data)
    balance_process_tuple = create_balance_market_tuple(input_data)
    
    v_flow = model_contents["variable"]["v_flow"]
    v_flow_bal = model_contents["variable"]["v_flow_bal"]
    v_bid = model_contents["expression"]["v_bid"] = OrderedDict()

    if input_data.setup.contains_reserves
        v_res_final = model_contents["variable"]["v_res_final"]
    end
    
    price_matr = OrderedDict()
    for m in keys(markets)
        if markets[m].is_bid
            pcols = []
            sizehint!(pcols, length(scenarios))
            for s in scenarios
                push!(pcols, values(markets[m].price(s).series))
                if markets[m].type == "energy"
                    for t in temporals.t
                        v_bid[(markets[m].name,s,t)] = AffExpr(0.0)
                        add_to_expression!(v_bid[(markets[m].name,s,t)],
                                v_flow[validate_tuple(model_contents, filter(x->x[3]==markets[m].name && x[5]==t && x[4]==s,process_tuple)[1], 4)],1.0)
                        add_to_expression!(v_bid[(markets[m].name,s,t)],
                                v_flow_bal[validate_tuple(model_contents, filter(x->x[1]==markets[m].name && x[2]=="up" && x[4]==t && x[3]==s,balance_process_tuple)[1], 3)],1.0)
                        add_to_expression!(v_bid[(markets[m].name,s,t)],
                                v_flow[validate_tuple(model_contents, filter(x->x[2]==markets[m].name && x[5]==t && x[4]==s,process_tuple)[1], 4)],-1.0)
                        add_to_expression!(v_bid[(markets[m].name,s,t)],
                                v_flow_bal[validate_tuple(model_contents, filter(x->x[1]==markets[m].name && x[2]=="dw" && x[4]==t && x[3]==s,balance_process_tuple)[1], 3)],-1.0)
                    end
                end
                if markets[m].type=="reserve"
                    for t in temporals.t
                        if markets[m].price(s)(t) == 0
                            fix(v_res_final[validate_tuple(model_contents, (m, s, t), 2)], 0.0; force=true)
                        end
                    end
                end
            end
            price_matr[m] = stack(pcols)
        end
    end
    function scen_pairs(ps)
        s_indx = sortperm(ps)
        ((scenarios[s_indx[k - 1 : k]], ps[s_indx[k - 1]] == ps[s_indx[k]])
         for k in 2 : length(s_indx))
    end
    cons = Dict()
    for m in keys(markets)
        markets[m].is_bid || continue
        slots = get(input_data.bid_slots, m, nothing)
        slot_times = Set(isnothing(slots) ? [] : slots.time_steps)
        for (i,t) in enumerate(temporals.t)
            t in slot_times && continue
            if markets[m].type == "energy"
                #XXX Is this ever different from m?
                mn = markets[m].name
                for (sns, eq) in scen_pairs(price_matr[m][i,:])
                    vars = [v_bid[(mn, s, t)] for s in sns]
                    cons[m, t, sns...] = (vars[2] - vars[1], eq)
                end
            elseif markets[m].type == "reserve" && input_data.setup.contains_reserves
                for (sns, eq) in scen_pairs(price_matr[m][i,:])
                    vars = [v_res_final[validate_tuple(model_contents, (m, s, t), 2)] for s in sns]
                    cons[m, t, sns...] = (vars[2] - vars[1], eq)
                end
            end
        end
    end
    @constraint(model, bidding[k = keys(cons)],
                cons[k][1] in (cons[k][2] ? MOI.EqualTo(0)
                                          : MOI.GreaterThan(0)))
end

"""
    setup_reserve_participation(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup participation limits for reserve

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_reserve_participation(model_contents::OrderedDict, input_data::Predicer.InputData)
    if input_data.setup.contains_reserves
        model = model_contents["model"]
        markets = input_data.markets
        v_res_online = model_contents["variable"]["v_reserve_online"]
        v_res_final = model_contents["variable"]["v_res_final"]
        res_lim_tuple = create_reserve_limits(input_data)
        res_online_up_expr = model_contents["expression"]["res_online_up_expr"] = OrderedDict()
        res_online_lo_expr = model_contents["expression"]["res_online_lo_expr"] = OrderedDict()
        for tup in res_lim_tuple
            max_bid = markets[tup[1]].max_bid
            min_bid = markets[tup[1]].min_bid
            if max_bid > 0
                res_online_up_expr[tup] = @expression(model,v_res_final[validate_tuple(model_contents, tup, 2)]-max_bid*v_res_online[validate_tuple(model_contents, tup, 2)])
            else
                res_online_up_expr[tup] = AffExpr(0.0)
            end
            if min_bid > 0
                res_online_lo_expr[tup] = @expression(model,v_res_final[validate_tuple(model_contents, tup, 2)]-min_bid*v_res_online[validate_tuple(model_contents, tup, 2)])
            else
                res_online_lo_expr[tup] = AffExpr(0.0)
            end
        end
        res_online_up = @constraint(model, res_online_up[tup in res_lim_tuple], res_online_up_expr[tup] <= 0)
        res_online_lo = @constraint(model, res_online_lo[tup in res_lim_tuple], res_online_lo_expr[tup] >= 0)
        model_contents["constraint"]["res_online_up"] = res_online_up
        model_contents["constraint"]["res_online_lo"] = res_online_lo
    end
end


"""
    setup_inflow_blocks(model_contents::OrderedDict, input_data::Predicer.InputData)    

Setup functionality, which can be used to model demand flexibility in Predicer. Only one block can 
be active per node per scenario. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_inflow_blocks(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    block_tuples = Predicer.block_tuples(input_data)
    v_block = model_contents["variable"]["v_block"]
    nodes = input_data.nodes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals

    node_block_expr = model_contents["expression"]["node_block_expr"] = OrderedDict()

    for n in collect(keys(nodes))
        for s in scenarios, t in temporals.t
            b_tups = filter(x -> x[2] == n && x[3] == s && x[4] == t, block_tuples)
            if !isempty(b_tups)
                node_block_expr[(n, s, t)] = AffExpr(0.0)
                for b_tup in b_tups
                    add_to_expression!(node_block_expr[(n, s, t)], v_block[(b_tup[1], n, Predicer.validate_tuple(model_contents,(s,input_data.inflow_blocks[b_tup[1]].start_time),1)[1])])
                end
            end
        end
    end
    node_block_eq = @constraint(model, node_block_eq[tup in collect(keys(node_block_expr))], sum(node_block_expr[tup]) <= 1)
    model_contents["constraint"]["node_block_eq"] = node_block_eq
end


"""
    setup_generic_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup generic constraints. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_generic_constraints(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    process_tuple = process_topology_tuples(input_data)
    online_tuple = online_process_tuples(input_data)
    state_tuple = state_node_tuples(input_data)
    setpoint_tups = setpoint_tuples(input_data)
    v_flow = model_contents["variable"]["v_flow"]
    if input_data.setup.contains_online
        v_online = model_contents["variable"]["v_online"]    
        reduced_online_tuple = unique(map(x -> (x[1]), online_tuple))
    end    
    if input_data.setup.contains_states
        v_state = model_contents["variable"]["v_state"]
        reduced_state_tuple = unique(map(x -> (x[1]), state_tuple))
    end
    
    v_setpoint = model_contents["variable"]["v_setpoint"]
    v_set_up = model_contents["variable"]["v_set_up"]
    v_set_down = model_contents["variable"]["v_set_down"]

    temporals = input_data.temporals
    gen_constraints = input_data.gen_constraints

    const_ts = OrderedDict()
    const_set = Dict()
    const_expr = model_contents["gen_expression"] = OrderedDict()
    setpoint_expr_lhs = OrderedDict()
    setpoint_expr_rhs = OrderedDict()

    reduced_process_tuple = unique(map(x -> (x[1:3]), process_tuple))

    for c in keys(gen_constraints)
        # Get timesteps for where there is data defined. (Assuming all scenarios are equal)
        gen_const_ts = keys(gen_constraints[c].factors[1].data(scenarios(input_data)[1]).series)
        # Get timesteps which are found in both temporals and gen constraints 
        relevant_ts = filter(t -> t in gen_const_ts, temporals.t)
        facs = gen_constraints[c].factors
        consta = gen_constraints[c].constant
        eq_dir = gen_constraints[c].type
        if !gen_constraints[c].is_setpoint
            const_ts[c] = relevant_ts
            const_set[c] = (eq_dir == "eq" ? MOI.EqualTo(0)
                            : eq_dir == "gt" ? MOI.GreaterThan(0)
                            : MOI.LessThan(0))
            const_expr[c] = OrderedDict(
                (s,t) => AffExpr(consta(s, t))
                for s in scenarios(input_data), t in relevant_ts)
            for f in facs
                if f.var_type == "flow"
                    p_flow = f.var_tuple
                    if input_data.processes[p_flow[1]].conversion == 1
                        tup = filter(x -> x[1] == p_flow[1] && (x[2] == p_flow[2] || x[3] == p_flow[2]), reduced_process_tuple)[1]
                    else
                        tup = filter(x -> x[1] == p_flow[1] && (x[2] == p_flow[1] || x[3] == p_flow[2]), reduced_process_tuple)[1]
                    end
                    for s in scenarios(input_data), t in relevant_ts
                        p_tup_with_s_and_t = (tup[1], tup[2], tup[3], s, t)
                        fac_data = f.data(s, t)
                        add_to_expression!(
                            const_expr[c][(s,t)], fac_data,
                            v_flow[validate_tuple(model_contents, p_tup_with_s_and_t, 4)])
                    end
                elseif f.var_type == "online"
                    p = f.var_tuple[1]
                    if input_data.processes[p].is_online
                        tup = unique(filter(x -> x == p, reduced_online_tuple))[1]
                    else
                        msg = "Factor " * string((p, f.var_tuple)) * " of gen_constraint " * string(c) * " has no online functionality!" 
                        throw(ErrorException(msg))
                    end
                    for s in scenarios(input_data), t in relevant_ts
                        online_tup_with_s_and_t = (p, s, t)
                        fac_data = f.data(s, t)
                        add_to_expression!(
                            const_expr[c][(s,t)], fac_data,
                            v_online[validate_tuple(model_contents, online_tup_with_s_and_t, 2)])
                    end
                elseif f.var_type == "state"
                    n = f.var_tuple[1]
                    if input_data.nodes[n].is_state
                        tup = filter(x -> x == n, reduced_state_tuple)[1]
                    else
                        msg = "Factor " * string((n, f.var_tuple)) * " of gen_constraint " * string(c) * " has no state functionality!" 
                        throw(ErrorException(msg))
                    end
                    for s in scenarios(input_data), t in relevant_ts
                        n_tup_with_s_and_t = (n, s, t)
                        fac_data = f.data(s, t)
                        add_to_expression!(const_expr[c][(s,t)],fac_data,v_state[validate_tuple(model_contents, n_tup_with_s_and_t, 2)])
                    end       
                end
            end
        else
            for s in scenarios(input_data), t in relevant_ts
                if !((c, s, t) in collect(keys(setpoint_expr_lhs)))
                    setpoint_expr_lhs[(c, s, t)] = AffExpr(0.0)
                    setpoint_expr_rhs[(c, s, t)] = AffExpr(0.0)
                else
                    msg = "Several columns with factors are not supported for setpoint constraints!" 
                    throw(ErrorException(msg))
                end
                for f in facs
                    if f.var_type == "state"
                        n = string(f.var_tuple[1])
                        d_max = input_data.nodes[n].state.state_max
                        add_to_expression!(setpoint_expr_lhs[(c, s, t)], v_state[validate_tuple(model_contents, (n, s, t), 2)])
                    elseif f.var_type == "flow"
                        p = f.var_tuple[1]
                        topo = filter(x -> x.source == f.var_tuple[2] || x.sink == f.var_tuple[2], input_data.processes[p].topos)[1]
                        d_max = topo.capacity
                        flow_tup = (p, topo.source, topo.sink, s, t)
                        add_to_expression!(setpoint_expr_lhs[(c, s, t)], v_flow[validate_tuple(model_contents, flow_tup, 4)])
                    else
                        msg = "Setpoint constraints cannot be used with variables of the type " * f.var_type * "!" 
                        throw(ErrorException(msg))
                    end
                    d_setpoint = f.data(s,t)
                    if eq_dir == "eq" # lower and upper setpoint are the same.  
                        d_upper = d_setpoint / d_max
                        d_lower = d_setpoint / d_max
                    elseif eq_dir == "gt" # No upper bound
                        d_upper = 1.0
                        d_lower = d_setpoint / d_max
                    else # eq_dir == "st" , meaning no lower bound
                        d_upper = d_setpoint / d_max
                        d_lower = 0.0
                    end
                    JuMP.set_upper_bound(v_set_up[(c, s, t)], (1.0 - d_upper) * d_max)
                    JuMP.set_upper_bound(v_set_down[(c, s, t)], d_lower * d_max)
                    JuMP.set_upper_bound(v_setpoint[(c, s, t)], (d_upper - d_lower) * d_max)
                    add_to_expression!(setpoint_expr_rhs[(c, s, t)], d_lower * d_max + v_setpoint[validate_tuple(model_contents, (c, s, t), 2)] + v_set_up[validate_tuple(model_contents, (c, s, t), 2)] - v_set_down[validate_tuple(model_contents, (c, s, t), 2)])                        
                end
            end
        end
    end
    @constraint(model,
                gen_con[c = keys(const_ts), s = scenarios(input_data),
                        t = const_ts[c]],
                const_expr[c][(s, t)] in const_set[c])
    model_contents["gen_constraint"] = gen_con
    @constraint(model, setpoint_eq[tup in setpoint_tups],
                setpoint_expr_lhs[tup] == setpoint_expr_rhs[tup])
    model_contents["constraint"]["setpoint_eq"] = setpoint_eq
end


"""
    setup_cost_calculations(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup expressions used for calculating the costs in the model. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_cost_calculations(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    process_tuple = process_topology_tuples(input_data)
    node_balance_tuple = balance_node_tuples(input_data)
    
    v_flow = model_contents["variable"]["v_flow"]
    v_bid = model_contents["expression"]["v_bid"]
    v_flow_bal = model_contents["variable"]["v_flow_bal"]

    scenarios = collect(keys(input_data.scenarios))
    nodes = input_data.nodes
    markets = input_data.markets
    processes = input_data.processes
    temporals = input_data.temporals

    # Commodity costs and market costs
    commodity_costs = model_contents["expression"]["commodity_costs"] = OrderedDict()
    market_costs = model_contents["expression"]["market_costs"] = OrderedDict()
    for s in scenarios
        commodity_costs[s] = AffExpr(0.0)
        market_costs[s] = AffExpr(0.0)
        for n in keys(nodes)
            #Commodity costs:
            if nodes[n].is_commodity
                flow_tups = filter(x -> x[2] == n && x[4] == s, process_tuple)
                cost_ts = nodes[n].cost(s)
                # Add to expression for each t found in series
                for tup in unique(validate_tuples(model_contents, flow_tups, 4))
                    add_to_expression!(commodity_costs[s], sum(v_flow[tup]) * cost_ts(tup[5]) * temporals(tup[5]))
                end
            end
            # Spot-Market costs and profits
            if nodes[n].is_market
                # bidding market with balance market
                if markets[n].is_bid
                    price_ts = markets[n].price(s)
                    price_up_ts = markets[n].up_price(s)
                    price_dw_ts = markets[n].down_price(s)
                    for t in temporals.t
                        tup = (nodes[n].name,s,t)
                        tup_up = (nodes[n].name,"up",s,t)
                        tup_dw = (nodes[n].name,"dw",s,t)
                        add_to_expression!(market_costs[s], -v_bid[tup] * price_ts(t) * temporals(t))
                        add_to_expression!(market_costs[s], v_flow_bal[validate_tuple(model_contents, tup_up, 3)] * price_up_ts(t) * temporals(t))
                        add_to_expression!(market_costs[s], -v_flow_bal[validate_tuple(model_contents, tup_dw, 3)] * price_dw_ts(t) * temporals(t))
                    end
                # non-bidding market
                else
                    flow_out = filter(x -> x[2] == n && x[4] == s, process_tuple)
                    flow_in = filter(x -> x[3] == n && x[4] == s, process_tuple)
                    price_ts = markets[n].price(s)

                    for tup in flow_out
                        add_to_expression!(market_costs[s], sum(v_flow[validate_tuple(model_contents, tup, 4)]) * price_ts(tup[5]) * temporals(tup[5]))
                    end
                    # Assuming what goes into the node is sold and has a negatuive cost
                    for tup in flow_in
                        add_to_expression!(market_costs[s],  - sum(v_flow[validate_tuple(model_contents, tup, 4)]) * price_ts(tup[5]) * temporals(tup[5]))
                    end
                end
            end
        end
    end

    # VOM_costs
    vom_costs = model_contents["expression"]["vom_costs"] = OrderedDict()
    for s in scenarios
        vom_costs[s] = AffExpr(0.0)
        for tup in unique(map(x->(x[1],x[2],x[3]),process_tuple))
            vom = filter(x->x.source == tup[2] && x.sink == tup[3], processes[tup[1]].topos)[1].VOM_cost
            if vom != 0
                flows = filter(x -> x[1:3] == tup && x[4] == s, process_tuple)
                for f in flows
                    add_to_expression!(vom_costs[s], sum(v_flow[validate_tuple(model_contents, f, 4)]) * vom * temporals(f[5]))
                end
            end
        end
    end

    # Start costs
    start_costs = model_contents["expression"]["start_costs"] = OrderedDict()
    for s in scenarios
        start_costs[s] = AffExpr(0.0)
    end
    if input_data.setup.contains_online
        proc_online_tuple = online_process_tuples(input_data)
        for s in scenarios
            for p in keys(processes)
                start_tup = filter(x->x[1] == p && x[2]==s,proc_online_tuple)
                if !isempty(start_tup)
                    v_start = model_contents["variable"]["v_start"]
                    cost = processes[p].start_cost
                    add_to_expression!(start_costs[s], sum(v_start[validate_tuples(model_contents, start_tup, 2)]) * cost)
                end
            end
        end
    end

    # Reserve profits:
    reserve_costs = model_contents["expression"]["reserve_costs"] = OrderedDict()
    for s in scenarios
        reserve_costs[s] = AffExpr(0.0)
    end
    if input_data.setup.contains_reserves
        v_res_final = model_contents["variable"]["v_res_final"]
        res_final_tuple = reserve_market_tuples(input_data)
        for s in scenarios
            for tup in filter(x -> x[2] == s, res_final_tuple)
                price = markets[tup[1]].price(s, tup[3])
                add_to_expression!(reserve_costs[s],-price*v_res_final[validate_tuple(model_contents, tup, 2)])
            end
        end
    end

    # reserve activation profits
    reserve_activation_costs = model_contents["expression"]["reserve_activation_costs"] = OrderedDict()
    for s in scenarios
        reserve_activation_costs[s] = AffExpr(0.0)
    end
    if input_data.setup.contains_reserves
        v_res_final = model_contents["variable"]["v_res_final"]
        res_final_tup = reserve_market_tuples(input_data)
        for s in scenarios
            for tup in filter(x -> x[2] == s, res_final_tup)
                real_p = input_data.markets[tup[1]].realisation(tup[2], tup[3])
                act_p = input_data.markets[tup[1]].reserve_activation_price(tup[2], tup[3])
                add_to_expression!(reserve_activation_costs[s], v_res_final[validate_tuple(model_contents, tup, 2)] * real_p * act_p)
            end
        end
    end

    # Reserve fee costs:
    reserve_fees = model_contents["expression"]["reserve_fee_costs"] = OrderedDict()
    for s in scenarios
        reserve_fees[s] = AffExpr(0.0)
    end
    if input_data.setup.contains_reserves
        v_reserve_online = model_contents["variable"]["v_reserve_online"]
        res_online_tuple = create_reserve_limits(input_data)
        for s in scenarios
            for tup in filter(x->x[2] == s, res_online_tuple)
                add_to_expression!(reserve_fees[s], markets[tup[1]].fee * v_reserve_online[validate_tuple(model_contents, tup, 2)])
            end
        end
    end

    # Setpoint deviation costs
    setpoint_deviation_costs = model_contents["expression"]["setpoint_deviation_costs"] = OrderedDict()
    v_set_up = model_contents["variable"]["v_set_up"]
    v_set_down = model_contents["variable"]["v_set_down"]
    for s in scenarios
        setpoint_deviation_costs[s] = AffExpr(0.0)
    end
    for c in collect(keys(input_data.gen_constraints))
        if input_data.gen_constraints[c].is_setpoint
            penalty = input_data.gen_constraints[c].penalty
            for s in scenarios
                c_tups = filter(tup -> tup[1] == c && tup[2] == s, setpoint_tuples(input_data))
                for c_tup in c_tups
                    add_to_expression!(setpoint_deviation_costs[s], penalty * input_data.temporals(c_tup[3]) * (sum(v_set_up[validate_tuple(model_contents, c_tup, 2)]) + sum(v_set_down[validate_tuple(model_contents, c_tup, 2)])))
                end
            end
        end
    end

    # State residue costs
    state_residue_costs = model_contents["expression"]["state_residue_costs"] = OrderedDict()
    for s in scenarios
        state_residue_costs[s] = AffExpr(0.0)
    end
    if input_data.setup.contains_states
        v_state = model_contents["variable"]["v_state"]
        state_node_tuple = state_node_tuples(input_data)
        for s in scenarios
            for tup in filter(x -> x[3] == temporals.t[end] && x[2] == s, state_node_tuple)
                add_to_expression!(state_residue_costs[s], -1 * nodes[tup[1]].state.residual_value * v_state[validate_tuple(model_contents, tup, 2)])
            end
        end
    end

    # Dummy variable costs
    dummy_costs = model_contents["expression"]["dummy_costs"] = OrderedDict()
    p_node = input_data.setup.node_dummy_variable_cost
    p_ramp = input_data.setup.ramp_dummy_variable_cost

    if input_data.setup.use_node_dummy_variables
        vq_state_up = model_contents["variable"]["vq_state_up"]
        vq_state_dw = model_contents["variable"]["vq_state_dw"]
    end

    if input_data.setup.use_ramp_dummy_variables
        vq_ramp_up = model_contents["variable"]["vq_ramp_up"]
        vq_ramp_dw = model_contents["variable"]["vq_ramp_dw"]
    end
    for s in scenarios
        dummy_costs[s] = AffExpr(0.0) 
        if input_data.setup.use_node_dummy_variables
            for tup in filter(x->x[2]==s,node_balance_tuple)
                add_to_expression!(dummy_costs[s], sum(vq_state_up[validate_tuple(model_contents, tup, 2)])*p_node + sum(vq_state_dw[validate_tuple(model_contents, tup, 2)])*p_node)
            end
        end
        if input_data.setup.use_ramp_dummy_variables
            for tup in filter(x -> x[4] == s, process_topology_ramp_times_tuples(input_data))
                add_to_expression!(dummy_costs[s], sum(vq_ramp_up[validate_tuple(model_contents, tup, 4)])*p_ramp + sum(vq_ramp_dw[validate_tuple(model_contents, tup, 4)])*p_ramp)
            end
        end
    end
    

    # Total model costs
    total_costs = model_contents["expression"]["total_costs"] = OrderedDict()
    for s in scenarios
        total_costs[s] = sum(commodity_costs[s]) + sum(market_costs[s]) + sum(vom_costs[s]) + sum(reserve_costs[s]) + sum(start_costs[s]) + sum(state_residue_costs[s]) + sum(reserve_fees[s]) + sum(setpoint_deviation_costs[s]) + sum(dummy_costs[s]) + sum(reserve_activation_costs[s])
    end
end


"""
    setup_cvar_element(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup expressions used for calculating the cvar in the model. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_cvar_element(model_contents::OrderedDict, input_data::Predicer.InputData)
    if input_data.setup.contains_risk
        model = model_contents["model"]
        total_costs = model_contents["expression"]["total_costs"]
        v_var = model_contents["variable"]["v_var"]
        v_cvar_z = model_contents["variable"]["v_cvar_z"]
        scenarios = collect(keys(input_data.scenarios))
        scen_p = collect(values(input_data.scenarios))
        alfa = input_data.risk["alfa"]
        cvar_constraint = @constraint(model, cvar_constraint[s in scenarios], v_cvar_z[s] >= total_costs[s]-v_var)
        model_contents["constraint"]["cvar_constraint"] = cvar_constraint
        model_contents["expression"]["cvar"] = @expression(model, sum(v_var)+(1/(1-alfa))*sum(values(scen_p).*v_cvar_z[scenarios]))
    end
end


"""
    setup_objective_function(model_contents::OrderedDict, input_data::Predicer.InputData)

Sets up the objective function, which in this model aims to minimize the costs.
"""
function setup_objective_function(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    total_costs = model_contents["expression"]["total_costs"]
    scen_p = collect(values(input_data.scenarios))
    if input_data.setup.contains_risk
        beta = input_data.risk["beta"]
        cvar = model_contents["expression"]["cvar"]
        @objective(model, Min, (1-beta)*sum(values(scen_p).*values(total_costs))+beta*cvar)
    else
        @objective(model, Min, sum(values(scen_p).*values(total_costs)))
    end
end
