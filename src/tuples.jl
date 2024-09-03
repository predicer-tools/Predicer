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
    tuplebook["bid_slot_tuple"] = bid_slot_tuples(input_data)
    tuplebook["bid_scen_tuple"] = bid_scenario_tuples(input_data)   
    return tuplebook
end

"""
    validate_tuple(mc::OrderedDict, tuple::NTuple{N, String} where N, s_index::Int)

Helper function used to correct generated index tuples in cases when the start of the optimization horizon is the same for all scenarios.
"""
function validate_tuple(mc::OrderedDict, tuple::NTuple{N, AbstractString} where N, s_index::Int)
    if !isempty(mc["validation_dict"])
        if tuple[s_index+1] in mc["common_timesteps"]
            if s_index + 1 < length(tuple)
                (tuple[1:s_index-1]..., mc["validation_dict"][tuple[s_index:s_index+1]]..., tuple[s_index+2:end]...)
            else
                return (tuple[1:s_index-1]..., mc["validation_dict"][tuple[s_index:s_index+1]]...)
            end
        else
            return tuple
        end
    else
        return tuple
    end
end


"""
    validate_tuple(val_dict::OrderedDict, cts::Vector{String}, tuple::NTuple{N, AbstractString} where N, s_index::Int)

Helper function used to correct generated index tuples in cases when the start of the optimization horizon is the same for all scenarios.
This version is faster when validating larger tuples.
"""
function validate_tuple(val_dict::OrderedDict, cts::Union{Vector{String}, Vector{Any}}, tuple::NTuple{N, AbstractString} where N, s_index::Int)
    if !isempty(val_dict)
        if tuple[s_index+1] in cts
            if s_index + 1 < length(tuple)
                (tuple[1:s_index-1]..., val_dict[tuple[s_index:s_index+1]]..., tuple[s_index+2:end]...)
            else
                return (tuple[1:s_index-1]..., val_dict[tuple[s_index:s_index+1]]...)
            end
        else
            return tuple
        end
    else
        return tuple
    end
end

"""
    validate_tuple(mc::OrderedDict, tuple::Vector{T} where T, s_index::Int)

Helper function used to correct generated index tuples in cases when the start of the optimization horizon is the same for all scenarios.
"""
function validate_tuple(mc::OrderedDict, tuple::Vector{T} where T, s_index::Int)
    if !isempty(mc["validation_dict"])
        val_dict = mc["validation_dict"]
        cts =  mc["common_timesteps"]
        return map(x -> Predicer.validate_tuple(val_dict, cts, x, s_index), tuple)
    else
        return tuple
    end
end

"""
    validate_tuple(mc::OrderedDict, tuple::Vector{T} where T, s_index::Int)

Helper function used to correct generated index tuples in cases when the start of the optimization horizon is the same for all scenarios.
"""
function validate_tuple(val_dict::OrderedDict, cts::Union{Vector{String}, Vector{Any}}, tuple::Vector{T} where T, s_index::Int)
    if !isempty(val_dict)
        return map(x -> Predicer.validate_tuple(val_dict, cts, x, s_index), tuple)
    else
        return tuple
    end
end

"""
    reserve_nodes(input_data::InputData)

Return nodes which have a reserve. Form: (n).
"""
function reserve_nodes(input_data::InputData) # original name: create_res_nodes_tuple()
    reserve_nodes = String[]
    if input_data.setup.contains_reserves
        markets = input_data.markets
        group_tups = create_group_tuples(input_data)
        for m in collect(keys(markets))
            if markets[m].m_type == "reserve"
                for n in unique(map(y -> y[3], filter(x -> x[2] == markets[m].node, group_tups)))
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
        rmdt = NTuple{5, String}[]
        res_markets = filter(x -> x.m_type == "reserve", collect(values(input_data.markets)))
        scens = scenarios(input_data)
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
        sizehint!(rmdt, length(res_dir) * length(res_markets) * length(scens) * length(temporals.t))
        for m in res_markets
            if m.direction in res_dir
                for s in scens, t in temporals.t
                    push!(rmdt, (m.name, m.node, m.direction, s, t))
                end
            else
                for d in res_dir, s in scens, t in temporals.t
                    push!(rmdt, (m.name, m.node, d, s, t))
                end
            end
        end
        return rmdt
    end
