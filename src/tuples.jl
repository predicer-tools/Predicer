using DataStructures
using TimeZones


"""
    create_tuples(input_data::InputData)

Create all tuples used in the model, and save them in the tuplebook dict.

# Arguments
- `input_data::InputData`: Struct containing data used to build the model. 
"""
function create_tuples(input_data::InputData) # unused, should be debricated
    tuplebook = OrderedDict()
    tuplebook["res_nodes_tuple"] = reserve_nodes(input_data)
    tuplebook["res_tuple"] = reserve_market_directional_tuples(input_data)
    tuplebook["process_tuple"] = process_topology_tuples(input_data)
    tuplebook["proc_online_tuple"] = online_process_tuples(input_data)
    tuplebook["reserve_groups"] =  reserve_groups(input_data)
    tuplebook["res_potential_tuple"] = reserve_process_tuples(input_data)
    tuplebook["nodegroup_reserves"] = nodegroup_reserves(input_data)
    tuplebook["node_reserves"] = node_reserves(input_data)
    tuplebook["res_pot_prod_tuple"] = producer_reserve_process_tuples(input_data)
    tuplebook["res_pot_cons_tuple"] = consumer_reserve_process_tuples(input_data)
    tuplebook["node_state_tuple"] = state_node_tuples(input_data)
    tuplebook["node_balance_tuple"] = balance_node_tuples(input_data)
    tuplebook["proc_balance_tuple"] = balance_process_tuples(input_data)
    tuplebook["proc_op_balance_tuple"] = operative_slot_process_tuples(input_data)
    tuplebook["proc_op_tuple"] = piecewise_efficiency_process_tuples(input_data)
    tuplebook["cf_balance_tuple"] = cf_process_topology_tuples(input_data)
    tuplebook["lim_tuple"] = fixed_limit_process_topology_tuples(input_data)
    tuplebook["trans_tuple"] = transport_process_topology_tuples(input_data)
    tuplebook["res_eq_tuple"] = reserve_nodegroup_tuples(input_data)
    tuplebook["res_eq_updn_tuple"] = up_down_reserve_market_tuples(input_data)
    tuplebook["res_final_tuple"] = reserve_market_tuples(input_data)
    tuplebook["fixed_value_tuple"] = fixed_market_tuples(input_data)
    tuplebook["ramp_tuple"] = process_topology_ramp_times_tuples(input_data)
    tuplebook["risk_tuple"] = scenarios(input_data)
    tuplebook["balance_market_tuple"] = create_balance_market_tuple(input_data)
    tuplebook["market_tuple"] = create_market_tuple(input_data)
    tuplebook["state_reserves"] = state_reserves(input_data)
    tuplebook["reserve_limits"] = create_reserve_limits(input_data)
    tuplebook["setpoint_tuples"] = setpoint_tuples(input_data)
    tuplebook["block_tuples"] = block_tuples(input_data)
    tuplebook["group_tuples"] = create_group_tuples(input_data)
    tuplebook["node_diffusion_tuple"] = node_diffusion_tuple(input_data)
    tuplebook["diffusion_nodes"] = diffusion_nodes(input_data)
    tuplebook["node_delay_tuple"] = node_delay_tuple(input_data)

    
    return tuplebook
end


"""
    reserve_nodes(input_data::InputData)

Return nodes which have a reserve. Form: (n).
"""
function reserve_nodes(input_data::InputData) # original name: create_res_nodes_tuple()
    reserve_nodes = String[]
    if input_data.setup.contains_reserves
        markets = input_data.markets
        for m in collect(keys(markets))
            if markets[m].type == "reserve"
                for n in unique(map(y -> y[3], filter(x -> x[2] == markets[m].node, create_group_tuples(input_data))))
                    if input_data.nodes[n].is_res
                        push!(reserve_nodes, n)
                    end
                end
            end
        end
    end
    return unique(reserve_nodes)
end


