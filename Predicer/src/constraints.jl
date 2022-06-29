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
    setup_node_balance(model_contents, input_data)
    setup_process_online_balance(model_contents, input_data)
    setup_process_balance(model_contents, input_data)
    setup_processes_limits(model_contents, input_data)
    setup_reserve_balances(model_contents, input_data)
    setup_ramp_constraints(model_contents, input_data)
    setup_fixed_values(model_contents, input_data)
    setup_bidding_constraints(model_contents, input_data)
    setup_generic_constraints(model_contents, input_data)
    setup_cost_calculations(model_contents, input_data)
    setup_cvar_element(model_contents, input_data)
    setup_objective_function(model_contents, input_data)
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
    res_dir = model_contents["res_dir"]
    node_state_tuple = state_node_tuples(input_data)
    node_balance_tuple = balance_node_tuples(input_data)
    res_tuple = reserve_market_directional_tuples(input_data)
    v_state = model_contents["variable"]["v_state"]
    v_flow = model_contents["variable"]["v_flow"]
    vq_state_up = model_contents["variable"]["vq_state_up"]
    vq_state_dw = model_contents["variable"]["vq_state_dw"]
    temporals = input_data.temporals  
    nodes = input_data.nodes
    markets = input_data.markets

    # Balance constraints
    # gather data in dicts, e_prod, etc, now point to a Dict()
    e_prod = model_contents["expression"]["e_prod"] = OrderedDict()
    e_cons = model_contents["expression"]["e_cons"] = OrderedDict()
    e_state = model_contents["expression"]["e_state"] = OrderedDict()
    
    for (i, tu) in enumerate(node_balance_tuple)
        # tu of form (node, scenario, t)
        # process tuple of form (process_name, source, sink, scenario, t)
        cons = filter(x -> (x[2] == tu[1] && x[4] == tu[2] && x[5] == tu[3]), process_tuple)
        prod = filter(x -> (x[3] == tu[1] && x[4] == tu[2] && x[5] == tu[3]), process_tuple)

        # get reserve markets for realisation
        real_up = []
        real_dw = []
        # tu of form (node, scenario, t)
        # res_tuple of form (res_market, node, res_dir, scenario, t)
        resu = filter(x-> x[2] == tu[1] && x[3] == res_dir[1] && x[4] == tu[2] && x[5] == tu[3],res_tuple)
        for ru in resu
            push!(real_up,markets[ru[1]].realisation)
        end
        resd = filter(x-> x[2] == tu[1] && x[3] == res_dir[2] && x[4] == tu[2] && x[5] == tu[3],res_tuple)
        for rd in resd
            push!(real_dw,markets[rd[1]].realisation)
        end
        # Check inflow for node
        if nodes[tu[1]].is_inflow
            inflow_val = nodes[tu[1]].inflow(tu[2], tu[3])
        else
            inflow_val = 0.0
        end

        v_res = model_contents["variable"]["v_res"]
        if isempty(cons)
            if isempty(resd)
                cons_expr = @expression(model, -vq_state_dw[tu] + inflow_val)
            else
                cons_expr = @expression(model, -vq_state_dw[tu] + inflow_val + sum(real_dw .* v_res[resd]))
            end
        else
            if isempty(resd)
                cons_expr = @expression(model, -sum(v_flow[cons]) - vq_state_dw[tu] + inflow_val)
            else
                cons_expr = @expression(model, -sum(v_flow[cons]) - vq_state_dw[tu] + inflow_val + sum(real_dw .* v_res[resd]))
            end
        end
        if isempty(prod)
            if isempty(resu)
                prod_expr = @expression(model, vq_state_up[tu])
            else
                prod_expr = @expression(model, vq_state_up[tu] - sum(real_up .* v_res[resu]))
            end
        else
            if isempty(resu)
                prod_expr = @expression(model, sum(v_flow[prod]) + vq_state_up[tu])
            else
                prod_expr = @expression(model, sum(v_flow[prod]) + vq_state_up[tu] - sum(real_up .* v_res[resu]))
            end
        end
        if nodes[tu[1]].is_state
            if tu[3] == temporals.t[1]
                state_expr = @expression(model, v_state[tu] - (1-nodes[tu[1]].state.state_loss*temporals(tu[3]))*nodes[tu[1]].state.initial_state)
            else
                state_expr = @expression(model, v_state[tu] - (1-nodes[tu[1]].state.state_loss*temporals(tu[3]))*v_state[node_balance_tuple[i-1]])
            end
        else
            state_expr = 0
        end

        e_prod[tu] = prod_expr
        e_cons[tu] = cons_expr
        e_state[tu] = state_expr
    end
    node_bal_eq = @constraint(model, node_bal_eq[tup in node_balance_tuple], temporals(tup[3]) * (e_prod[tup] + e_cons[tup]) == e_state[tup])
    node_state_max_up = @constraint(model, node_state_max_up[tup in node_state_tuple], e_state[tup] <= nodes[tup[1]].state.in_max * temporals(tup[3]))
    node_state_max_dw = @constraint(model, node_state_max_dw[tup in node_state_tuple], -e_state[tup] <= nodes[tup[1]].state.out_max * temporals(tup[3]))  
    model_contents["constraint"]["node_bal_eq"] = node_bal_eq
    model_contents["constraint"]["node_state_max_up"] = node_state_max_up
    model_contents["constraint"]["node_state_max_dw"] = node_state_max_dw
    for tu in node_state_tuple
        set_upper_bound(v_state[tu], nodes[tu[1]].state.state_max)
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
                # Note - initial online state is assumed 1!
                online_expr[tup] = @expression(model,v_start[tup]-v_stop[tup]-v_online[tup] + Int(processes[tup[1]].initial_state))
            else
                online_expr[tup] = @expression(model,v_start[tup]-v_stop[tup]-v_online[tup]+v_online[proc_online_tuple[i-1]])
            end
        end
        online_dyn_eq =  @constraint(model,online_dyn_eq[tup in proc_online_tuple], online_expr[tup] == 0)
        model_contents["constraint"]["online_dyn_eq"] = online_dyn_eq

        # Minimum online and offline periods
        min_online_rhs = OrderedDict()
        min_online_lhs = OrderedDict()
        min_offline_rhs = OrderedDict()
        min_offline_lhs = OrderedDict()
        for p in keys(processes)
            if processes[p].is_online
                min_online = processes[p].min_online * Dates.Minute(60)
                min_offline = processes[p].min_offline * Dates.Minute(60)
                for s in scenarios
                    for t in temporals.t
                        # get all timesteps that are within min_online/min_offline after t. 
                        on_hours = filter(x-> Dates.Minute(0) <= ZonedDateTime(x, temporals.ts_format) - ZonedDateTime(t, temporals.ts_format) <= min_online, temporals.t)
                        off_hours = filter(x-> Dates.Minute(0) <= ZonedDateTime(x, temporals.ts_format) - ZonedDateTime(t, temporals.ts_format) <= min_offline, temporals.t)

                        for h in on_hours
                            min_online_rhs[(p, s, t, h)] = v_start[(p,s,t)]
                            min_online_lhs[(p, s, t, h)] = v_online[(p,s,h)]
                        end
                        for h in off_hours
                            min_offline_rhs[(p, s, t, h)] = (1-v_stop[(p,s,t)])
                            min_offline_lhs[(p, s, t, h)] = v_online[(p,s,h)]
                        end
                    end
                end
            end
        end

        min_online_con = @constraint(model, min_online_con[tup in keys(min_online_lhs)], min_online_lhs[tup] >= min_online_rhs[tup])
        min_offline_con = @constraint(model, min_offline_con[tup in keys(min_offline_lhs)], min_offline_lhs[tup] <= min_offline_rhs[tup])

        model_contents["constraint"]["min_online_con"] = min_online_con
        model_contents["constraint"]["min_offline_con"] = min_offline_con
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
    proc_op_tuple = piecewise_efficiency_process_tuples(input_data)
    proc_op_balance_tuple = operative_slot_process_tuples(input_data)
    v_flow = model_contents["variable"]["v_flow"]
    #vq_flow_up = model_contents["variable"]["vq_flow_up"]
    #vq_flow_down = model_contents["variable"]["vq_flow_down"]

    v_flow_op_out = model_contents["variable"]["v_flow_op_out"]
    v_flow_op_in = model_contents["variable"]["v_flow_op_in"]
    v_flow_op_bin = model_contents["variable"]["v_flow_op_bin"]
    processes = input_data.processes

    # Fixed efficiency case:
    nod_eff = OrderedDict()
    for tup in proc_balance_tuple
        # fixed eff value
        if isempty(processes[tup[1]].eff_ts)
            eff = processes[tup[1]].eff
        # timeseries based eff
        else
            eff = processes[tup[1]].eff_ts(tup[2], tup[3])
        end
        sources = filter(x -> (x[1] == tup[1] && x[3] == tup[1] && x[4] == tup[2] && x[5] == tup[3]), process_tuple)
        sinks = filter(x -> (x[1] == tup[1] && x[2] == tup[1] && x[4] == tup[2] && x[5] == tup[3]), process_tuple)
        nod_eff[tup] = sum(v_flow[sinks]) - (length(sources) > 0 ? eff * sum(v_flow[sources]) : 0)
    end

    process_bal_eq = @constraint(model, process_bal_eq[tup in proc_balance_tuple], nod_eff[tup] == 0)
    model_contents["constraint"]["process_bal_eq"] = process_bal_eq

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

    flow_op_out_sum = @constraint(model,flow_op_out_sum[tup in proc_op_tuple],sum(v_flow_op_out[filter(x->x[1:3]==tup,proc_op_balance_tuple)]) == sum(v_flow[filter(x->x[2]==tup[1] && x[4] == tup[2] && x[5] == tup[3],process_tuple)]))
    flow_op_in_sum = @constraint(model,flow_op_in_sum[tup in proc_op_tuple],sum(v_flow_op_in[filter(x->x[1:3]==tup,proc_op_balance_tuple)]) == sum(v_flow[filter(x->x[3]==tup[1] && x[4] == tup[2] && x[5] == tup[3],process_tuple)]))
    model_contents["constraint"]["flow_op_out_sum"] = flow_op_out_sum
    model_contents["constraint"]["flow_op_in_sum"] = flow_op_in_sum

    flow_op_lo = @constraint(model,flow_op_lo[tup in proc_op_balance_tuple], v_flow_op_out[tup] >= v_flow_op_bin[tup] .* op_min[tup])
    flow_op_up = @constraint(model,flow_op_up[tup in proc_op_balance_tuple], v_flow_op_out[tup] <= v_flow_op_bin[tup] .* op_max[tup])
    flow_op_ef = @constraint(model,flow_op_ef[tup in proc_op_balance_tuple], v_flow_op_out[tup] == op_eff[tup] .* v_flow_op_in[tup])
    flow_bin = @constraint(model,flow_bin[tup in proc_op_tuple], sum(v_flow_op_bin[filter(x->x[1:3] == tup, proc_op_balance_tuple)]) == 1)
    model_contents["constraint"]["flow_op_lo"] = flow_op_lo
    model_contents["constraint"]["flow_op_up"] = flow_op_up
    model_contents["constraint"]["flow_op_ef"] = flow_op_ef
    model_contents["constraint"]["flow_bin"] = flow_bin