end


"""
    process_topology_tuples(input_data::InputData)

Return tuples identifying each process topology (flow) for each time step and scenario. Form: (p, so, si, s, t).
"""
function process_topology_tuples(input_data::InputData) # original name: create_process_tuple()
    ptt = NTuple{5, String}[]
    processes = input_data.processes
    scens = scenarios(input_data)
    temporals = input_data.temporals
    n_topos = sum(map(x -> length(x.topos), collect(values(processes))))
    sizehint!(ptt, n_topos * length(scens) * length(temporals.t))
    for p in values(processes)
        for topo in p.topos
            for s in scens
                for t in temporals.t
                    push!(ptt, (p.name, topo.source, topo.sink, s, t))
                end
            end
        end
    end
    return ptt
end


"""
    previous_process_topology_tuples(input_data::InputData)

Return dict of tuples containing the previous process tuple, used in building ramp constraints.
"""
function previous_process_topology_tuples(input_data::InputData)
    pptt = OrderedDict()
    process_tuples = process_topology_tuples(input_data)
    temporals = input_data.temporals.t
    sizehint!(pptt, length(process_tuples))
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
        opt = NTuple{3, String}[]
        scens = scenarios(input_data)
        temporals = input_data.temporals
        sizehint!(opt, length(input_data.processes) * length(scens) * length(temporals.t))
        for p in values(input_data.processes)
            if p.is_online
                for s in scens, t in temporals.t
                    push!(opt, (p.name, s, t))
                end
            end
        end
        return opt
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
            if markets[m].m_type == "reserve"
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
        scens = scenarios(input_data)
        temporals = input_data.temporals
        markets = input_data.markets
        res_markets =  unique(map(x -> x[3], reserve_groups(input_data)))
        sizehint!(res_nodegroups, length(res_markets) * length(scens) * length(temporals.t))

        relevant_nodes = unique(map(x -> markets[x].node, res_markets))
        for n in relevant_nodes
            for s in scens, t in temporals.t
                push!(res_nodegroups, (n, s, t))
            end
        end
        return res_nodegroups
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
        scens = scenarios(input_data)
        temporals = input_data.temporals
        rns = reserve_nodes(input_data)
        res_nodes = NTuple{3, String}[]
        sizehint!(res_nodes, length(rns) * length(scens) * length(temporals.t))
        for n in rns
            for s in scens, t in temporals.t
                push!(res_nodes, (n, s, t))
            end
        end
        return res_nodes
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
        rpt = NTuple{7, String}[]
        res_processes = filter(x -> input_data.processes[x].is_res, collect(keys(input_data.processes)))
        scens = scenarios(input_data)
        temporals = input_data.temporals
        res_groups = reserve_groups(input_data)
        n_res = length(unique(map(x -> x[1:2], res_groups)))
        sizehint!(rpt, n_res * length(res_processes) * length(scens) * length(temporals.t))
        for p in res_processes
            res_cons = filter(x -> x[5] == p, res_groups)
            for rc in res_cons
                for topo in input_data.processes[p].topos
                    if (topo.source == rc[4]|| topo.sink == rc[4])
                        for s in scens, t in temporals.t
                            push!(rpt, (rc[1], rc[2], p, topo.source, topo.sink, s, t))
                        end
                    end
                end
            end
        end
        return rpt
    end
end