"""
    reserve_market_directional_tuples(input_data::InputData)

Return tuples identifying each reserve market with its node and directions in each time step and scenario. Form: (r, ng, d, s, t).

!!! note
    This function assumes that reserve markets' market type is formatted "reserve" and that the up and down reserve market directions are "res_up" and "res_down".
"""
function reserve_market_directional_tuples(input_data::InputData) # original name: create_res_tuple()
    if !input_data.setup.contains_reserves
        return NTuple{5, String}[]
    else
        reserve_market_directional_tuples = NTuple{5, String}[]
        markets = input_data.markets
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        input_data_dirs = unique(map(m -> m.direction, collect(values(input_data.markets))))
        res_dir = []
        for d in input_data_dirs
            if d == "up" || d == "res_up"
                push!(res_dir, "res_up")
            elseif d == "dw" || d == "res_dw" || d == "dn" || d == "res_dn" || d == "down" || d == "res_down"
                push!(res_dir, "res_down")
            elseif d == "up/down" || d == "up/dw" || d == "up/dn" ||d == "up_down" || d == "up_dw" || d == "up_dn"
                push!(res_dir, "res_up")
                push!(res_dir, "res_down")
            elseif d != "none"
                msg = "Invalid reserve direction given: " * d
                throw(ErrorException(msg))
            end
        end
        unique!(res_dir)
        for m in values(markets)
            if m.type == "reserve"
                if m.direction in res_dir
                    for s in scenarios, t in temporals.t
                        push!(reserve_market_directional_tuples, (m.name, m.node, m.direction, s, t))
                    end
                else
                    for d in res_dir, s in scenarios, t in temporals.t
                        push!(reserve_market_directional_tuples, (m.name, m.node, d, s, t))
                    end
                end
            end
        end
        return reserve_market_directional_tuples
    end
end


"""
    process_topology_tuples(input_data::InputData)

Return tuples identifying each process topology (flow) for each time step and scenario. Form: (p, so, si, s, t).
"""
function process_topology_tuples(input_data::InputData) # original name: create_process_tuple()
    process_topology_tuples = NTuple{5, String}[]
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for p in values(processes)
        for s in scenarios
            for topo in p.topos
                for t in temporals.t
                    push!(process_topology_tuples, (p.name, topo.source, topo.sink, s, t))
                end
            end
        end
    end
    return process_topology_tuples
end


"""
    previous_process_topology_tuples(input_data::InputData)

Return dict of tuples containing the previous process tuple, used in building ramp constraints.
"""
function previous_process_topology_tuples(input_data::InputData)
    pptt = OrderedDict()
    process_tuples = process_topology_tuples(input_data)
    temporals = input_data.temporals.t

    for (i, tup) in enumerate(process_tuples)
        if tup[5] != temporals[1]
            pptt[tup] = process_tuples[i-1]
        end
    end
    return pptt
end


"""
    online_process_tuples(input_data::InputData)

Return tuples for each process with online variables for every time step and scenario. Form: (p, s, t).
"""
function online_process_tuples(input_data::InputData) # original name: create_proc_online_tuple()
    if !input_data.setup.contains_online
        return NTuple{3, String}[]
    else
        online_process_tuples = NTuple{3, String}[]
        processes = input_data.processes
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        for p in values(processes)
            if p.is_online
                for s in scenarios, t in temporals.t
                    push!(online_process_tuples, (p.name, s, t))
                end
            end
        end
        return online_process_tuples
    end
end

"""
    function reserve_groups(input_data::InputData)

Build tuples containing the mapping of processes - nodes over each reserve. Form: (dir, res_type, reserve, node, process)
"""
function reserve_groups(input_data::InputData)
    if !input_data.setup.contains_reserves
        return NTuple{5, String}[]
    else
        markets = input_data.markets
        groups = input_data.groups
        reserve_groups = NTuple{5, String}[]
        for m in collect(keys(markets))
            if markets[m].type == "reserve"
                d = markets[m].direction
                for p in groups[markets[m].processgroup].members, n in groups[markets[m].node].members
                    if d == "up/down" || d == "up/dw" || d == "up/dn" ||d == "up_down" || d == "up_dw" || d == "up_dn"
                        push!(reserve_groups, ("res_up", markets[m].reserve_type, m, n, p))
                        push!(reserve_groups, ("res_down", markets[m].reserve_type, m, n, p))
                    elseif d == "dw" || d == "res_dw" || d == "dn" || d == "res_dn" || d == "down" || d == "res_down"
                        push!(reserve_groups, ("res_down", markets[m].reserve_type, m, n, p))
                    elseif d == "up" || d == "res_up"
                        push!(reserve_groups, ("res_up", markets[m].reserve_type, m, n, p))
                    end
                end
            end
        end
        return reserve_groups
    end
