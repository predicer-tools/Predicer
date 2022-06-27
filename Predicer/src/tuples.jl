using DataStructures

"""
    create_tuples(model_contents::OrderedDict, input_data::InputData)

Create all tuples used in the model, and save them in the model_contents dict.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::InputData`: Struct containing data used to build the model. 
"""
function create_tuples(model_contents::OrderedDict, input_data::InputData)
    create_res_nodes_tuple(model_contents, input_data)
    create_res_tuple(model_contents, input_data)
    create_process_tuple(model_contents, input_data)
    create_res_potential_tuple(model_contents, input_data)
    create_proc_online_tuple(model_contents, input_data)
    create_res_pot_prod_tuple(model_contents)
    create_res_pot_cons_tuple(model_contents)
    create_node_state_tuple(model_contents, input_data)
    create_node_balance_tuple(model_contents, input_data)
    create_proc_potential_tuple(model_contents, input_data)
    create_proc_balance_tuple(model_contents, input_data)
    create_proc_op_balance_tuple(model_contents, input_data)
    create_proc_op_tuple(model_contents)
    create_cf_balance_tuple(model_contents, input_data)
    create_lim_tuple(model_contents, input_data)
    create_trans_tuple(model_contents, input_data)
    create_res_eq_tuple(model_contents, input_data)
    create_res_eq_updn_tuple(model_contents, input_data)
    create_res_final_tuple(model_contents, input_data)
    create_fixed_value_tuple(model_contents, input_data)
    create_ramp_tuple(model_contents, input_data)
    create_risk_tuple(model_contents, input_data)
end


"""
    create_res_nodes_tuple(model_contents::OrderedDict, input_data::InputData)

Creates the tuple containing all the nodes which have a reserve. Form: (node).
"""
function create_res_nodes_tuple(model_contents::OrderedDict, input_data::InputData)
    reserve_nodes = []

    for n in values(input_data.nodes)
        if n.is_res
            push!(reserve_nodes, n.name)
        end
    end
    model_contents["tuple"]["res_nodes_tuple"] = reserve_nodes
end



"""
    create_res_tuple(model_contents::OrderedDict, input_data::InputData)

Creates the reserve tuple. Form: (res, n, rd, s, t).
"""
function create_res_tuple(model_contents::OrderedDict, input_data::InputData)
    res_tuple = []
    markets = input_data.markets
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    res_dir = model_contents["res_dir"]
    for m in values(markets)
        if m.type == "reserve"
            if m.direction in res_dir
                for s in scenarios, t in temporals.t
                    push!(reserve_market_tuple, (m.name, m.node, m.direction, s, t))
                end
            else
                for d in res_dir, s in scenarios, t in temporals.t
                    push!(reserve_market_tuple, (m.name, m.node, d, s, t))
                end
            end
        end
    end
    model_contents["tuple"]["res_tuple"] = res_tuple
end


"""
    create_process_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing process topology for each timestep. Form: (p, so, si, s, t).
"""
function create_process_tuple(model_contents::OrderedDict, input_data::InputData)
    process_tuple = []
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for p in values(processes), s in scenarios
        for topo in p.topos
            for t in temporals.t
                push!(process_tuple, (p.name, topo.source, topo.sink, s, t))
            end
        end
    end
    model_contents["tuple"]["process_tuple"] = process_tuple
end


"""
    create_proc_online_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing processes with online variables for each timestep. Form: (p, s, t).
"""
function create_proc_online_tuple(model_contents::OrderedDict, input_data::InputData)
    proc_online_tuple = []
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for p in values(processes)
        if p.is_online
            for s in scenarios, t in temporals.t
                push!(proc_online_tuple, (p.name, s, t))
            end
        end
    end
    model_contents["tuple"]["proc_online_tuple"] = proc_online_tuple
end


"""
    create_res_pot_prod_tuple(model_contents::OrderedDict)

Creates tuple containing information on potential reserve participation per unit for each timestep. Form: (rd, rt, p, so, si, s, t).
"""
function create_res_pot_prod_tuple(model_contents::OrderedDict)
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    res_potential_tuple = model_contents["tuple"]["res_potential_tuple"]
    res_pot_prod_tuple = filter(x -> x[5] in res_nodes_tuple, res_potential_tuple)
    model_contents["tuple"]["res_pot_prod_tuple"] = res_pot_prod_tuple
end


"""
    create_res_pot_cons_tuple(model_contents::OrderedDict)

Creates tuple containing information on potential reserve participation per unit for each timestep. Form: (rd, rt, p, so, si, s, t).
"""
function create_res_pot_cons_tuple(model_contents::OrderedDict)
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    res_potential_tuple = model_contents["tuple"]["res_potential_tuple"]
    res_pot_cons_tuple = filter(x -> x[4] in res_nodes_tuple, res_potential_tuple)
    model_contents["tuple"]["res_pot_cons_tuple"] = res_pot_cons_tuple