"""
    state_node_tuples(input_data::InputData)

Return tuples for each node with a state (storage) for every time step and scenario. Form: (n, s, t).
"""
function state_node_tuples(input_data::InputData) # original name: create_node_state_tuple()
    snt = NTuple{3, String}[]
    if input_data.setup.contains_states
        state_nodes = filter(x -> x.is_state, collect(values(input_data.nodes)))
        scens = scenarios(input_data)
        temporals = input_data.temporals
        sizehint!(snt, length(state_nodes) * length(scens) * length(temporals.t))
        for n in state_nodes
            for s in scens, t in temporals.t
                push!(snt, (n.name, s, t))
            end
        end
    end
    return snt
end


"""
    balance_node_tuples(input_data::InputData)

Return tuples for each node over which balance should be maintained for every time step and scenario. Form: (n s, t).
"""
function balance_node_tuples(input_data::InputData) # original name: create_node_balance_tuple()
    bnt = NTuple{3, String}[]
    nodes = filter(x -> !x.is_commodity && !x.is_market, collect(values(input_data.nodes)))
    scens = scenarios(input_data)
    temporals = input_data.temporals
    sizehint!(bnt, length(nodes) * length(scens) * length(temporals.t))
    for n in nodes
        for s in scens, t in temporals.t
            push!(bnt, (n.name, s, t))
        end
    end
    return bnt
end

"""
    previous_state_node_tuples(input_data::InputData)

Function to gather the node state tuple for the previous timestep. Returns a Dict() with the node_state_tup as key and the previous tup as value. 
"""
function previous_state_node_tuples(input_data::InputData)
    psnt = OrderedDict()
    node_state_tups = state_node_tuples(input_data)
    sizehint!(psnt, length(node_state_tups))
    for (i, n) in enumerate(node_state_tups)
        if n[3] != input_data.temporals.t[1]
            psnt[n] = node_state_tups[i-1]
        end
    end
    return psnt
end

"""
    balance_process_tuples(input_data::InputData)

Return tuples for each process over which balance is to be maintained for every time step and scenario. Form: (p, s, t).
"""
function balance_process_tuples(input_data::InputData) # orignal name: create_proc_balance_tuple()
    bpt = NTuple{3, String}[]
    bal_processes = filter(x -> !x.is_cf && x.conversion == 1, collect(values(input_data.processes)))
    scens = scenarios(input_data)
    temporals = input_data.temporals
    sizehint!(bpt, length(bal_processes) * length(scens) * length(temporals.t))
    for p in bal_processes
        if isempty(p.eff_fun)
            for s in scens, t in temporals.t
                push!(bpt, (p.name, s, t))
            end
        end
    end
    return bpt
end


"""
    operative_slot_process_tuples(input_data::InputData)

Return tuples identifying processes with piecewise efficiency for each of their operative slots (o), and every time step and scenario. Form: (p, s, t, o).
"""
function operative_slot_process_tuples(input_data::InputData) # original name: create_proc_op_balance_tuple()
    if !input_data.setup.contains_piecewise_eff
        return NTuple{4, String}[]
    else
        ospt = NTuple{4, String}[]
        op_processes = filter(x -> !x.is_cf && x.conversion == 1 && !isempty(x.eff_fun), collect(values(input_data.processes)))
        n_ops = sum(map(x -> length(x.eff_ops), op_processes))
        scens = scenarios(input_data)
        temporals = input_data.temporals
        sizehint!(ospt, n_ops * length(op_processes) * length(scens) * length(temporals.t))
        for p in op_processes
            for s in scens, t in temporals.t, o in p.eff_ops
                push!(ospt, (p.name, s, t, o))
            end
        end
        return ospt
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
        pept = NTuple{3, String}[]
        op_processes = filter(x -> !x.is_cf && x.conversion == 1 && !isempty(x.eff_fun), collect(values(input_data.processes)))
        scens = scenarios(input_data)
        temporals = input_data.temporals
        sizehint!(pept, length(op_processes) * length(scens) * length(temporals.t))
        for p in op_processes
            for s in scens, t in temporals.t
                push!(pept, (p.name, s, t))
            end
        end
        return pept
    end
