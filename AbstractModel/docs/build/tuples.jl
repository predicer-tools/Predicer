# Calls for all tuples to be created and saved in the model dict. 
function create_tuples(model_contents, input_data)
    create_res_nodes_tuple(model_contents, input_data)
    create_res_tuple(model_contents, input_data)
    create_process_tuple(model_contents, input_data)
    create_res_potential_tuple(model_contents, input_data)
    create_proc_online_tuple(model_contents, input_data)
    create_res_pot_prod_tuple(model_contents, input_data)
    create_res_pot_cons_tuple(model_contents, input_data)
    create_node_state_tuple(model_contents, input_data)
    create_node_balance_tuple(model_contents, input_data)
    create_proc_potential_tuple(model_contents, input_data)
    create_proc_balance_tuple(model_contents, input_data)
    create_proc_op_balance_tuple(model_contents, input_data)
    create_proc_op_tuple(model_contents, input_data)
    #create_op_tuples(model_contents, input_data)
    create_cf_balance_tuple(model_contents, input_data)
    create_lim_tuple(model_contents, input_data)
    create_trans_tuple(model_contents, input_data)
    create_res_eq_tuple(model_contents, input_data)
    create_res_eq_updn_tuple(model_contents, input_data)
    create_res_final_tuple(model_contents, input_data)
    create_fixed_value_tuple(model_contents, input_data)
    create_ramp_tuple(model_contents, input_data)
end

function create_res_nodes_tuple(model_contents, input_data)
    res_nodes_tuple = []
    markets = input_data["markets"]
    for m in keys(markets)
        if markets[m].type == "reserve"
            push!(res_nodes_tuple, markets[m].node)
        end
    end
    model_contents["tuple"]["res_nodes_tuple"] = unique(res_nodes_tuple)
end