end


"""
    setup_processes_limits(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup constraints used for process limitations, such as min/max loads, unit starts and participation in reserves.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_processes_limits(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    trans_tuple = transport_process_topology_tuples(input_data)
    lim_tuple = fixed_limit_process_topology_tuples(input_data)
    cf_balance_tuple = cf_process_topology_tuples(input_data)
    res_pot_cons_tuple = consumer_reserve_process_tuples(input_data)
    res_pot_prod_tuple = producer_reserve_process_tuples(input_data)
    proc_online_tuple = online_process_tuples(input_data)
    v_flow = model_contents["variable"]["v_flow"]
    v_reserve = model_contents["variable"]["v_reserve"]
    
    processes = input_data.processes
    res_typ = collect(keys(input_data.reserve_type))
    res_dir = model_contents["res_dir"]

    # Transport processes
    for tup in trans_tuple
        set_upper_bound(v_flow[tup], filter(x -> x.sink == tup[3], processes[tup[1]].topos)[1].capacity)
    end

    # cf processes
    cf_fac_fix = model_contents["expression"]["cf_fac_fix"] = OrderedDict()
    cf_fac_up = model_contents["expression"]["cf_fac_up"] = OrderedDict()
    for tup in cf_balance_tuple

        cf_val = processes[tup[1]].cf(tup[4], tup[5])
        cap = filter(x -> (x.sink == tup[3]), processes[tup[1]].topos)[1].capacity
        if processes[tup[1]].is_cf_fix
            cf_fac_fix[tup] = @expression(model, sum(v_flow[tup]) - cf_val * cap)
        else
            cf_fac_up[tup] = @expression(model, sum(v_flow[tup]) - cf_val * cap)
        end
    end

    cf_fix_bal_eq = @constraint(model, cf_fix_bal_eq[tup in collect(keys(cf_fac_fix))], cf_fac_fix[tup] == 0)
    cf_up_bal_eq = @constraint(model, cf_up_bal_eq[tup in collect(keys(cf_fac_up))], cf_fac_up[tup] <= 0)
    model_contents["constraint"]["cf_fix_bal_eq"] = cf_fix_bal_eq
    model_contents["constraint"]["cf_up_bal_eq"] = cf_up_bal_eq

    # Other
    p_online = filter(x -> processes[x[1]].is_online, lim_tuple)
    p_offline = filter(x -> !(processes[x[1]].is_online), lim_tuple)
    p_reserve_cons = filter(x -> (res_dir[1], res_typ[1], x...) in res_pot_cons_tuple, lim_tuple)
    p_reserve_prod = filter(x -> (res_dir[1], res_typ[1], x...) in res_pot_prod_tuple, lim_tuple)

    # Base expressions as Dict:
    e_lim_max = model_contents["expression"]["e_lim_max"] = OrderedDict()
    e_lim_min = model_contents["expression"]["e_lim_min"] = OrderedDict()
    
    for tup in lim_tuple
        e_lim_max[tup] = AffExpr(0.0)
        e_lim_min[tup] = AffExpr(0.0)
    end

    for tup in p_reserve_prod
        res_up_tup = filter(x->x[1] == "res_up" && x[3:end] == tup,res_pot_prod_tuple)
        add_to_expression!(e_lim_max[tup], sum(v_reserve[(res_up_tup)]))
        res_down_tup = filter(x->x[1] == "res_down" && x[3:end] == tup,res_pot_prod_tuple)
        add_to_expression!(e_lim_min[tup], -sum(v_reserve[(res_down_tup)]))
    end

    for tup in p_reserve_cons
        res_up_tup = filter(x->x[1] == "res_down" && x[3:end] == tup,res_pot_cons_tuple)
        add_to_expression!(e_lim_max[tup], sum(v_reserve[(res_up_tup)]))
        res_down_tup = filter(x->x[1] == "res_up" && x[3:end] == tup,res_pot_cons_tuple)
        add_to_expression!(e_lim_min[tup], -sum(v_reserve[(res_down_tup)]))
    end

    if !isempty(proc_online_tuple)
        v_online = model_contents["variable"]["v_online"]
        for tup in p_online
            topo = filter(x->x.sink == tup[3] || x.source == tup[2], processes[tup[1]].topos)[1]
            if isempty(topo.cap_ts)
                cap = topo.capacity
            else
                cap = topo.cap_ts(tup[4], tup[5])
            end
            #cap = filter(x->x.sink == tup[3] || x.source == tup[2], processes[tup[1]].topos)[1].capacity
            add_to_expression!(e_lim_max[tup], -processes[tup[1]].load_max * cap * v_online[(tup[1], tup[4], tup[5])])
            add_to_expression!(e_lim_min[tup], -processes[tup[1]].load_min * cap * v_online[(tup[1], tup[4], tup[5])])
        end

        for tup in p_offline
            topo = filter(x->x.sink == tup[3] || x.source == tup[2], processes[tup[1]].topos)[1]
            if isempty(topo.cap_ts)
                cap = topo.capacity
            else
                cap = topo.cap_ts(tup[4], tup[5])
            end
            #cap = filter(x->x.sink == tup[3] || x.source == tup[2], processes[tup[1]].topos)[1].capacity
            if tup in p_reserve_prod || tup in p_reserve_cons
                add_to_expression!(e_lim_max[tup], -cap)
            else
                set_upper_bound(v_flow[tup], cap)
            end
        end
    end

    con_max_tuples = filter(x -> !(e_lim_max[x] == AffExpr(0)), keys(e_lim_max))
    con_min_tuples = filter(x -> !(e_lim_min[x] == AffExpr(0)), keys(e_lim_min))

    max_eq = @constraint(model, max_eq[tup in con_max_tuples], v_flow[tup] + e_lim_max[tup] <= 0)
    min_eq = @constraint(model, min_eq[tup in con_min_tuples], v_flow[tup] + e_lim_min[tup] >= 0)
    model_contents["constraint"]["max_eq"] = max_eq
    model_contents["constraint"]["min_eq"] = min_eq
end


"""
    setup_reserve_balances(model_contents::OrderedDict, input_data::Predicer.InputData)