end


"""
    create_node_state_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing each node with a state (storage) for each timestep. Form: (n, s, t).
"""
function create_node_state_tuple(model_contents::OrderedDict, input_data::InputData)
    node_state_tuple = []
    nodes = input_data.nodes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for n in values(nodes)
        if !(n.is_commodity) & !(n.is_market) & n.is_state
            for s in scenarios, t in temporals.t
                push!(node_state_tuple, (n.name, s, t))
            end
        end
    end
    model_contents["tuple"]["node_state_tuple"] = node_state_tuple
end


"""
    create_node_balance_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing nodes over which balance should be calculated. Form: (n s, t).
"""
function create_node_balance_tuple(model_contents::OrderedDict, input_data::InputData)
    node_balance_tuple = []
    nodes = input_data.nodes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for n in values(nodes)
        if !(n.is_commodity) & !(n.is_market)
            for s in scenarios, t in temporals.t
                push!(node_balance_tuple, (n.name, s, t))
            end
        end
    end
    model_contents["tuple"]["node_balance_tuple"] = node_balance_tuple
end


"""
    create_res_potential_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing information on reserve participation in each timestep. Form: (rd, rt, p, so, si, s, t).
"""
function create_res_potential_tuple(model_contents::OrderedDict, input_data::InputData)
    res_potential_tuple = []
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    res_type = collect(keys(input_data.reserve_type))
    res_dir = model_contents["res_dir"]

    for p in values(processes), s in scenarios, t in temporals.t
        for topo in p.topos
            if (topo.source in res_nodes_tuple|| topo.sink in res_nodes_tuple) && p.is_res
                for r in res_dir, rt in res_type
                    push!(res_potential_tuple, (r, rt, p.name, topo.source, topo.sink, s, t))
                end
            end
        end
    end
    model_contents["tuple"]["res_potential_tuple"] = res_potential_tuple
end


"""
    create_proc_potential_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing information on potential reserve participation per unit for each timestep. Form: (rd, rt, p, so, si, s, t).
"""
function create_proc_potential_tuple(model_contents::OrderedDict, input_data::InputData)
    res_potential_tuple = []
    res_dir = model_contents["res_dir"]
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    res_type = collect(keys(input_data.reserve_type))

    for p in values(processes), s in scenarios, t in temporals.t
        for topo in p.topos
            if (topo.source in res_nodes_tuple|| topo.sink in res_nodes_tuple) && p.is_res
                for r in res_dir, rt in res_type
                    push!(res_potential_tuple, (r, rt, p.name, topo.source, topo.sink, s, t))
                end
            end
        end
    end
    model_contents["tuple"]["res_potential_tuple"] = res_potential_tuple
end


"""
    create_proc_balance_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing all processes, over which balance is to be calculated, for each timestep. Form: (p, s, t).
"""
function create_proc_balance_tuple(model_contents::OrderedDict, input_data::InputData)
    proc_balance_tuple = []
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for p in values(processes)
        if p.conversion == 1 && !p.is_cf
            if isempty(p.eff_fun)
                for s in scenarios, t in temporals.t
                    push!(proc_balance_tuple, (p.name, s, t))
                end
            end
        end
    end
    model_contents["tuple"]["proc_balance_tuple"] = proc_balance_tuple
end


"""
    create_proc_op_balance_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing all processes with piecewise efficiency, for each timestep and each operating point. Form: (p, s, t, operating_point).
"""
function create_proc_op_balance_tuple(model_contents::OrderedDict, input_data::InputData)
    proc_op_balance_tuple = []
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for p in values(processes)
        if p.conversion == 1 && !p.is_cf
            if !isempty(p.eff_fun)
                for s in scenarios, t in temporals.t, o in p.eff_ops
                    push!(proc_op_balance_tuple, (p.name, s, t, o))
                end
            end
        end
    end
    model_contents["tuple"]["proc_op_balance_tuple"] = proc_op_balance_tuple
end


"""
    create_proc_op_tuple(model_contents::OrderedDict)

Creates tuple containing all processes with piecewise efficiency, for each timestep. Form: (p, s, t).
"""
function create_proc_op_tuple(model_contents::OrderedDict)
    proc_op_tuple = unique(map(x->(x[1],x[2],x[3]),model_contents["tuple"]["proc_op_balance_tuple"]))
    model_contents["tuple"]["proc_op_tuple"] = proc_op_tuple
end