end


"""
    cf_process_topology_tuples(input_data::InputData)

Return tuples identifying process topologies with a capacity factor for every time step and scenario. Form: (p, so, si, s, t).
"""
function cf_process_topology_tuples(input_data::InputData) # original name: create_cf_balance_tuple()
    cf_ptt = NTuple{5, String}[]
    cf_processes = filter(x -> x.is_cf, collect(values(input_data.processes)))
    reduced_process_tuples = unique(map(x -> x[1:3], process_topology_tuples(input_data)))
    scens = scenarios(input_data)
    temporals = input_data.temporals
    sizehint!(cf_ptt, length(cf_processes) * length(scens) * length(temporals.t))
    for p in cf_processes
        p_tups = filter(x -> x[1] == p.name, reduced_process_tuples)
        for p_tup in p_tups
            for s in scens, t in temporals.t
                push!(cf_ptt, (p_tup..., s, t))
            end
        end
    end
    return cf_ptt
end

"""
    fixed_limit_process_topology_tuples(input_data::InputData)

Return tuples containing information on process topologies with fixed limit on flow capacity. Form: (p, so, si, s, t).
"""
function fixed_limit_process_topology_tuples( input_data::InputData) # original name: create_lim_tuple()
    flptt = NTuple{5, String}[]
    fixed_processes = filter(x -> !x.is_cf && x.conversion == 1, collect(values(input_data.processes)))
    scens = scenarios(input_data)
    sizehint!(flptt, length(fixed_processes) * length(scens) * length(input_data.temporals.t))
    for p in fixed_processes
        for topo in p.topos
            for s in scens, t in input_data.temporals.t
                push!(flptt, (p.name, topo.source, topo.sink, s, t))
            end
        end
    end
    return flptt
end


"""
    transport_process_topology_tuples(input_data::InputData)

Return tuples identifying transport process topologies for each time step and scenario. Form: (p, so, si, s, t).
"""
function transport_process_topology_tuples(input_data::InputData) # original name. create_trans_tuple()
    tptt = NTuple{5, String}[]
    trans_processes = filter(x -> !x.is_cf && x.conversion == 2, collect(values(input_data.processes)))
    scens = scenarios(input_data)
    sizehint!(tptt, length(trans_processes) * length(scens) * length(input_data.temporals.t))
    for p in trans_processes
        for topo in p.topos
            for s in scens, t in input_data.temporals.t
                push!(tptt, (p.name, topo.source, topo.sink, s, t))
            end
        end
    end
    return tptt
end


"""
    reserve_nodegroup_tuples(input_data::InputData)

Return tuples for each nodegroup with reserves for each relevant reserve type, all time steps and scenarios. Form: (ng, rt, s, t).
"""
function reserve_nodegroup_tuples(input_data::InputData) # original name: create_res_eq_tuple()
    if !input_data.setup.contains_reserves
        return NTuple{4, String}[]
    else
        rnt = NTuple{4, String}[]
        res_nodegroup = nodegroup_reserves(input_data)
        res_typ = collect(keys(input_data.reserve_type))
        sizehint!(rnt, length(res_nodegroup) * length(res_typ))
        for ng_tup in res_nodegroup, rt in res_typ
            push!(rnt, (ng_tup[1], rt, ng_tup[2], ng_tup[3]))
        end
        return rnt
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
        scens = scenarios(input_data)
        temporals = input_data.temporals
        res_ms = unique(map(x -> x[1], reserve_market_tuples(input_data)))
        for rm in res_ms
            d = markets[rm].direction
            if d == "up/down" || d == "up/dw" || d == "up/dn" ||d == "up_down" || d == "up_dw" || d == "up_dn"
                for s in scens, t in temporals.t
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
        rmt = NTuple{3, String}[]
        res_markets = filter(x -> x.m_type == "reserve", collect(values(input_data.markets)))
        scens = scenarios(input_data)
        temporals = input_data.temporals
        sizehint!(rmt, length(res_markets) * length(scens) * length(temporals.t))
        for m in res_markets
            for s in scens, t in temporals.t
                push!(rmt, (m.name, s, t))
            end
        end
        return rmt
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
    scens = scenarios(input_data)
    for m in values(markets)
        if !isempty(m.fixed) && m.m_type == "energy"
            temps = map(x->x[1], m.fixed)
            for s in scens, t in temps
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
    rtptt = NTuple{5, String}[]
    ramp_procs = filter(x -> x.conversion == 1 && !x.is_cf, collect(values(input_data.processes)))
    n_topos = sum(map(x -> length(x.topos), ramp_procs))
    scens = scenarios(input_data)
    temps = input_data.temporals
    sizehint!(rtptt, n_topos * length(scens) * length(temps.t))
    for p in ramp_procs
        for topo in p.topos
            for s in scens, t in temps.t
                push!(rtptt, (p.name, topo.source, topo.sink, s, t))
            end
        end
    end
    return rtptt