function create_res_tuple(model_contents, input_data)
    res_tuple = []
    markets = input_data["markets"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    res_dir = model_contents["res_dir"]
    for m in keys(markets)
        if markets[m].type == "reserve"
            if markets[m].direction in res_dir
                for s in scenarios, t in temporals
                    push!(res_tuple, (m, markets[m].node, markets[m].direction, s, t))
                end
            else
                for rd in res_dir, s in scenarios, t in temporals
                    push!(res_tuple, (m, markets[m].node, rd, s, t))
                end
            end
        end
    end
    model_contents["tuple"]["res_tuple"] = res_tuple
end

function create_process_tuple(model_contents, input_data)
    process_tuple = []
    processes = input_data["processes"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    for p in keys(processes), s in scenarios
        for topo in processes[p].topos
            for t in temporals
                push!(process_tuple, (p, topo.source, topo.sink, s, t))
            end
        end
    end
    model_contents["tuple"]["process_tuple"] = process_tuple
end

function create_proc_online_tuple(model_contents, input_data)
    proc_online_tuple = []
    processes = input_data["processes"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    for p in keys(processes)
        if processes[p].is_online
            for s in scenarios, t in temporals
                push!(proc_online_tuple, (p, s, t))
            end
        end
    end
    model_contents["tuple"]["proc_online_tuple"] = proc_online_tuple
end

function create_res_pot_prod_tuple(model_contents, input_data)
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    res_potential_tuple = model_contents["tuple"]["res_potential_tuple"]
    res_pot_prod_tuple = filter(x -> x[5] in res_nodes_tuple, res_potential_tuple)
    model_contents["tuple"]["res_pot_prod_tuple"] = res_pot_prod_tuple
end

function create_res_pot_cons_tuple(model_contents, input_data)
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    res_potential_tuple = model_contents["tuple"]["res_potential_tuple"]
    res_pot_cons_tuple = filter(x -> x[4] in res_nodes_tuple, res_potential_tuple)
    model_contents["tuple"]["res_pot_cons_tuple"] = res_pot_cons_tuple
end

function create_node_state_tuple(model_contents, input_data)
    node_state_tuple = []
    nodes = input_data["nodes"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    for n in keys(nodes)
        if !(nodes[n].is_commodity) & !(nodes[n].is_market) & nodes[n].is_state
            for s in scenarios, t in temporals
                push!(node_state_tuple, (n, s, t))
            end
        end
    end
    model_contents["tuple"]["node_state_tuple"] = node_state_tuple
end

function create_node_balance_tuple(model_contents, input_data)
    node_balance_tuple = []
    nodes = input_data["nodes"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    for n in keys(nodes)
        if !(nodes[n].is_commodity) & !(nodes[n].is_market)
            for s in scenarios, t in temporals
                push!(node_balance_tuple, (n, s, t))
            end
        end
    end
    model_contents["tuple"]["node_balance_tuple"] = node_balance_tuple
end

function create_res_potential_tuple(model_contents, input_data)
    res_potential_tuple = []
    processes = input_data["processes"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    res_typ = collect(keys(input_data["reserve_type"]))
    for p in keys(processes), s in scenarios, t in temporals
        for topo in processes[p].topos
            if (topo.source in res_nodes_tuple|| topo.sink in res_nodes_tuple) && processes[p].is_res
                for r in model_contents["res_dir"], rt in res_typ
                    push!(res_potential_tuple, (r, rt, p, topo.source, topo.sink, s, t))
                end
            end
        end
    end
    model_contents["tuple"]["res_potential_tuple"] = res_potential_tuple
end

function create_proc_potential_tuple(model_contents, input_data)
    res_potential_tuple = []
    res_dir = ["res_up", "res_down"]
    processes = input_data["processes"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    res_typ = collect(keys(input_data["reserve_type"]))
    for p in keys(processes), s in scenarios, t in temporals
        for topo in processes[p].topos
            if (topo.source in res_nodes_tuple|| topo.sink in res_nodes_tuple) && processes[p].is_res
                for r in res_dir, rt in res_typ
                    push!(res_potential_tuple, (r, rt, p, topo.source, topo.sink, s, t))
                end
            end
        end
    end
    model_contents["tuple"]["res_potential_tuple"] = res_potential_tuple
end

function create_proc_balance_tuple(model_contents, input_data)
    proc_balance_tuple = []
    processes = input_data["processes"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    for p in keys(processes)
        if processes[p].conversion == 1 && !processes[p].is_cf
            if isempty(processes[p].eff_fun)
                for s in scenarios, t in temporals
                    push!(proc_balance_tuple, (p, s, t))
                end
            end
        end
    end
    model_contents["tuple"]["proc_balance_tuple"] = proc_balance_tuple
end

function create_proc_op_balance_tuple(model_contents, input_data)
    proc_op_balance_tuple = []
    processes = input_data["processes"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    for p in keys(processes)
        if processes[p].conversion == 1 && !processes[p].is_cf
            if !isempty(processes[p].eff_fun)
                for s in scenarios, t in temporals, o in processes[p].eff_ops
                    push!(proc_op_balance_tuple, (p, s, t, o))
                end
            end
        end
    end
    model_contents["tuple"]["proc_op_balance_tuple"] = proc_op_balance_tuple
end

function create_proc_op_tuple(model_contents, input_data)
    proc_op_tuple = unique(map(x->(x[1],x[2],x[3]),model_contents["tuple"]["proc_op_balance_tuple"]))
    model_contents["tuple"]["proc_op_tuple"] = proc_op_tuple
end

#=function create_op_tuples(model_contents, input_data)
    op_min_tuple = []
    op_max_tuple = []
    op_eff_tuple = []
    processes = input_data["processes"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    for p in keys(processes) 
        if !isempty(processes[p].eff_fun)
            cap = sum(map(x->x.capacity,filter(x->x.source == p,processes[p].topos)))
            for s in scenarios, t in temporals
                for i in 1:length(processes[p].eff_ops)
                    if i==1
                        push!(op_min_tuple,0.0)
                    else
                        push!(op_min_tuple,processes[p].eff_fun[i-1][1]*cap)
                    end
                    push!(op_max_tuple,processes[p].eff_fun[i][1]*cap)
                    push!(op_eff_tuple,processes[p].eff_fun[i][2])
                end
            end
        end
    end
    model_contents["tuple"]["op_min_tuple"] = op_min_tuple
    model_contents["tuple"]["op_max_tuple"] = op_max_tuple
    model_contents["tuple"]["op_eff_tuple"] = op_eff_tuple
end=#

function create_cf_balance_tuple(model_contents, input_data)
    cf_balance_tuple = []
    processes = input_data["processes"]
    for p in keys(processes)
        if processes[p].is_cf
            push!(cf_balance_tuple, filter(x -> (x[1] == p), model_contents["tuple"]["process_tuple"])...)
        end
    end
    model_contents["tuple"]["cf_balance_tuple"] = cf_balance_tuple
end

function create_lim_tuple(model_contents, input_data)
    lim_tuple = []
    processes = input_data["processes"]
    process_tuple = model_contents["tuple"]["process_tuple"]
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    for p in keys(processes)
        if !processes[p].is_cf && (processes[p].conversion == 1)
            push!(lim_tuple, filter(x -> x[1] == p && (x[2] == p || x[2] in res_nodes_tuple), process_tuple)...)
        end
    end
    model_contents["tuple"]["lim_tuple"] = lim_tuple
end

function create_trans_tuple(model_contents, input_data)
    trans_tuple = []
    processes = input_data["processes"]
    process_tuple = model_contents["tuple"]["process_tuple"]
    for p in keys(processes)
        if !processes[p].is_cf && processes[p].conversion == 2
            push!(trans_tuple, filter(x -> x[1] == p, process_tuple)...)
        end
    end
    model_contents["tuple"]["trans_tuple"] = trans_tuple
end

function create_res_eq_tuple(model_contents, input_data)
    res_eq_tuple = []
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    res_typ = collect(keys(input_data["reserve_type"]))
    for n in res_nodes_tuple, r in res_typ, s in scenarios, t in temporals
        push!(res_eq_tuple, (n, r, s, t))
    end
    model_contents["tuple"]["res_eq_tuple"] = res_eq_tuple
end

function create_res_eq_updn_tuple(model_contents, input_data)
    res_eq_updn_tuple = []
    markets = input_data["markets"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    for m in keys(markets), s in scenarios, t in temporals
        if markets[m].direction == "up_down"
            push!(res_eq_updn_tuple, (m, s, t))
        end
    end
    model_contents["tuple"]["res_eq_updn_tuple"] = res_eq_updn_tuple
end

function create_res_final_tuple(model_contents, input_data)
    res_final_tuple = []
    markets = input_data["markets"]
    scenarios = collect(keys(input_data["scenarios"]))
    temporals = input_data["temporals"]
    for m in keys(markets)
        if markets[m].type == "reserve"
            for s in scenarios, t in temporals
                push!(res_final_tuple, (m, s, t))
            end
        end
    end
    model_contents["tuple"]["res_final_tuple"] = res_final_tuple
end

function create_fixed_value_tuple(model_contents, input_data)
    fixed_value_tuple = []
    markets = input_data["markets"]
    scenarios = collect(keys(input_data["scenarios"]))
    for m in keys(markets)
        if !isempty(markets[m].fixed) && markets[m].type == "energy"
            temps = map(x->x[1],markets[m].fixed)
            for s in scenarios, t in temps
                push!(fixed_value_tuple, (m, s, t))
            end
        end
    end
    model_contents["tuple"]["fixed_value_tuple"] = fixed_value_tuple
end

function create_ramp_tuple(model_contents, input_data)
    ramp_tuple = []
    processes = input_data["processes"]
    temporals = input_data["temporals"]
    for tup in model_contents["tuple"]["process_tuple"]
        if processes[tup[1]].conversion == 1 && !processes[tup[1]].is_cf
            if tup[5] != temporals[1]
                push!(ramp_tuple,tup)
            end
        end
    end
    model_contents["tuple"]["ramp_tuple"] = ramp_tuple
end