end




"""
    nodegroup_reserves(input_data::InputData)

Return tuples for each nodegroup, scenario and timestep'. Form: (ng, s, t).
"""
function nodegroup_reserves(input_data::InputData)
    if !input_data.setup.contains_reserves
        return NTuple{3, String}[]
    else
        res_nodegroups = NTuple{3, String}[]
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        markets = input_data.markets
        for res_m in unique(map(x -> x[3], reserve_groups(input_data)))
            for s in scenarios, t in temporals.t
                push!(res_nodegroups, (markets[res_m].node, s, t))
            end
        end
        return unique(res_nodegroups)
    end
end

"""
    node_reserves(input_data::InputData)

Return tuples for each node, scenario and timestep'. Form: (n, s, t).
"""
function node_reserves(input_data::InputData)
    if !input_data.setup.contains_reserves
        return NTuple{3, String}[]
    else
        res_nodes = NTuple{3, String}[]
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        for n in reserve_nodes(input_data)
            for s in scenarios, t in temporals.t
                push!(res_nodes, (n, s, t))
            end
        end
        return unique(res_nodes)
    end
end


"""
    producer_reserve_process_tuples(input_data::InputData)

Return tuples containing information on 'producer' process topologies with reserve potential for every time step and scenario. Form: (d, rt, p, so, si, s, t).
"""
function producer_reserve_process_tuples(input_data::InputData) # original name: create_res_pot_prod_tuple()
    if !input_data.setup.contains_reserves
        return NTuple{7, String}[]
    else
        res_nodes = reserve_nodes(input_data)
        res_process_tuples = reserve_process_tuples(input_data)
        producer_reserve_process_tuples = filter(x -> x[5] in res_nodes, res_process_tuples)
        return producer_reserve_process_tuples
    end
end


"""
    consumer_reserve_process_tuples(input_data::InputData)

Return tuples containing information on 'consumer' process topologies with reserve potential for every time step and scenario. Form: (d, rt, p, so, si, s, t).
"""
function consumer_reserve_process_tuples(input_data::InputData) # original name: create_res_pot_cons_tuple()
    if !input_data.setup.contains_reserves
        return NTuple{7, String}[]
    else
        res_nodes = reserve_nodes(input_data)
        res_process_tuples = reserve_process_tuples(input_data)
        consumer_reserve_process_tuples = filter(x -> x[4] in res_nodes, res_process_tuples)
        return consumer_reserve_process_tuples
    end
end


"""
    reserve_process_tuples(input_data::InputData)

Return tuples containing information on process topologies with reserve potential for every time step and scenario. Form: (d, rt, p, so, si, s, t).

!!! note 
    This function assumes that the up and down reserve market directions are "res_up" and "res_down".
"""
function reserve_process_tuples(input_data::InputData) # original name: create_res_potential_tuple(), duplicate existed: create_proc_potential_tuple()
    if !input_data.setup.contains_reserves
        return NTuple{7, String}[]
    else
        reserve_process_tuples = NTuple{7, String}[]
        processes = input_data.processes
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        res_groups = reserve_groups(input_data)
        for p in collect(keys(processes))
            if processes[p].is_res
                res_cons = filter(x -> x[5] == p, res_groups)
                for rc in res_cons
                    for topo in processes[p].topos
                        if (topo.source == rc[4]|| topo.sink == rc[4])
                            for s in scenarios, t in temporals.t
                                push!(reserve_process_tuples, (rc[1], rc[2], p, topo.source, topo.sink, s, t))
                            end
                        end
                    end
                end
            end
        end
        return unique(reserve_process_tuples)
    end
end


"""
    state_node_tuples(input_data::InputData)

Return tuples for each node with a state (storage) for every time step and scenario. Form: (n, s, t).
"""
function state_node_tuples(input_data::InputData) # original name: create_node_state_tuple()
    state_node_tuples = NTuple{3, String}[]
    if input_data.setup.contains_states
        nodes = input_data.nodes
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        for n in values(nodes)
            if n.is_state
                for s in scenarios, t in temporals.t
                    push!(state_node_tuples, (n.name, s, t))
                end
            end
        end
    end
    return state_node_tuples