"""
    create_cf_balance_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing information on processes with an capacity factor, for each timestep. Form: (p, so, si, s, t).
"""
function create_cf_balance_tuple(model_contents::OrderedDict, input_data::InputData)
    cf_balance_tuple = []
    processes = input_data.processes
    process_tuple = model_contents["tuple"]["process_tuple"]
    for p in values(processes)
        if p.is_cf
            push!(cf_balance_tuple, filter(x -> (x[1] == p.name), process_tuple)...)
        end
    end
    model_contents["tuple"]["cf_balance_tuple"] = cf_balance_tuple
end

"""
    create_lim_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple ?. Form: (p, so, si, s, t).
"""
function create_lim_tuple(model_contents::OrderedDict, input_data::InputData)
    lim_tuple = []
    processes = input_data.processes
    process_tuple = model_contents["tuple"]["process_tuple"]
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    for p in values(processes)
        if !p.is_cf && (p.conversion == 1)
            push!(lim_tuple, filter(x -> x[1] == p.name && (x[2] == p.name || x[2] in res_nodes_tuple), process_tuple)...)
        end
    end
    model_contents["tuple"]["lim_tuple"] = lim_tuple
end


"""
    create_trans_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing information on transport processes, for each timestep. Form: (p, so, si, s, t).
"""
function create_trans_tuple(model_contents::OrderedDict, input_data::InputData)
    trans_tuple = []
    processes = input_data.processes
    process_tuple = model_contents["tuple"]["process_tuple"]
    for p in values(processes)
        if !p.is_cf && p.conversion == 2
            push!(trans_tuple, filter(x -> x[1] == p.name, process_tuple)...)
        end
    end
    model_contents["tuple"]["trans_tuple"] = trans_tuple
end


"""
    create_res_eq_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple with each node with reserves, for relevant reserve type and each timestep. Form: (n, rt, s, t).
"""
function create_res_eq_tuple(model_contents::OrderedDict, input_data::InputData)
    res_eq_tuple = []
    res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    res_type = collect(keys(input_data.reserve_type))
    for n in res_nodes_tuple, r in res_type, s in scenarios, t in temporals.t
        push!(res_eq_tuple, (n, r, s, t))
    end
    model_contents["tuple"]["res_eq_tuple"] = res_eq_tuple
end


"""
    create_res_eq_updn_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing all (reserve) markets with an (up/down) direction. Form: (m, s, t).
"""
function create_res_eq_updn_tuple(model_contents::OrderedDict, input_data::InputData)
    res_eq_updn_tuple = []
    markets = input_data.markets
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for m in values(markets), s in scenarios, t in temporals.t
        if m.direction == "up_down"
            push!(res_eq_updn_tuple, (m.name, s, t))
        end
    end
    model_contents["tuple"]["res_eq_updn_tuple"] = res_eq_updn_tuple
end


"""
    create_res_final_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing all (reserve) markets for each timestep. Form: (m, s, t).
"""
function create_res_final_tuple(model_contents::OrderedDict, input_data::InputData)
    res_final_tuple = []
    markets = input_data.markets
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for m in values(markets)
        if m.type == "reserve"
            for s in scenarios, t in temporals.t
                push!(res_final_tuple, (m.name, s, t))
            end
        end
    end
    model_contents["tuple"]["res_final_tuple"] = res_final_tuple
end


"""
    create_fixed_value_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing timesteps containing fixed market states. Form: (m, s, t).
"""
function create_fixed_value_tuple(model_contents::OrderedDict, input_data::InputData)
    fixed_value_tuple = []
    markets = input_data.markets
    scenarios = collect(keys(input_data.scenarios))
    for m in values(markets)
        if !isempty(m.fixed) && m.type == "energy"
            temps = map(x->x[1], m.fixed)
            for s in scenarios, t in temps
                push!(fixed_value_tuple, (m.name, s, t))
            end
        end
    end
    model_contents["tuple"]["fixed_value_tuple"] = fixed_value_tuple
end


"""
    create_ramp_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing timesteps with ramp possibility. Form: (p, so, si, s, t).
"""
function create_ramp_tuple(model_contents::OrderedDict, input_data::InputData)
    ramp_tuple = []
    processes = input_data.processes
    temporals = input_data.temporals
    process_tuples = model_contents["tuple"]["process_tuple"]
    for (name, source, sink, s, t) in process_tuples
        if processes[name].conversion == 1 && !processes[name].is_cf
            if t != temporals.t[1]
                push!(ramp_tuple, (name, source, sink, s, t))
            end
        end
    end
    model_contents["tuple"]["ramp_tuple"] = ramp_tuple
end

"""
    create_risk_tuple(model_contents::OrderedDict, input_data::InputData)

Creates tuple containing scenarios for risk variable. Form: (s).
"""
function create_risk_tuple(model_contents::OrderedDict, input_data::InputData)
    scenarios = collect(keys(input_data.scenarios))
    risk_tuple = scenarios
    model_contents["tuple"]["risk_tuple"] = risk_tuple
end