end

"""
    scenarios(input_data::InputData)

Return scenarios. Form: (s).
"""
function scenarios(input_data::InputData) # original name: create_risk_tuple()
    scens = collect(keys(input_data.scenarios))
    return scens
end

""" 
    create_balance_market_tuple((input_data::Predicer.InputData)

Returns array of tuples containing balance market. Form: (m, dir, s, t).
"""
function create_balance_market_tuple(input_data::Predicer.InputData)
    bal_tuples = NTuple{4, String}[]
    energy_markets = filter(x -> x.m_type == "energy" && x.is_bid, collect(values(input_data.markets)))
    dir = ["up","dw"]
    scens = scenarios(input_data)
    temps = input_data.temporals
    sizehint!(bal_tuples, length(energy_markets) * length(dir) * length(scens) * length(temps.t))
    for m in energy_markets
        for d in dir, s in scens, t in temps.t
            push!(bal_tuples, (m.name, d, s, t))
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
        push!(mnt, (k, m.m_type, m.node, m.processgroup))
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
        state_res_nodes = filter(x -> x.is_state && x.is_res, collect(values(input_data.nodes)))
        if !isempty(state_res_nodes)
            processes = input_data.processes
            res_nodes_tuple = reserve_nodes(input_data)
            res_potential_tuple = reserve_process_tuples(input_data)
            reduced_res_potential_tuple = unique(map(x -> x[1:5], res_potential_tuple))
            process_tuple = process_topology_tuples(input_data)
            for n in res_nodes_tuple
                res_node_in_processes = unique(map(x -> (x[3], x[4], x[5]), filter(tup -> tup[5] == n, reduced_res_potential_tuple)))
                res_node_out_processes = unique(map(x -> (x[3], x[4], x[5]), filter(tup -> tup[4] == n, reduced_res_potential_tuple)))
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
                            if input_data.nodes[s_node].is_state
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
    end
    """    
    if input_data.setup.contains_reserves && input_data.setup.contains_states
        processes = input_data.processes
        state_nodes = filter(x -> x.is_state && x.is_res, collect(values(input_data.nodes)))
        res_nodes_tuple = reserve_nodes(input_data)
        res_potential_tuple = reserve_process_tuples(input_data)
        process_tuple = process_topology_tuples(input_data)
        for n in res_nodes_tuple
            res_node_in_processes = unique(map(x -> (x[3], x[4], x[5]), filter(tup -> tup[5] == n, reduced_res_potential_tuple)))
            res_node_out_processes = unique(map(x -> (x[3], x[4], x[5]), filter(tup -> tup[4] == n, reduced_res_potential_tuple)))
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
                        if input_data.nodes[s_node].is_state
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
    """ 
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
        res_markets = filter(x -> x.m_type == "reserve" && x.is_limited, collect(values(input_data.markets)))
        scens = scenarios(input_data)
        temporals = input_data.temporals
        sizehint!(reserve_limits, length(res_markets) * length(scens) * length(temporals.t))
        for m in res_markets
            for s in scens, t in temporals.t
                push!(reserve_limits,(m.name,s,t))
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
    st = NTuple{3, String}[]
    scens = scenarios(input_data)
    temporals = input_data.temporals.t
    setpoint_cons = filter(x -> x.is_setpoint, collect(values(input_data.gen_constraints)))
    sizehint!(st, length(setpoint_cons) * length(scens) * length(temporals))
    for c in setpoint_cons
        for s in scens, t in temporals
            push!(st, (c.name, s, t))
        end
    end
    return st