end


"""
    balance_node_tuples(input_data::InputData)

Return tuples for each node over which balance should be maintained for every time step and scenario. Form: (n s, t).
"""
function balance_node_tuples(input_data::InputData) # original name: create_node_balance_tuple()
    balance_node_tuples = NTuple{3, String}[]
    nodes = input_data.nodes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for n in values(nodes)
        if !(n.is_commodity) & !(n.is_market)
            for s in scenarios, t in temporals.t
                push!(balance_node_tuples, (n.name, s, t))
            end
        end
    end
    return balance_node_tuples
end

"""
    previous_balance_node_tuples(input_data::InputData)

Function to gather the node balance tuple for the previous timestep. Returns a Dict() with the node_bal_tup as key and the previous tup as value. 
"""
function previous_balance_node_tuples(input_data::InputData)
    pbnt = OrderedDict()
    node_bal_tups = balance_node_tuples(input_data)
    for (i, n) in enumerate(node_bal_tups)
        if n[3] != input_data.temporals.t[1]
            pbnt[n] = node_bal_tups[i-1]
        end
    end
    return pbnt
end

"""
    balance_process_tuples(input_data::InputData)

Return tuples for each process over which balance is to be maintained for every time step and scenario. Form: (p, s, t).
"""
function balance_process_tuples(input_data::InputData) # orignal name: create_proc_balance_tuple()
    balance_process_tuples = NTuple{3, String}[]
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for p in values(processes)
        if p.conversion == 1 && !p.is_cf
            if isempty(p.eff_fun)
                for s in scenarios, t in temporals.t
                    push!(balance_process_tuples, (p.name, s, t))
                end
            end
        end
    end
    return balance_process_tuples
end


"""
    operative_slot_process_tuples(input_data::InputData)

Return tuples identifying processes with piecewise efficiency for each of their operative slots (o), and every time step and scenario. Form: (p, s, t, o).
"""
function operative_slot_process_tuples(input_data::InputData) # original name: create_proc_op_balance_tuple()
    if !input_data.setup.contains_piecewise_eff
        return NTuple{4, String}[]
    else
        operative_slot_process_tuples = NTuple{4, String}[]
        processes = input_data.processes
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        for p in values(processes)
            if p.conversion == 1 && !p.is_cf
                if !isempty(p.eff_fun)
                    for s in scenarios, t in temporals.t, o in p.eff_ops
                        push!(operative_slot_process_tuples, (p.name, s, t, o))
                    end
                end
            end
        end
        return operative_slot_process_tuples
    end
end


"""
    piecewise_efficiency_process_tuples(input_data::InputData)

Return tuples identifying processes with piecewise efficiency for each time step and scenario. Form: (p, s, t).
"""
function piecewise_efficiency_process_tuples(input_data::InputData) # original name: create_proc_op_tuple()
    if !input_data.setup.contains_piecewise_eff
        return NTuple{3, String}[]
    else
        piecewise_efficiency_process_tuples = NTuple{3, String}[]
        processes = input_data.processes
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        for p in values(processes)
            if p.conversion == 1 && !p.is_cf
                if !isempty(p.eff_fun)
                    for s in scenarios, t in temporals.t
                        push!(piecewise_efficiency_process_tuples, (p.name, s, t))
                    end
                end
            end
        end
        return piecewise_efficiency_process_tuples
    end
end


"""
    cf_process_topology_tuples(input_data::InputData)

Return tuples identifying process topologies with a capacity factor for every time step and scenario. Form: (p, so, si, s, t).
"""
function cf_process_topology_tuples(input_data::InputData) # original name: create_cf_balance_tuple()
    cf_process_topology_tuples = NTuple{5, String}[]
    processes = input_data.processes
    process_tuples = process_topology_tuples(input_data)
    for p in values(processes)
        if p.is_cf
            push!(cf_process_topology_tuples, filter(x -> (x[1] == p.name), process_tuples)...)
        end
    end
    return cf_process_topology_tuples
end

