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
    tuplebook["res_potential_tuple"] = reserve_process_tuples(input_data)
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
    tuplebook["res_eq_tuple"] = reserve_node_tuples(input_data)
    tuplebook["res_eq_updn_tuple"] = up_down_reserve_market_tuples(input_data)
    tuplebook["res_final_tuple"] = reserve_market_tuples(input_data)
    tuplebook["fixed_value_tuple"] = fixed_market_tuples(input_data)
    tuplebook["ramp_tuple"] = process_topology_ramp_times_tuples(input_data)
    tuplebook["risk_tuple"] = scenarios(input_data)
    tuplebook["delay_tuple"] = create_delay_process_tuple(input_data)
    tuplebook["balance_market_tuple"] = create_balance_market_tuple(input_data)
    tuplebook["state_reserves"] = state_reserves(input_data)
    tuplebook["reserve_limits"] = create_reserve_limits(input_data)
    tuplebook["setpoint_tuples"] = setpoint_tuples(input_data)
    tuplebook["block_tuples"] = block_tuples(input_data)
    return tuplebook
end


"""
    reserve_nodes(input_data::InputData)

Return nodes which have a reserve. Form: (n).
"""
function reserve_nodes(input_data::InputData) # original name: create_res_nodes_tuple()
    reserve_nodes = []

    for n in values(input_data.nodes)
        if n.is_res
            push!(reserve_nodes, n.name)
        end
    end
    return reserve_nodes
end



"""
    reserve_market_directional_tuples(input_data::InputData)

Return tuples identifying each reserve market with its node and directions in each time step and scenario. Form: (r, n, d, s, t).

!!! note
    This function assumes that reserve markets' market type is formatted "reserve" and that the up and down reserve market directions are "res_up" and "res_down".
"""
function reserve_market_directional_tuples(input_data::InputData) # original name: create_res_tuple()
    if !input_data.contains_reserves
        return []
    else
        reserve_market_directional_tuples = []
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
    process_topology_tuples = []
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for p in values(processes)
        if p.delay == 0
            for s in scenarios
                for topo in p.topos
                    for t in temporals.t
                        push!(process_topology_tuples, (p.name, topo.source, topo.sink, s, t))
                    end
                end
            end
        end
    end
    return process_topology_tuples
end


"""
    online_process_tuples(input_data::InputData)

Return tuples for each process with online variables for every time step and scenario. Form: (p, s, t).
"""
function online_process_tuples(input_data::InputData) # original name: create_proc_online_tuple()
    if !input_data.contains_online
        return []
    else
        online_process_tuples = []
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
    producer_reserve_process_tuples(input_data::InputData)

Return tuples containing information on 'producer' process topologies with reserve potential for every time step and scenario. Form: (d, rt, p, so, si, s, t).
"""
function producer_reserve_process_tuples(input_data::InputData) # original name: create_res_pot_prod_tuple()
    if !input_data.contains_reserves
        return []
    else
        res_nodes = reserve_nodes(input_data)
        res_process_tuples = reserve_process_tuples(input_data)
        # filter those processes that have a reserve node as a sink
        producer_reserve_process_tuples = filter(x -> x[5] in res_nodes, res_process_tuples)
        return producer_reserve_process_tuples
    end
end


"""
    consumer_reserve_process_tuples(input_data::InputData)

Return tuples containing information on 'consumer' process topologies with reserve potential for every time step and scenario. Form: (d, rt, p, so, si, s, t).
"""
function consumer_reserve_process_tuples(input_data::InputData) # original name: create_res_pot_cons_tuple()
    if !input_data.contains_reserves
        return []
    else
        res_nodes = reserve_nodes(input_data)
        res_process_tuples = reserve_process_tuples(input_data)

        # filter those processes that have a reserve node as a source
        consumer_reserve_process_tuples = filter(x -> x[4] in res_nodes, res_process_tuples)
        return consumer_reserve_process_tuples
    end
end


"""
    state_node_tuples(input_data::InputData)

Return tuples for each node with a state (storage) for every time step and scenario. Form: (n, s, t).
"""
function state_node_tuples(input_data::InputData) # original name: create_node_state_tuple()
    state_node_tuples = []
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
    return state_node_tuples
end


"""
    balance_node_tuples(input_data::InputData)

Return tuples for each node over which balance should be maintained for every time step and scenario. Form: (n s, t).
"""
function balance_node_tuples(input_data::InputData) # original name: create_node_balance_tuple()
    balance_node_tuples = []
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
    reserve_process_tuples(input_data::InputData)

Return tuples containing information on process topologies with reserve potential for every time step and scenario. Form: (d, rt, p, so, si, s, t).

!!! note 
    This function assumes that the up and down reserve market directions are "res_up" and "res_down".
"""
function reserve_process_tuples(input_data::InputData) # original name: create_res_potential_tuple(), duplicate existed: create_proc_potential_tuple()
    if !input_data.contains_reserves
        return []
    else
        reserve_process_tuples = []
        processes = input_data.processes
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        res_nodes = reserve_nodes(input_data)
        res_type = collect(keys(input_data.reserve_type))
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

        for p in values(processes), s in scenarios, t in temporals.t
            for topo in p.topos
                if (topo.source in res_nodes|| topo.sink in res_nodes) && p.is_res
                    for d in res_dir, rt in res_type
                        push!(reserve_process_tuples, (d, rt, p.name, topo.source, topo.sink, s, t))
                    end
                end
            end
        end
        return reserve_process_tuples
    end
