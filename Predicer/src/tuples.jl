using DataStructures

"""
    create_tuples(model_contents::OrderedDict, input_data::InputData)

Create all tuples used in the model, and save them in the model_contents dict.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::InputData`: Struct containing data used to build the model. 
"""
function create_tuples(model_contents::OrderedDict, input_data::InputData) # unused, should be debricated
    model_contents["tuple"]["res_nodes_tuple"] = reserve_nodes(input_data)
    model_contents["tuple"]["res_tuple"] = reserve_market_directional_tuples(input_data)
    model_contents["tuple"]["process_tuple"] = process_topology_tuples(input_data)
    model_contents["tuple"]["proc_online_tuple"] = online_process_tuples(input_data)
    model_contents["tuple"]["res_potential_tuple"] = reserve_process_tuples(input_data)
    model_contents["tuple"]["res_pot_prod_tuple"] = producer_reserve_process_tuples(input_data)
    model_contents["tuple"]["res_pot_cons_tuple"] = consumer_reserve_process_tuples(input_data)
    model_contents["tuple"]["node_state_tuple"] = state_node_tuples(input_data)
    model_contents["tuple"]["node_balance_tuple"] = balance_node_tuples(input_data)
    model_contents["tuple"]["proc_balance_tuple"] = balance_process_tuples(input_data)
    model_contents["tuple"]["proc_op_balance_tuple"] = operative_slot_process_tuples(input_data)
    model_contents["tuple"]["proc_op_tuple"] = piecewise_efficiency_process_tuples(input_data)
    model_contents["tuple"]["cf_balance_tuple"] = cf_process_topology_tuples(input_data)
    model_contents["tuple"]["lim_tuple"] = fixed_limit_process_topology_tuples(input_data)
    model_contents["tuple"]["trans_tuple"] = transport_process_topology_tuples(input_data)
    model_contents["tuple"]["res_eq_tuple"] = reserve_node_tuples(input_data)
    model_contents["tuple"]["res_eq_updn_tuple"] = up_down_reserve_market_tuples(input_data)
    model_contents["tuple"]["res_final_tuple"] = reserve_market_tuples(input_data)
    model_contents["tuple"]["fixed_value_tuple"] = fixed_market_tuples(input_data)
    model_contents["tuple"]["ramp_tuple"] = process_topology_ramp_times_tuples(input_data)
    model_contents["tuple"]["risk_tuple"] = scenarios(input_data)
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
    reserve_market_directional_tuples = []
    markets = input_data.markets
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    res_dir = ["res_up", "res_down"]
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


"""
    process_topology_tuples(input_data::InputData)

Return tuples identifying each process topology (flow) for each time step and scenario. Form: (p, so, si, s, t).
"""
function process_topology_tuples(input_data::InputData) # original name: create_process_tuple()
    process_topology_tuples = []
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    for p in values(processes), s in scenarios
        for topo in p.topos
            for t in temporals.t
                push!(process_topology_tuples, (p.name, topo.source, topo.sink, s, t))
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


"""
    producer_reserve_process_tuples(input_data::InputData)

Return tuples containing information on 'producer' process topologies with reserve potential for every time step and scenario. Form: (d, rt, p, so, si, s, t).
"""
function producer_reserve_process_tuples(input_data::InputData) # original name: create_res_pot_prod_tuple()
    res_nodes = reserve_nodes(input_data)
    res_process_tuples = reserve_process_tuples(input_data)

    # filter those processes that have a reserve node as a sink
    producer_reserve_process_tuples = filter(x -> x[5] in res_nodes, res_process_tuples)
    return producer_reserve_process_tuples
end


"""
    consumer_reserve_process_tuples(input_data::InputData)

Return tuples containing information on 'consumer' process topologies with reserve potential for every time step and scenario. Form: (d, rt, p, so, si, s, t).
"""
function consumer_reserve_process_tuples(input_data::InputData) # original name: create_res_pot_cons_tuple()
    res_nodes = reserve_nodes(input_data)
    res_process_tuples = reserve_process_tuples(input_data)

    # filter those processes that have a reserve node as a source
    consumer_reserve_process_tuples = filter(x -> x[4] in res_nodes, res_process_tuples)
    return consumer_reserve_process_tuples
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
    reserve_process_tuples = []
    processes = input_data.processes
    scenarios = collect(keys(input_data.scenarios))
    temporals = input_data.temporals
    res_nodes = reserve_nodes(input_data)
    res_type = collect(keys(input_data.reserve_type))
    res_dir = ["res_up", "res_down"]

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


"""
    piecewise_efficiency_process_tuples(input_data::InputData)

Return tuples identifying processes with piecewise efficiency for each time step and scenario. Form: (p, s, t).
"""
function piecewise_efficiency_process_tuples(input_data::InputData) # original name: create_proc_op_tuple()
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

??Return tuples containing information on process topologies with fixed limit on flow capacity. Form: (p, so, si, s, t).
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


"""
    up_down_reserve_market_tuples(input_data::InputData)

Return tuples for each reserve market with an 'up_down' direction for all time steps and scenarios. Form: (r, s, t).

!!! note
    This function assumes that reserve markets with up and down reserve have market direction "up_down".
"""
function up_down_reserve_market_tuples(input_data::InputData) # original name: create_res_eq_updn_tuple()
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


"""
    reserve_market_tuples(input_data::InputData)

Return tuples for each reserve market for every time step and scenario. Form: (r, s, t).

!!! note
    This function assumes that reserve markets' market type is formatted "reserve".
"""
function reserve_market_tuples(input_data::InputData) # orignal name: create_res_final_tuple()
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