"""
    fixed_limit_process_topology_tuples(input_data::InputData)

Return tuples containing information on process topologies with fixed limit on flow capacity. Form: (p, so, si, s, t).
"""
function fixed_limit_process_topology_tuples( input_data::InputData) # original name: create_lim_tuple()
    fixed_limit_process_topology_tuples = NTuple{5, String}[]
    processes = input_data.processes
    process_tuples = process_topology_tuples(input_data)
    res_nodes = reserve_nodes(input_data)
    for p in values(processes)
        if !p.is_cf && (p.conversion == 1)
            push!(fixed_limit_process_topology_tuples, filter(x -> x[1] == p.name, process_tuples)...)
        end
    end
    return fixed_limit_process_topology_tuples
end


"""
    transport_process_topology_tuples(input_data::InputData)

Return tuples identifying transport process topologies for each time step and scenario. Form: (p, so, si, s, t).
"""
function transport_process_topology_tuples(input_data::InputData) # original name. create_trans_tuple()
    transport_process_topology_tuples = NTuple{5, String}[]
    processes = input_data.processes
    process_tuples = process_topology_tuples(input_data)
    for p in values(processes)
        if !p.is_cf && p.conversion == 2
            push!(transport_process_topology_tuples, filter(x -> x[1] == p.name, process_tuples)...)
        end
    end
    return transport_process_topology_tuples
end


"""
    reserve_nodegroup_tuples(input_data::InputData)

Return tuples for each nodegroup with reserves for each relevant reserve type, all time steps and scenarios. Form: (ng, rt, s, t).
"""
function reserve_nodegroup_tuples(input_data::InputData) # original name: create_res_eq_tuple()
    if !input_data.setup.contains_reserves
        return NTuple{4, String}[]
    else
        reserve_node_tuples = NTuple{4, String}[]
        res_nodegroup = nodegroup_reserves(input_data)
        res_typ = collect(keys(input_data.reserve_type))
        for ng_tup in res_nodegroup, rt in res_typ
            push!(reserve_node_tuples, (ng_tup[1], rt, ng_tup[2], ng_tup[3]))
        end
        return reserve_node_tuples
    end
end


"""
    up_down_reserve_market_tuples(input_data::InputData)

Return tuples for each reserve market with an 'up_down' direction for all time steps and scenarios. Form: (r, s, t).

!!! note
    This function assumes that reserve markets with up and down reserve have market direction "up_down".
"""
function up_down_reserve_market_tuples(input_data::InputData) # original name: create_res_eq_updn_tuple()
    if !input_data.setup.contains_reserves
        return NTuple{3, String}[]
    else
        up_down_reserve_market_tuples = NTuple{3, String}[]
        markets = input_data.markets
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        res_ms = unique(map(x -> x[1], reserve_market_tuples(input_data)))
        for rm in res_ms
            d = markets[rm].direction
            if d == "up/down" || d == "up/dw" || d == "up/dn" ||d == "up_down" || d == "up_dw" || d == "up_dn"
                for s in scenarios, t in temporals.t
                    push!(up_down_reserve_market_tuples, (rm, s, t))
                end
            end 
        end
        return up_down_reserve_market_tuples
    end
end


"""
    reserve_market_tuples(input_data::InputData)

Return tuples for each reserve market for every time step and scenario. Form: (r, s, t).

!!! note
    This function assumes that reserve markets' market type is formatted "reserve".
"""
function reserve_market_tuples(input_data::InputData) # orignal name: create_res_final_tuple()
    if !input_data.setup.contains_reserves
        return NTuple{3, String}[]
    else
        reserve_market_tuples = NTuple{3, String}[]
        markets = input_data.markets
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        for m in values(markets)
            if m.type == "reserve"
                for s in scenarios, t in temporals.t
                    push!(reserve_market_tuples, (m.name, s, t))
                end
            end
        end
        return reserve_market_tuples
    end
end


"""
    fixed_market_tuples(input_data::InputData)

Return tuples containing time steps for energy markets when the market state is fixed in each scenario. Form: (m, s, t).

!!! note
    This function assumes that energy markets' market type is formatted "energy".
"""
function fixed_market_tuples(input_data::InputData) # original name: create_fixed_value_tuple()
    fixed_market_tuples = NTuple{3, String}[]
    markets = input_data.markets
    scenarios = collect(keys(input_data.scenarios))
    for m in values(markets)
        if !isempty(m.fixed) && m.type == "energy"
            temps = map(x->x[1], m.fixed)
            for s in scenarios, t in temps
                push!(fixed_market_tuples, (m.name, s, t))
            end
        end
    end
    return fixed_market_tuples