Setup constraints for reserves. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::OrderedDict`: Dictionary containing data used to build the model. 
"""
function setup_reserve_balances(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    res_eq_tuple = reserve_node_tuples(input_data)
    res_eq_updn_tuple = up_down_reserve_market_tuples(input_data)
    res_potential_tuple = reserve_process_tuples(input_data)
    res_tuple = reserve_market_directional_tuples(input_data)
    res_final_tuple = reserve_market_tuples(input_data)
    res_nodes_tuple = reserve_nodes(input_data)
    res_typ = collect(keys(input_data.reserve_type))
    res_dir = model_contents["res_dir"]
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    markets = input_data.markets
    v_reserve = model_contents["variable"]["v_reserve"]
    v_res = model_contents["variable"]["v_res"]
    v_res_final = model_contents["variable"]["v_res_final"]

    # Reserve balances (from reserve potential to reserve product):
    e_res_bal_up = model_contents["expression"]["e_res_bal_up"] = OrderedDict()
    e_res_bal_dn = model_contents["expression"]["e_res_bal_up"] = OrderedDict()
    for n in res_nodes_tuple, r in res_typ, s in scenarios, t in temporals.t
        tup = (n, r, s, t) # same as res_eq_tuple
        e_res_bal_up[tup] = AffExpr(0.0)
        e_res_bal_dn[tup] = AffExpr(0.0)

        res_pot_u = filter(x -> x[1] == res_dir[1] && x[2] == r && x[6] == s && x[7] == t && (x[4] == n || x[5] == n), res_potential_tuple)
        res_pot_d = filter(x -> x[1] == res_dir[2] && x[2] == r && x[6] == s && x[7] == t && (x[4] == n || x[5] == n), res_potential_tuple)

        res_u = filter(x -> x[3] == res_dir[1] && markets[x[1]].reserve_type == r && x[4] == s && x[5] == t && x[2] == n, res_tuple)
        res_d = filter(x -> x[3] == res_dir[2] && markets[x[1]].reserve_type == r && x[4] == s && x[5] == t && x[2] == n, res_tuple)

        if !isempty(res_pot_u)
            add_to_expression!(e_res_bal_up[tup], sum(v_reserve[res_pot_u]))
        end
        if !isempty(res_pot_d)
            add_to_expression!(e_res_bal_dn[tup], sum(v_reserve[res_pot_d]))
        end

        if !isempty(res_u)
            add_to_expression!(e_res_bal_up[tup], -sum(v_res[res_u]))
        end
        if !isempty(res_d)
            add_to_expression!(e_res_bal_dn[tup], -sum(v_res[res_d]))
        end
    end            

    # res_tuple is the tuple use for v_res (market, n, res_dir, s, t)
    # res_eq_updn_tuple (market, s, t)
    # the previously used tuple is res_eq_tuple, of form (n, rt, s, t)
    res_eq_updn = @constraint(model, res_eq_updn[tup in res_eq_updn_tuple], v_res[(tup[1], markets[tup[1]].node, res_dir[1], tup[2], tup[3])] - v_res[(tup[1], markets[tup[1]].node, res_dir[2], tup[2], tup[3])] == 0)
    res_eq_up = @constraint(model, res_eq_up[tup in res_eq_tuple], e_res_bal_up[tup] == 0)
    res_eq_dn = @constraint(model, res_eq_dn[tup in res_eq_tuple], e_res_bal_dn[tup] == 0)
    model_contents["constraint"]["res_eq_updn"] = res_eq_updn
    model_contents["constraint"]["res_eq_up"] = res_eq_up
    model_contents["constraint"]["res_eq_dn"] = res_eq_dn

    # Final reserve product:
    # res_final_tuple (m, s, t)
    # r_tup = res_tuple = (m, n, res_dir, s, t)
    reserve_final_exp = model_contents["expression"]["reserve_final_exp"] = OrderedDict()
    for tup in res_final_tuple
        r_tup = filter(x -> x[1] == tup[1] && x[4] == tup[2] && x[5] == tup[3], res_tuple)
        reserve_final_exp[tup] = @expression(model, sum(v_res[r_tup]) .* (markets[tup[1]].direction == "up_down" ? 0.5 : 1.0) .- v_res_final[tup])
    end
    reserve_final_eq = @constraint(model, reserve_final_eq[tup in res_final_tuple], reserve_final_exp[tup] == 0)
    model_contents["constraint"]["reserve_final_eq"] = reserve_final_eq
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
    ramp_tuple = process_topology_ramp_times_tuples(input_data)
    process_tuple = process_topology_tuples(input_data)
    res_nodes_tuple = reserve_nodes(input_data)
    res_potential_tuple = reserve_process_tuples(input_data)
    v_reserve = model_contents["variable"]["v_reserve"]
    
    v_flow = model_contents["variable"]["v_flow"]

    res_dir = model_contents["res_dir"]
    reserve_types = input_data.reserve_type
   
    processes = input_data.processes
    temporals = input_data.temporals


    ramp_expr_up = model_contents["expression"]["ramp_expr_up"] = OrderedDict()
    ramp_expr_down = model_contents["expression"]["ramp_expr_down"] = OrderedDict()


    for tup in process_tuple
        if processes[tup[1]].conversion == 1 && !processes[tup[1]].is_cf
            if tup[5] != temporals.t[1]
                ramp_expr_up[tup] = AffExpr(0.0)
                ramp_expr_down[tup] = AffExpr(0.0)        
                topo = filter(x -> x.source == tup[2] && x.sink == tup[3], processes[tup[1]].topos)[1]
                ramp_up_cap = topo.ramp_up * topo.capacity * temporals(tup[5])
                ramp_dw_cap = topo.ramp_down * topo.capacity * temporals(tup[5])
                start_cap = max(0,processes[tup[1]].load_min-topo.ramp_up)*topo.capacity
                stop_cap = max(0,processes[tup[1]].load_min-topo.ramp_down)*topo.capacity
                if processes[tup[1]].is_online
                    v_start = model_contents["variable"]["v_start"]
                    v_stop = model_contents["variable"]["v_stop"]
                    if processes[tup[1]].is_res
                        res_tup_up = filter(x->x[1]==res_dir[1] && x[3:end]==tup,res_potential_tuple)
                        res_tup_down = filter(x->x[1]==res_dir[2] && x[3:end]==tup,res_potential_tuple)
                        if tup[2] in res_nodes_tuple
                            add_to_expression!(ramp_expr_up[tup], -1 * sum(values(reserve_types) .* v_reserve[res_tup_down]) + ramp_up_cap + start_cap * v_start[(tup[1], tup[4], tup[5])]) 
                            add_to_expression!(ramp_expr_down[tup], sum(values(reserve_types) .* v_reserve[res_tup_up]) - ramp_dw_cap - stop_cap * v_stop[(tup[1], tup[4], tup[5])]) 
                        elseif tup[3] in res_nodes_tuple
                            add_to_expression!(ramp_expr_up[tup], -1 * sum(values(reserve_types) .* v_reserve[res_tup_up]) + ramp_up_cap + start_cap * v_start[(tup[1], tup[4], tup[5])]) 
                            add_to_expression!(ramp_expr_down[tup], sum(values(reserve_types) .* v_reserve[res_tup_down]) - ramp_dw_cap - stop_cap * v_stop[(tup[1], tup[4], tup[5])]) 
                        else
                            add_to_expression!(ramp_expr_up[tup], ramp_up_cap + start_cap * v_start[(tup[1], tup[4], tup[5])]) 
                            add_to_expression!(ramp_expr_down[tup], - ramp_dw_cap - stop_cap * v_stop[(tup[1], tup[4], tup[5])]) 
                        end
                    else
                        add_to_expression!(ramp_expr_up[tup], ramp_up_cap + start_cap * v_start[(tup[1], tup[4], tup[5])]) 
                        add_to_expression!(ramp_expr_down[tup], - ramp_dw_cap - stop_cap * v_stop[(tup[1], tup[4], tup[5])]) 
                    end
                else
                    if processes[tup[1]].is_res
                        res_tup_up = filter(x->x[1]==res_dir[1] && x[3:end]==tup,res_potential_tuple)
                        res_tup_down = filter(x->x[1]==res_dir[2] && x[3:end]==tup,res_potential_tuple)
                        if tup[2] in res_nodes_tuple
                            add_to_expression!(ramp_expr_up[tup], -sum(values(reserve_types) .* v_reserve[res_tup_down]) + ramp_up_cap) 
                            add_to_expression!(ramp_expr_down[tup], sum(values(reserve_types) .* v_reserve[res_tup_up]) - ramp_dw_cap) 
                        elseif tup[3] in res_nodes_tuple
                            add_to_expression!(ramp_expr_up[tup], -sum(values(reserve_types) .* v_reserve[res_tup_up]) + ramp_up_cap) 
                            add_to_expression!(ramp_expr_down[tup], sum(values(reserve_types) .* v_reserve[res_tup_down]) - ramp_dw_cap) 
                        else
                            add_to_expression!(ramp_expr_up[tup], ramp_up_cap)
                            add_to_expression!(ramp_expr_down[tup], - ramp_dw_cap)
                        end
                    else
                        add_to_expression!(ramp_expr_up[tup], ramp_up_cap)
                        add_to_expression!(ramp_expr_down[tup], - ramp_dw_cap)
                    end
                end
            end
        end
    end

    ramp_up_eq = @constraint(model, ramp_up_eq[tup in ramp_tuple], v_flow[tup] - v_flow[process_tuple[findall(x->x==tup,process_tuple)[1]-1]] <= ramp_expr_up[tup])
    ramp_down_eq = @constraint(model, ramp_down_eq[tup in ramp_tuple], v_flow[tup] - v_flow[process_tuple[findall(x->x==tup,process_tuple)[1]-1]] >= ramp_expr_down[tup])
    model_contents["constraint"]["ramp_up_eq"] = ramp_up_eq
    model_contents["constraint"]["ramp_down_eq"] = ramp_down_eq
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
    
    process_tuple = process_topology_tuples(input_data)
    fixed_value_tuple = fixed_market_tuples(input_data)
    v_flow = model_contents["variable"]["v_flow"]
    v_res_final = model_contents["variable"]["v_res_final"]
    markets = input_data.markets
    scenarios = collect(keys(input_data.scenarios))
    
    fix_expr = model_contents["expression"]["fix_expr"] = OrderedDict()
    for m in keys(markets)
        if !isempty(markets[m].fixed)
            temps = map(x->x[1],markets[m].fixed)
            fix_vec = map(x->x[2],markets[m].fixed)

            if markets[m].type == "energy"
                for (t, fix_val) in zip(temps, fix_vec)
                    for s in scenarios
                        tup1 = filter(x->x[2]==m && x[4]==s && x[5]==t,process_tuple)[1]
                        tup2 = filter(x->x[3]==m && x[4]==s && x[5]==t,process_tuple)[1]
                        fix_expr[(m, s, t)] = @expression(model,v_flow[tup1]-v_flow[tup2]-fix_val)
                    end
                end
            elseif markets[m].type == "reserve"
                for (t, fix_val) in zip(temps, fix_vec)
                    for s in scenarios
                        fix(v_res_final[(m, s, t)], fix_val; force=true)
                    end
                end
            end
        end
    end
    fixed_value_eq = @constraint(model, fixed_value_eq[tup in fixed_value_tuple], fix_expr[tup] == 0)
    model_contents["constraint"]["fixed_value_eq"] = fixed_value_eq
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
    v_res_final = model_contents["variable"]["v_res_final"]
    v_flow = model_contents["variable"]["v_flow"]
    
    price_matr = OrderedDict()
    for m in keys(markets)
        if markets[m].is_bid
            for (i,s) in enumerate(scenarios)
                vec = map(x -> x[2], markets[m].price(s).series)
                if i == 1
                    price_matr[m] = vec
                else
                    price_matr[m] = hcat(price_matr[m],vec)
                end
            end
        end
    end
    for m in keys(markets)
        if markets[m].is_bid
            for (i,t) in enumerate(temporals.t)
                s_indx = sortperm((price_matr[m][i,:]))
                if markets[m].type == "energy"
                    for k in 2:length(s_indx)
                        if price_matr[m][s_indx[k]] == price_matr[m][s_indx[k-1]]
                            @constraint(model, v_flow[filter(x->x[3]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k]],process_tuple)[1]]-v_flow[filter(x->x[2]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k]],process_tuple)[1]] == 
                                v_flow[filter(x->x[3]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k-1]],process_tuple)[1]]-v_flow[filter(x->x[2]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k-1]],process_tuple)[1]])
                        else
                            @constraint(model, v_flow[filter(x->x[3]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k]],process_tuple)[1]]-v_flow[filter(x->x[2]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k]],process_tuple)[1]] >= 
                                v_flow[filter(x->x[3]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k-1]],process_tuple)[1]]-v_flow[filter(x->x[2]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k-1]],process_tuple)[1]])
                        end
                    end
                elseif markets[m].type == "reserve"
                    for k in 2:length(s_indx)
                        if price_matr[m][s_indx[k]] == price_matr[m][s_indx[k-1]]
                            @constraint(model, v_res_final[(m,scenarios[s_indx[k]],t)] == v_res_final[(m,scenarios[s_indx[k-1]],t)])
                        else
                            @constraint(model, v_res_final[(m,scenarios[s_indx[k]],t)] >= v_res_final[(m,scenarios[s_indx[k-1]],t)])
                        end

                    end
                end
            end
        end
    end
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
    v_flow = model_contents["variable"]["v_flow"]

    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    gen_constraints = input_data.gen_constraints

    const_expr = model_contents["gen_expression"] = OrderedDict()
    const_dict = model_contents["gen_constraint"] = OrderedDict()

    for c in keys(gen_constraints)
        const_expr[c] = OrderedDict((s,t) => AffExpr(0.0) for s in scenarios, t in temporals.t)
        facs = gen_constraints[c].factors
        consta = gen_constraints[c].constant
        eq_dir = gen_constraints[c].type
        for s in scenarios, t in temporals.t
            add_to_expression!(const_expr[c][(s,t)], consta(s, t))
            #add_to_expression!(const_expr[c][(s,t)],filter(x->x.scenario == s,consta)[1](t))
            for f in facs
                p_flow = f.flow
                tup = filter(x->x[1]==p_flow[1] && (x[2]==p_flow[2] || x[3]==p_flow[2]) && x[4]==s && x[5]==t,process_tuple)[1]
                fac_data = f.data(s, t)
                add_to_expression!(const_expr[c][(s,t)],fac_data,v_flow[tup])
            end
        end 
        if eq_dir == "eq"
            const_dict[c] = @constraint(model,[s in scenarios,t in temporals.t],const_expr[c][(s,t)]==0.0)
        elseif eq_dir == "gt"
            const_dict[c] = @constraint(model,[s in scenarios,t in temporals.t],const_expr[c][(s,t)]>=0.0)
        else
            const_dict[c] = @constraint(model,[s in scenarios,t in temporals.t],const_expr[c][(s,t)]<=0.0)
        end
    end
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
    proc_online_tuple = online_process_tuples(input_data)
    res_final_tuple = reserve_market_tuples(input_data)
    node_balance_tuple = balance_node_tuples(input_data)
    v_flow = model_contents["variable"]["v_flow"]

    v_res_final = model_contents["variable"]["v_res_final"]
    vq_state_up = model_contents["variable"]["vq_state_up"]
    vq_state_dw = model_contents["variable"]["vq_state_dw"]

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
                for tup in flow_tups
                    add_to_expression!(commodity_costs[s], sum(v_flow[tup]) * cost_ts(tup[5]) * temporals(tup[5]))
                end
            end
            # Spot-Market costs and profits
            if nodes[n].is_market
                flow_out = filter(x -> x[2] == n && x[4] == s, process_tuple)
                flow_in = filter(x -> x[3] == n && x[4] == s, process_tuple)
                price_ts = markets[n].price(s)

                for tup in flow_out
                    add_to_expression!(market_costs[s], sum(v_flow[tup]) * price_ts(tup[5]) * temporals(tup[5]))
                end
                # Assuming what goes into the node is sold and has a negatuive cost
                for tup in flow_in
                    add_to_expression!(market_costs[s],  - sum(v_flow[tup]) * price_ts(tup[5]) * temporals(tup[5]))
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
                    add_to_expression!(vom_costs[s], sum(v_flow[f]) * vom * temporals(f[5]))
                end
            end
        end
    end

    # Start costs
    start_costs = model_contents["expression"]["start_costs"] = OrderedDict()
    for s in scenarios
        start_costs[s] = AffExpr(0.0)
        for p in keys(processes)
            start_tup = filter(x->x[1] == p && x[2]==s,proc_online_tuple)
            if !isempty(start_tup)
                v_start = model_contents["variable"]["v_start"]
                cost = processes[p].start_cost
                add_to_expression!(start_costs[s], sum(v_start[start_tup]) * cost)
            end
        end
    end

    # Reserve profits:
    reserve_costs = model_contents["expression"]["reserve_costs"] = OrderedDict()
    for s in scenarios
        reserve_costs[s] = AffExpr(0.0)
        for tup in filter(x -> x[2] == s, res_final_tuple)
            price = markets[tup[1]].price(s, tup[3])
            add_to_expression!(reserve_costs[s],-price*v_res_final[tup])
        end
    end

    # Dummy variable costs
    dummy_costs = model_contents["expression"]["dummy_costs"] = OrderedDict()
    p = 1000000
    # State dummy variables
    # Process balance dummy variables?
    for s in scenarios
        dummy_costs[s] = AffExpr(0.0)
        for tup in filter(x->x[2]==s,node_balance_tuple)
            add_to_expression!(dummy_costs[s], sum(vq_state_up[tup])*p + sum(vq_state_dw[tup])*p)
        end
    end


    # Total model costs
    total_costs = model_contents["expression"]["total_costs"] = OrderedDict()
    for s in scenarios
        total_costs[s] = sum(commodity_costs[s] + sum(market_costs[s]) + sum(vom_costs[s]) + sum(reserve_costs[s]) + sum(start_costs[s]) + sum(dummy_costs[s]))
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


"""
    setup_objective_function(model_contents::OrderedDict, input_data::Predicer.InputData)

Sets up the objective function, which in this model aims to minimize the costs.
"""
function setup_objective_function(model_contents::OrderedDict, input_data::Predicer.InputData)
    model = model_contents["model"]
    total_costs = model_contents["expression"]["total_costs"]
    scen_p = collect(values(input_data.scenarios))
    beta = input_data.risk["beta"]
    cvar = model_contents["expression"]["cvar"]
    @objective(model, Min, (1-beta)*sum(values(scen_p).*values(total_costs))+beta*cvar)
end