end

"""
    block_tuples(input_data::InputData)

Function to create tuples for inflow blocks. Form (blockname, node, s, t).
"""
function block_tuples(input_data::InputData)
    blocks = collect(values(input_data.inflow_blocks))
    bt = NTuple{4, String}[]
    bt_len = sum(map(x -> sum(map(y -> length(y.series), x.data.ts_data)), blocks))
    sizehint!(bt, bt_len)
    for b in blocks
        for t_series in b.data.ts_data
            for t in t_series.series
                push!(bt, (b.name, b.node, t_series.scenario, t[1]))
            end
        end
    end
    return bt
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
            push!(group_tuples, (groups[gn].g_type, gn, gm))
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
        scens = scenarios(input_data)
        temporals = input_data.temporals.t
        nodes = diffusion_nodes(input_data)
        sizehint!(node_diffusion_tup, length(nodes) * length(scens) * length(temporals))
        for n in nodes, s in scens, t in temporals
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
        scens = scenarios(input_data)
        sizehint!(node_delay_tup, length(input_data.node_delay) * length(scens) * length(input_data.temporals.t))
        for tup in input_data.node_delay
            n1 = tup[1]
            n2 = tup[2]
            delay = tup[3]
            for (i, t) in enumerate(input_data.temporals.t[begin:end])
                if (length(input_data.temporals.t) - i) <= delay
                    t2 = ZonedDateTime(t, input_data.temporals.ts_format) +  TimeZones.Hour(delay) * input_data.temporals.dtf
                else
                    t2 = input_data.temporals.t[i+delay]
                end
                for s in scens
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
        return unique(vcat(map(x -> x.node1, input_data.node_diffusion), map(y -> y.node2, input_data.node_diffusion)))
    else
        return String[]
    end
end

"""
    delay_nodes(input_data::InputData)

Function to obtain the nodes that are part of a delay relation. form (n)
"""
function delay_nodes(input_data::InputData)
    if input_data.setup.contains_delay
        return unique(vcat(map(x -> x[1], input_data.node_delay), map(x -> x[2], input_data.node_delay)))
    else
        return String[]
    end
end


"""
    bid_slot_tuples(input_data::InputData)

Function to create bid slot tuples. Form (m,slot,t)
"""
function bid_slot_tuples(input_data::InputData)
    b_slots = input_data.bid_slots
    bid_slot_tup = NTuple{3, String}[]
    markets = keys(b_slots)
    for m in markets
        for s in b_slots[m].slots
            for t in b_slots[m].time_steps
                push!(bid_slot_tup,(m,s,t))
            end
        end
    end
    return bid_slot_tup
end


"""
    bid_scenario_tuples(input_data::InputData)

Function to create bid scenario tuples linked to bid slots. Form (m,s,t)
"""
function bid_scenario_tuples(input_data::InputData)
    b_slots = input_data.bid_slots
    scens = scenarios(input_data)
    markets = keys(b_slots)
    bid_scen_tup = NTuple{3, String}[]
    for m in markets
        for s in scens
            for t in b_slots[m].time_steps
                push!(bid_scen_tup,(m,s,t))
            end
        end
    end
    return bid_scen_tup
end