end


"""
    process_topology_ramp_times_tuples(input_data::InputData)

Return tuples containing time steps with ramp possibility for each process topology and scenario. Form: (p, so, si, s, t).
"""
function process_topology_ramp_times_tuples(input_data::InputData) # orignal name: create_ramp_tuple()
    ramp_times_process_topology_tuple = NTuple{5, String}[]
    processes = input_data.processes
    process_tuples = process_topology_tuples(input_data)
    for (name, source, sink, s, t) in process_tuples
        if processes[name].conversion == 1 && !processes[name].is_cf
            push!(ramp_times_process_topology_tuple, (name, source, sink, s, t))
        end
    end
    return ramp_times_process_topology_tuple
end

"""
    scenarios(input_data::InputData)

Return scenarios. Form: (s).
"""
function scenarios(input_data::InputData) # original name: create_risk_tuple()
    scenarios = collect(keys(input_data.scenarios))
    return scenarios
end

""" 
    create_balance_market_tuple((input_data::Predicer.InputData)

Returns array of tuples containing balance market. Form: (m, dir, s, t).
"""
function create_balance_market_tuple(input_data::Predicer.InputData)
    bal_tuples = NTuple{4, String}[]
    markets = input_data.markets
    dir = ["up","dw"]
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for m in keys(markets)
        if markets[m].type == "energy" && markets[m].is_bid == true
            for d in dir, s in scenarios, t in temporals.t
                push!(bal_tuples, (markets[m].name, d, s, t))
            end
        end
    end
    return bal_tuples
end


"""
    create_market_tuple(input_data::Predicer.InputData)

Returns array containing information on the defined markets. Form (market, type, node/nodegroup, processgroup)
"""
function create_market_tuple(input_data::Predicer.InputData)
    mnt = []
    for k in collect(keys(input_data.markets))
        m = input_data.markets[k]
        push!(mnt, (k, m.type, m.node, m.processgroup))
    end
    return mnt
end


"""
    state_reserves(input_data::InputData)

Returns reserve potentials of processes connected to states with a reserve.
form: (sto_node, res_dir, res_type, p, so, si, s, t)
"""
function state_reserves(input_data::InputData)
    state_reserves = NTuple{8, String}[]
    if input_data.setup.contains_reserves && input_data.setup.contains_states
        processes = input_data.processes
        nodes = input_data.nodes
        res_nodes_tuple = reserve_nodes(input_data)
        res_potential_tuple = reserve_process_tuples(input_data)
        process_tuple = process_topology_tuples(input_data)
        for n in res_nodes_tuple
            res_node_in_processes = unique(map(x -> (x[3], x[4], x[5]), filter(tup -> tup[5] == n, res_potential_tuple)))
            res_node_out_processes = unique(map(x -> (x[3], x[4], x[5]), filter(tup -> tup[4] == n, res_potential_tuple)))
            for p_in in res_node_in_processes, p_out in res_node_out_processes
                # Get topos for p_in and p_out. Create tuple from the values
                p_in_topos = map(topo -> (p_in[1], topo.source, topo.sink), processes[p_in[1]].topos)
                p_out_topos = map(topo -> (p_out[1], topo.source, topo.sink), processes[p_out[1]].topos)

                # Get the TOPOS not going into the reserve node
                not_res_topos_p_in = filter(x -> !(x in res_node_in_processes), p_in_topos)
                not_res_topos_p_out = filter(x -> !(x in res_node_out_processes), p_out_topos)

                # The length of these topos should be 1.
                if length(not_res_topos_p_in)==1 && length(not_res_topos_p_out)==1
                    # Check that one of their source/sink is the same. 
                    if (not_res_topos_p_in[1][2] == not_res_topos_p_out[1][3])
                        s_node = not_res_topos_p_in[1][2]
                        if nodes[s_node].is_state
                            s_node_ps = unique(map(x -> x[1], filter(tup -> (tup[3] == s_node || tup[2] == s_node), process_tuple)))
                            if length(s_node_ps) == 2# if extra node only has 2 processes
                                append!(state_reserves, map(x -> (s_node, x...), filter(tup -> tup[3] == p_in[1], res_potential_tuple)))
                                append!(state_reserves, map(x -> (s_node, x...), filter(tup -> tup[3] == p_out[1], res_potential_tuple)))
                            end
                        end
                    end
                end
            end
        end
    end

    return state_reserves