end

"""
    balance_process_tuples(input_data::InputData)

Return tuples for each process over which balance is to be maintained for every time step and scenario. Form: (p, s, t).
"""
function balance_process_tuples(input_data::InputData) # orignal name: create_proc_balance_tuple()
    balance_process_tuples = []
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for p in values(processes)
        if p.conversion == 1 && !p.is_cf && p.delay == 0
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
    if !input_data.contains_piecewise_eff
        return []
    else
        operative_slot_process_tuples = []
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
    if !input_data.contains_piecewise_eff
        return []
    else
        piecewise_efficiency_process_tuples = []
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
    cf_process_topology_tuples = []
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
    fixed_limit_process_topology_tuples = []
    processes = input_data.processes
    process_tuples = process_topology_tuples(input_data)
    res_nodes = reserve_nodes(input_data)
    for p in values(processes)
        if !p.is_cf && (p.conversion == 1)
            push!(fixed_limit_process_topology_tuples, filter(x -> x[1] == p.name && (x[2] == p.name || x[2] in res_nodes), process_tuples)...)
        end
    end
    return fixed_limit_process_topology_tuples
end


"""
    transport_process_topology_tuples(input_data::InputData)

Return tuples identifying transport process topologies for each time step and scenario. Form: (p, so, si, s, t).
"""
function transport_process_topology_tuples(input_data::InputData) # original name. create_trans_tuple()
    transport_process_topology_tuples = []
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
    reserve_node_tuples(input_data::InputData)

Return tuples for each node with reserves for each relevant reserve type, all time steps and scenarios. Form: (n, rt, s, t).
"""
function reserve_node_tuples(input_data::InputData) # original name: create_res_eq_tuple()
    if !input_data.contains_reserves
        return []
    else
        reserve_node_tuples = []
        res_nodes = reserve_nodes(input_data)
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        res_type = collect(keys(input_data.reserve_type))
        for n in res_nodes, r in res_type, s in scenarios, t in temporals.t
            push!(reserve_node_tuples, (n, r, s, t))
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
    if !input_data.contains_reserves
        return []
    else
        up_down_reserve_market_tuples = []
        markets = input_data.markets
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
        for m in values(markets), s in scenarios, t in temporals.t
            if m.direction == "up_down"
                push!(up_down_reserve_market_tuples, (m.name, s, t))
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
    if !input_data.contains_reserves
        return []
    else
        reserve_market_tuples = []
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
    fixed_market_tuples = []
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
    ramp_times_process_topology_tuple = []
    processes = input_data.processes
    temporals = input_data.temporals
    process_tuples = process_topology_tuples(input_data)
    for (name, source, sink, s, t) in process_tuples
        if processes[name].conversion == 1 && !processes[name].is_cf
            if t != temporals.t[1]
                push!(ramp_times_process_topology_tuple, (name, source, sink, s, t))
            end
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
    create_delay_process_tuple(input_data::OrderedDict)

Returns array of tuples containing processes with delay functionality. Form: (p, so, si, s, t).
"""
function create_delay_process_tuple(input_data::Predicer.InputData)
    if !input_data.contains_delay
        return []
    end
    delay_tuple = []
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for p in keys(processes)
        if processes[p].delay != 0
            for topo in processes[p].topos
                for t in temporals.t, s in scenarios
                    push!(delay_tuple, (p, topo.source, topo.sink, s, t))
                end
            end
        end
    end
    return delay_tuple
end

""" 
    create_balance_market_tuple(input_data::OrderedDict)

Returns array of tuples containing balance market. Form: (m, dir, s, t).
"""
function create_balance_market_tuple(input_data::Predicer.InputData)
    bal_tuples = []
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
    state_reserves(input_data::InputData)

Returns reserve potentials of processes connected to states with a reserve.
form: (sto_node, res_dir, res_type, p, so, si, s, t)
"""
function state_reserves(input_data::InputData)
    state_reserves = []
    if input_data.contains_reserves
        processes = input_data.processes
        nodes = input_data.nodes
        res_nodes_tuple = reserve_nodes(input_data)
        res_potential_tuple = reserve_process_tuples(input_data)
        process_tuple = process_topology_tuples(input_data)
        scenarios = collect(keys(input_data.scenarios))
        temporals = input_data.temporals
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
    reserve_limits = []
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
    return reserve_limits
end

"""
    function setpoint_tuples(input_data::InputData)

Function to create tuples for general constraints with setpoints. Form (c, s, t), where
c is the name of the general constraint. 
"""
function setpoint_tuples(input_data::InputData)
    setpoint_tuples = []
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
    function block_tuples(input_data::InputData)

Function to create tuples for inflow blocks. Form (blockname, node, s, t).
"""
function block_tuples(input_data::InputData)
    blocks = input_data.inflow_blocks
    block_tuples = []
    for b in collect(keys(blocks))
        for t_series in blocks[b].data.ts_data
            for t in t_series.series
                push!(block_tuples, (b, blocks[b].node, t_series.scenario, t[1]))
            end
        end
    end
    return block_tuples
end