end

"""
    create_reserve_limits(input_data::InputData)

Returns limited reserve markets.
form: (market, s, t)
"""
function create_reserve_limits(input_data::InputData)
    reserve_limits = NTuple{3, String}[]
    if input_data.setup.contains_reserves
        markets = input_data.markets
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        for m in keys(markets)
            if markets[m].type == "reserve" && markets[m].is_limited
                for s in scenarios, t in temporals.t
                    push!(reserve_limits,(markets[m].name,s,t))
                end
            end
        end
    end
    return reserve_limits
end

"""
    setpoint_tuples(input_data::InputData)

Function to create tuples for general constraints with setpoints. Form (c, s, t), where
c is the name of the general constraint. 
"""
function setpoint_tuples(input_data::InputData)
    setpoint_tuples = NTuple{3, String}[]
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals.t
    for c in collect(keys(input_data.gen_constraints))
        if input_data.gen_constraints[c].is_setpoint
            for s in scenarios, t in temporals
                push!(setpoint_tuples, (c, s, t))
            end
        end
    end
    return setpoint_tuples
end

"""
    block_tuples(input_data::InputData)

Function to create tuples for inflow blocks. Form (blockname, node, s, t).
"""
function block_tuples(input_data::InputData)
    blocks = input_data.inflow_blocks
    block_tuples = NTuple{4, String}[]
    for b in collect(keys(blocks))
        for t_series in blocks[b].data.ts_data
            for t in t_series.series
                push!(block_tuples, (b, blocks[b].node, t_series.scenario, t[1]))
            end
        end
    end
    return block_tuples
end


"""
    create_group_tuples(input_data::InputData)

Function to create tuples for groups and their members. Form (group_type, groupname, member_name)
"""
function create_group_tuples(input_data::InputData)
    groups = input_data.groups
    group_tuples = NTuple{3, String}[]
    for gn in collect(keys(groups))
        for gm in groups[gn].members
            push!(group_tuples, (groups[gn].type, gn, gm))
        end
    end
    return group_tuples
end

"""
    node_diffusion_tuple(input_data::InputData)

Function to create tuples for "source" nodes with a diffusion functionality. Form (n, s, t)
"""

function node_diffusion_tuple(input_data::InputData)
    node_diffusion_tup = NTuple{3, String}[]
    if input_data.setup.contains_diffusion
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals.t
        nodes = diffusion_nodes(input_data)
        for n in nodes, s in scenarios, t in temporals
            push!(node_diffusion_tup, (n, s, t))
        end
    end
    return node_diffusion_tup
end


"""
    node_delay_tuple(input_data::InputData) 

Function to create tuples for node delay functionality. Form (node1, node2, scenario, t_at_node1, t_at_node2)
"""
function node_delay_tuple(input_data::InputData)
    node_delay_tup = NTuple{5, String}[]
    if input_data.setup.contains_delay && !input_data.temporals.is_variable_dt # ensure the dt length is constant. Need to change in the future if it isn't...
        for tup in input_data.node_delay
            n1 = tup[1]
            n2 = tup[2]
            delay = tup[3]
            l_t = length(input_data.temporals.t)
            for (i, t) in enumerate(input_data.temporals.t[begin:end])
                if (l_t - i) <= delay
                    t2 = ZonedDateTime(t, input_data.temporals.ts_format) +  TimeZones.Hour(delay) * input_data.temporals.dtf
                else
                    t2 = input_data.temporals.t[i+delay]
                end
                for s in scenarios(input_data)
                    push!(node_delay_tup, (n1, n2, s, string(t), string(t2)))
                end
            end
        end
    end
    return node_delay_tup
end


"""
    diffusion_nodes(input_data::InputData)

Function to obtain the nodes that are part of a diffusion relation. form (n)
"""
function diffusion_nodes(input_data::InputData)
    if input_data.setup.contains_diffusion
        return unique(vcat(map(x -> x[1], input_data.node_diffusion), map(x -> x[2], input_data.node_diffusion)))
    else
        return String[]
    end
end