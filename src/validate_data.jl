using Dates
using DataStructures
using Predicer


# The functions of this file are used to check the validity of the imported input data,
# which at this time should be mostly in struct form

# Check list for errors:

    # x Topologies:
    # x Process sink: commodity (ERROR) 
    # x Process (non-market) sink: market (ERROR)
    # x Process (non-market) source: market (ERROR)
    # x Conversion 2 and several branches (ERROR)
    # x Source in CF process (ERROR)
    # x Conversion 1 and neither source nor sink is p (error?)
    # x Conversion 2( transport?) and several topos
    # x Conversion 2 and itself as source/sink

    # Reserve in CF process
    # Check integrity of timeseries - Checked model timesteps. 
    # Check that there is equal amount of scenarios at all points - accessing an non-existing scenario returns the first defined scenario instead. 
    # Check that each entity doesn't have several timeseries for the same scenario!
    # x Check that two entities don't have the same name.
    # Check that state min < max, process min < max, etc. 

    # Check that each node with is_res has a corresponding market.
    # 

    # Check that each of the nodes and processes is valid. 

    # Ensure that the min_online and min_offline parameter can be divided with dtf, the time between timesteps. 
    # otherwise a process may need to be online or offline for 1.5 timesteps, which is difficult to solve. 

    # In constraints, chekc if e.g. v_start even exists before trying to force start constraints. 
    # Chewck that all given values have reasonable values, ramp values >0 for example. 

    # Check that a process doesnät participate in two energy markets at the same time 
    # - should this be allowed, since the energy markets can be "blocked" using gen_constraints?
    # - Process should be fine, as long as topos are different. 

    # Check that each entity (node, process, market, etc) has all relevant information defined. 


    #TODO!
    # Check that a process is connected to a node in the given node group during market participation
    # 
    # Check that the "node" connected to an energy market is a node, and that the 
    # "node connected to a reserve market is a nodegroup. 
    # Check that each node/process which is part of a node/process group referenced by a reserve has is_res
    # Check that the node/process group of a reserve exists
    # Check that the groups are not empty

    # check that reserve processes and reserve nodes match, so that the processes of a reserve product process group
    # actually connect to the nodes in the reserve nodegroup. Issue an warning if this isn't the case?
    # check that the processes in groups that are linked to reserves are all is_res?


    # check that if input_data.setup.reserve_realisation==false, the reserve realisation coefficients have to be 0.
    # check that if input_data.setup.common_timesteps > 0, then input_data.setup.common_scenario_name cannot be empty
    # ensure that the scenario-dependent timeseries are equal for the first x timesteps if common_timesteps > 0 
    # 


function validate_bid_slots(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]

    # check that the bidslot end points for a market are outside or equal to the min/max prices of the linked market
    for m in collect(keys(input_data.bid_slots))
        timesteps = input_data.bid_slots[m].time_steps
        for t in timesteps
            t_price_keys = filter(x -> x[1] == t, collect(keys(input_data.bid_slots[m].prices)))
            bs_prices = map(x -> input_data.bid_slots[m].prices[x], t_price_keys)
            m_prices = map(s -> input_data.markets[m].price(s, t), scenarios(input_data))

            if minimum(bs_prices) > minimum(m_prices)
                push!(error_log["errors"], "The smallest bid slot price for the timestep "* t*" for the market " * m * " is not smaller than or equal to the market prices\n")
                is_valid = false 
            end
            if maximum(bs_prices) < maximum(m_prices)
                push!(error_log["errors"], "The largest bid slot price for the timestep "* t*" for the market " * m * " is not larger than or equal to the market prices\n")
                is_valid = false 
            end

            if !(sort(bs_prices) == bs_prices)
                push!(error_log["errors"], "The market bid slot prices should be in ascending order. (market: " * m *", timestep: " * t * "\n")
                is_valid = false 
            end
        end
    end
    error_log["is_valid"] = is_valid
    return error_log
end

function validate_common_start(error_log::OrderedDict, series, common_steps_n)
    is_valid = error_log["is_valid"]
    # TODO
    # check that the start of the timeseries in the model are equal between the scenarios (per timeseries type)
    # 
    if common_steps_n > 0
        for k1 in collect(keys(series))
            for k2 in collect(keys(series[k1]))
                scens = map(x -> string(x.scenario), series[k1][k2].ts_data)
                starts = map(s -> series[k1][k2](s)[1:common_steps_n], scens)
                if length(unique(starts)) > 1
                    push!(error_log["errors"], "The scenarios are not equal in: " * k2 * ", " * k1 * ", despite a common start.\n")
                    is_valid = false 
                end
            end
        end
    end
    error_log["is_valid"] = is_valid
    return error_log
end

function validate_timeseries(error_log::OrderedDict, input_data::Predicer.InputData)
    # ensure that the timeseries provided to the model are correct
    
    series = Dict()
    
    # processes:
    series["cf"] = Dict()
    series["eff_ts"] = Dict()
    series["cap_ts"] = Dict()
    for p in collect(keys(input_data.processes))
        # cf timeseries
        if input_data.processes[p].is_cf
            series["cf"][p] = input_data.processes[p].cf
        end
        # eff_ts
        if !isempty(input_data.processes[p].eff_ts)        
            series["eff_ts"][p] = input_data.processes[p].eff_ts
        end

        #topology cap_ts
        for topo in input_data.processes[p].topos
            if !isempty(topo.cap_ts)
                series["cap_ts"][p] = topo.cap_ts
            end
        end
    end

    # nodes:
    series["inflow"] = Dict()
    series["cost"] = Dict()
    for n in collect(keys(input_data.nodes))
        # inflow
        if input_data.nodes[n].is_inflow
            series["inflow"][n] = input_data.nodes[n].inflow
        end
        # cost
        if input_data.nodes[n].is_commodity
            series["cost"][n] = input_data.nodes[n].cost
        end

    end

    # markets:
    series["price"] = Dict()
    series["up_price"] = Dict()
    series["down_price"] = Dict()
    for m in collect(keys(input_data.markets))
        # price
        series["price"][m] = input_data.markets[m].price
        # up price
        if !isempty(input_data.markets[m].up_price)
            series["up_price"][m] = input_data.markets[m].up_price
        end
        # down price
        if !isempty(input_data.markets[m].down_price)
            series["down_price"][m] = input_data.markets[m].down_price
        end
    end

    # InflowBlock:
    # data?
    #TODO

    # gen_constraints:
    series["gen_constraint_factor"] = Dict()
    series["gen_constraint_constant"] = Dict()
    for c in collect(keys(input_data.gen_constraints))
        # confactor
        for f in input_data.gen_constraints[c].factors
            series["gen_constraint_factor"][c*"_"*string(f.var_tuple)] = f.data
        end
        # constant
        series["gen_constraint_constant"][c] = input_data.gen_constraints[c].constant
    end

    error_log = validate_common_start(error_log, series, input_data.setup.common_timesteps)
    return error_log
end

function validate_node_delay(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    nds = input_data.node_delay
    nodes = input_data.nodes

    # check that the model has timesteps compatible with the delay
    # The timesteps should be multipliers of each of the delays, 
    # and the timestep length has to be constant
    if input_data.temporals.is_variable_dt && input_data.setup.contains_delay
        push!(error_log["errors"], "The model currently doesn't support both variable timesteps and delays.\n")
        is_valid = false 
    else
        for delay in map(x -> x[3], input_data.node_delay)
            if delay % input_data.temporals.dtf != 0
                push!(error_log["errors"], "The delay length between two nodes must be a multiple of the timestep length.\n")
                is_valid = false 
            end
        end
    end

    # check that there is only one delay per a pair of nodes
    if length(nds) != length(unique(map(x -> (x[1], x[2]), nds)))
        push!(error_log["errors"], "Each node-node pair can only have one defined delay.\n")
        is_valid = false 
    end

    # Check that the delay is positive
    if !isempty(filter(x -> x[3] <= 0, nds))
        push!(error_log["errors"], "The defined delays must always be larger than 0. If not, just use a transfer process.\n")
        is_valid = false 
    end

    # check that delay limits are reasonable
    if !isempty(filter(x -> x[4] > x[5], nds))
        push!(error_log["errors"], "The lower limit of the defined delays must be smaller than the defined upper limit.\n")
        is_valid = false 
    end
    if !isempty(filter(x -> x[4] < 0, nds))
        push!(error_log["errors"], "The lower limit of the defined delays must be larger than or equal to zero.\n")
        is_valid = false 
    end
    if !isempty(filter(x -> x[5] <= 0, nds))
        push!(error_log["errors"], "The upper limit of the defined delays must be larger than zero.\n")
        is_valid = false 
    end

    # Check that the nodes with delay isn't an market node
    if !isempty(filter(x -> nodes[x[1]].is_market || nodes[x[2]].is_market, nds))
        push!(error_log["errors"], "Market nodes cannot be part of delay connections.\n")
        is_valid = false 
    end
    # Check that the nodes with delay isn't an commodity node
    if !isempty(filter(x -> nodes[x[1]].is_commodity || nodes[x[2]].is_commodity, nds))
        push!(error_log["errors"], "Commodity nodes cannot be part of delay connections.\n")
        is_valid = false 
    end

    error_log["is_valid"] = is_valid
end

function validate_node_diffusion(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    nodes = input_data.nodes

    for n in collect(keys(nodes))
        if nodes[n].is_state
            if nodes[n].state.t_e_conversion <= 0.0
                # Check that the t_e_conversion coefficient is larger than 0
                push!(error_log["errors"], "The t_e_conversion coefficient of Node: (" * n * ") must be larger than 0.\n")
                is_valid = false 
            end
        end
    end
    for node_conn in input_data.node_diffusion
        if minimum(node_conn.coefficient) < 0 
            # Check that the node diffusion coeff is larger than 0
            push!(error_log["errors"], "The node diffusion coefficient of Node diffusion coefficient: (" * node_conn.node1 * ", " * node_conn.node2 * ") must be equal to or larger than 0.\n")
            is_valid = false 
        end
        if !(node_conn.node1 in collect(keys(nodes)))
            # Check that the nodes in node diffusion connection exist
            push!(error_log["errors"], "The node: ("*node_conn.node1*") of node diffusion connection : (" * (node_conn.node1, node_conn.node2) * ") is not defined.\n")
            is_valid = false 
        elseif !(node_conn.node2 in collect(keys(nodes)))
            # Check that the nodes in node diffusion connection exist
            push!(error_log["errors"], "The node: ("*node_conn.node2*") of node diffusion connection : (" * (node_conn.node1, node_conn.node2) * ") is not defined.\n")
            is_valid = false 
        elseif node_conn.node1 == node_conn.node2
            # Check that the nodes in the connection are not the same
            push!(error_log["errors"], "The node: ("*node_conn.node1* ") in the node diffusion connection : (" * (node_conn.node1, node_conn.node2) * ") is given twice.\n")
            is_valid = false
        else
            if !nodes[node_conn.node1].is_state
                # Check that the nodes on node diffusion connections have states
                push!(error_log["errors"], "The node: ("*node_conn.node1*") of Node diffusion connection: (" * (node_conn.node1, node_conn.node2) * ") has no state.\n")
                is_valid = false
            end
            if !nodes[node_conn.node2].is_state
                # Check that the nodes on node diffusion connections have states
                push!(error_log["errors"], "The node: ("*node_conn.node2*") of Node diffusion connection: (" * (node_conn.node1, node_conn.node2) * ") has no state.\n")
                is_valid = false
            end
        end
    end
    

    error_log["is_valid"] = is_valid
end

function validate_inflow_blocks(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"] 
    blocks = input_data.inflow_blocks
    nodes = input_data.nodes
    for b in collect(keys(blocks))
        if !(blocks[b].node in collect(keys(nodes)))
            # Check that the linked nodes exist, and that they are of the correct type
            push!(error_log["errors"], "The Node linked to the block (" * b * ", " * blocks[b].node * ") is not found in Nodes.\n")
            is_valid = false 
        else
            # Check that the linked node is of the correct type (not market or commodity)
            if nodes[blocks[b].node].is_market
                push!(error_log["errors"], "A market Node ("* blocks[b].node *") cannot be linked to a inflow block ("* b *").\n")
                is_valid = false 
            elseif nodes[blocks[b].node].is_commodity
                push!(error_log["errors"], "A commodity Node ("* blocks[b].node *") cannot be linked to a inflow block ("* b *").\n")
                is_valid = false 
            end
        end

        # check that there aren't two series for the same scenario
        if length(blocks[b].data.ts_data) != length(unique(map(x -> x.scenario, blocks[b].data.ts_data)))
            push!(error_log["errors"], "Inflow block (" * b * ") has multiple series for the same scenario.\n")
            is_valid = false 
        end

        for timeseries in blocks[b].data.ts_data
            ts = keys(timeseries.series)
            # Check that ALL the timesteps in the block are either not found in temporals, or ALL found in the temporals.
            if any((ts .∈ (input_data.temporals.t,)) .!= (first(ts) ∈ input_data.temporals.t))
                push!(error_log["errors"], "The timesteps of the block (" * b * ") should either all be found, or all not found in temporals. No partial blocks allowed.\n")
                is_valid = false 
            end
        end
    end
    error_log["is_valid"] = is_valid
end

function validate_groups(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"] 
    processes = input_data.processes
    nodes = input_data.nodes
    groups = input_data.groups

    for g in collect(keys(groups))
        # check that the groupnames are  not the same as any process, node
        if g in [collect(keys(processes)); collect(keys(nodes))  ]
            push!(error_log["errors"], "Invalid Groupname: ", g, ". The groupname must be unique and different from any node or process names.\n")
            is_valid = false 
        end
        # check that node groups have nodes and process groups have processes
        for m in groups[g].members
            if groups[g].g_type == "node"
                # check that node groups have nodes and process groups have processes
                if !(m in collect(keys(nodes))  )
                    push!(error_log["errors"], "Nodegroups (" * g * ") can only have Nodes as members!\n")
                    is_valid = false 
                end
            elseif groups[g].g_type == "process"
                # check that node groups have nodes and process groups have processes
                if !(m in collect(keys(processes)))
                    push!(error_log["errors"], "Processgroups (" * g * ") can only have Processes as members!\n")
                    is_valid = false 
                end
            end
        end
    end

    # Check that each entity in a groups member has the group as member
    for g in collect(keys(groups))
        for m in groups[g].members
            if m in collect(keys(nodes))
                if !(g in nodes[m].groups)
                    push!(error_log["errors"], "The member (" * m * ") of a nodegroup must have the group given in node.groups!\n")
                    is_valid = false 
                end
            elseif m in collect(keys(processes))
                if !(g in processes[m].groups)
                    push!(error_log["errors"], "The member (" * m * ") of a processgroup must have the group given in process.groups!\n")
                    is_valid = false 
                end
            end
        end
    end

    # check that each process and each node is part of a group of the correct type..
    for n in collect(keys(nodes))
        for ng in nodes[n].groups
            if !(groups[ng].g_type == "node")
                push!(error_log["errors"], "Nodes (" * n * ") can only be members of Nodegroups, not Processgroups!\n")
                is_valid = false 
            end
        end
    end
    for p in collect(keys(processes))
        for pg in processes[p].groups
            if !(groups[pg].g_type == "process")
                push!(error_log["errors"], "Processes (" * p * ") can only be members of Processgroups, not Nodegroups!\n")
                is_valid = false 
            end
        end
    end
    error_log["is_valid"] = is_valid
end

function validate_gen_constraints(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    gcs = input_data.gen_constraints
    nodes = input_data.nodes
    processes = input_data.processes

    for gc in collect(keys(gcs))
        # Check that the given operators are valid.
        if !(gcs[gc].gc_type in ["gt", "eq", "st"])
            push!(error_log["errors"], "The operator '" * gcs[gc].gc_type * "' is not valid for the gen_constraint '" * gc *"'.\n")
            is_valid = false 
        end

        #check that the factors of the same gc are all of the same type
        if length(unique(map(f -> f.var_type, gcs[gc].factors))) > 1
            push!(error_log["errors"], "A gen_constraint (" * gc * ") cannot have factors of different types.\n")
            is_valid = false 
        end

        # Check that gen_constraint has at least one factor. 
        if isempty(gcs[gc].factors)
            push!(error_log["errors"], "The gen_constraint (" * gc * ") must have at least one series for a 'factor' defined.\n")
            is_valid = false 
        else
            for fac in gcs[gc].factors
                if fac.var_type == "state"
                    #check that the linked node exists
                    if !(fac.var_tuple[1] in collect(keys(nodes)))
                        push!(error_log["errors"], "The node '"* fac.var_tuple[1] * "' linked to gen_constraint (" * gc * ") is not a node.\n")
                        is_valid = false 
                    else
                        # check that the linked node has a state
                        if !nodes[fac.var_tuple[1]].is_state
                            push!(error_log["errors"], "The node '"* fac.var_tuple[1] * "' linked to gen_constraint (" * gc * ") has no state variable.\n")
                            is_valid = false 
                        end
                    end
                elseif fac.var_type == "online"
                    #check that the linked process exists
                    if !(fac.var_tuple[1] in collect(keys(processes)))
                        push!(error_log["errors"], "The process '"* fac.var_tuple[1] * "' linked to gen_constraint (" * gc * ") is not a process.\n")
                        is_valid = false 
                    else
                        # check that the linked process has a state
                        if !processes[fac.var_tuple[1]].is_online
                            push!(error_log["errors"], "The process '"* fac.var_tuple[1] * "' linked to gen_constraint (" * gc * ") has no online functionality.\n")
                            is_valid = false 
                        end
                    end
                elseif fac.var_type == "flow"
                    #check that the linked process exists
                    if !(fac.var_tuple[1] in collect(keys(processes)))
                        push!(error_log["errors"], "The process '"* fac.var_tuple[1] * "' linked to gen_constraint (" * gc * ") is not a process.\n")
                        is_valid = false 
                    else
                        # check that the linked process has a relevant topo
                        p = fac.var_tuple[1]
                        c = fac.var_tuple[2]
                        if length(filter(t -> t.source == c || t.sink == c, processes[fac.var_tuple[1]].topos)) < 1
                            push!(error_log["errors"], "The flow ("* p * ", " * c * ") linked to gen_constraint (" * gc * ") could not be found.\n")
                            is_valid = false 
                        end
                    end
                end
            end
        end

        # Check that setpoints have no constants, and non-setpoints have constants. 
        if gcs[gc].is_setpoint
            if !isempty(gcs[gc].constant)
                push!(error_log["errors"], "The gen_constraint (" * gc * ") of the 'setpoint' type can not have a series for a 'constant'.\n")
                is_valid = false 
            end
        else
            if isempty(gcs[gc].constant)
                push!(error_log["errors"], "The gen_constraint (" * gc * ") of the 'normal' type must have a series for a 'constant'.\n")
                is_valid = false 
            end
        end
    end

    error_log["is_valid"] = is_valid
end

"""
    function validate_processes(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that each Process is valid, for example a cf process cannot be part of a reserve. 
"""
function validate_processes(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    processes = input_data.processes
    for pname in keys(processes)

        # conversion and rest match
        # eff < 0
        # !(is_cf && is_res)
        # !(is_cf && is_online)
        # 0 <= min_load <= 1
        # 0 <= max_load <= 1
        # min load <= max_load
        # min_offline >= 0
        # min_online >= 0

        p = processes[pname]
        if 0 > p.eff && p.conversion != 3
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The efficiency of a Process cannot be negative. .\n")
            is_valid = false
        end
        if !(0 <= p.load_min <= 1)
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The min load of a process must be between 0 and 1.\n")
            is_valid = false 
        end
        if !(0 <= p.load_max <= 1)
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The max load of a process must be between 0 and 1.\n")
            is_valid = false 
        end
        if p.load_min > p.load_max
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The min load of a process must be less or equal to the max load.\n")
            is_valid = false 
        end
        if p.min_online < 0
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The min online time of a process must be more or equal to 0.\n")
            is_valid = false 
        end
        if p.min_online < 0
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The min offline time of a process must be more or equal to 0.\n")
            is_valid = false 
        end

        if p.is_cf
            if p.is_res
                push!(error_log["errors"], "Invalid Process: ", p.name, ". A cf process cannot be part of a reserve.\n")
                is_valid = false 
            end
            if p.is_online
                push!(error_log["errors"], "Invalid Process: ", p.name, ". A cf process cannot have online functionality.\n")
                is_valid = false 
            end
            validate_timeseriesdata(error_log, p.cf)
        end

        if !isempty(p.eff_ts)
            validate_timeseriesdata(error_log, p.eff_ts)
        end
    end
    error_log["is_valid"] = is_valid
end


"""
    function validate_nodes(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that each Node is valid, for example a commodity node cannot have a state or an inflow. 
"""
function validate_nodes(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    nodes = input_data.nodes
    for nname in keys(nodes)
        n = nodes[nname]
        if n.is_market && n.is_commodity
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A commodity Node cannot be a market.\n")
            is_valid = false
        end
        if n.is_state && n.is_commodity
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A commodity Node cannot have a state.\n")
            is_valid = false
        end
        if n.is_res && n.is_commodity
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A commodity Node cannot be part of a reserve.\n")
            is_valid = false
        end
        if n.is_inflow && n.is_commodity
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A commodity Node cannot have an inflow.\n")
            is_valid = false
        end
        if n.is_market && n.is_inflow
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A market node cannot have an inflow.\n")
            is_valid = false
        end
        if n.is_market && n.is_state
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A market node cannot have a state.\n")
            is_valid = false
        end
        if n.is_market && n.is_res
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A market node cannot have a reserve.\n")
            is_valid = false
        end
        if isempty(n.cost) && n.is_commodity
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A commodity Node must have a price.\n")
            is_valid = false
        else
            validate_timeseriesdata(error_log, n.cost)
        end
        if isempty(n.inflow) && n.is_inflow
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A Node with inflow must have an inflow timeseries.\n")
            is_valid = false        
        else
            validate_timeseriesdata(error_log, n.inflow)
        end
        if n.is_state
            if isnothing(n.state)
                push!(error_log["errors"], "Invalid Node: ", n.name, ". A Node defined as having a state must have a State.\n")
                is_valid = false
            else
                validate_state(error_log, n.state)
            end
        end
    end
    error_log["is_valid"] = is_valid
end


"""
    function validate_state(error_log::OrderedDict, s::Predicer.State)

Checks that the values of a state are valid and logical.
"""
function validate_state(error_log::OrderedDict, s::Predicer.State)
    is_valid = error_log["is_valid"]
    if s.out_max < 0
        push!(error_log["errors"], "Invalid state parameters. Maximum outflow to a state cannot be smaller than 0.\n")
        is_valid = false
    end
    if s.in_max < 0
        push!(error_log["errors"], "Invalid state parameters. Maximum inflow to a state cannot be smaller than 0.\n")
        is_valid = false
    end
    if s.state_max < 0
        push!(error_log["errors"], "Invalid state parameters. State max cannot be smaller than 0.\n")
        is_valid = false
    end
    if s.state_min < 0
        push!(error_log["errors"], "Invalid state parameters. State min cannot be smaller than 0.\n")
        is_valid = false
    end
    if s.state_max < s.state_min
        push!(error_log["errors"], "Invalid state parameters. State max cannot be smaller than state min.\n")
        is_valid = false
    end
    if !(s.state_min <= s.initial_state <= s.state_max)
        push!(error_log["errors"], "Invalid state parameters. The initial state has to be between state min and state max.\n")
        is_valid = false
    end
    error_log["is_valid"] = is_valid
end


"""
    function validate_timeseriesdata(error_log::OrderedDict, tsd::TimeSeriesData)

Checks that the TimeSeriesData struct has one timeseries per scenario, and that the timesteps are in chronological order.
"""
function validate_timeseriesdata(error_log::OrderedDict, tsd::Predicer.TimeSeriesData)
    # Nah, it'll be fine.
end


"""
    validate_temporals(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that the time data in the model is valid. 
"""
function validate_temporals(error_log::OrderedDict, input_data::Predicer.InputData)
    # Nah, it'll be fine.
    error_log["is_valid"] = true
end


"""
    validate_unique_names(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that the entity names in the input data are unique.
"""
function validate_unique_names(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    p_names = collect(keys(input_data.processes))
    n_names = collect(keys(input_data.nodes))
    if length(p_names) != length(unique(p_names))
        push!(error_log["errors"], "Invaling naming. Two processes cannot have the same name.\n")
        is_valid = false
    end
    if length(n_names) != length(unique(n_names))
        push!(error_log["errors"], "Invaling naming. Two nodes cannot have the same name.\n")
        is_valid = false
    end
    if length([p_names; n_names]) != length(unique([p_names; n_names]))
        push!(error_log["errors"], "Invaling naming. A process and a node cannot have the same name.\n")
        is_valid = false
    end
    error_log["is_valid"] = is_valid
end 


"""
    function validate_process_topologies(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that the topologies in the input data are valid. 
"""
function validate_process_topologies(error_log::OrderedDict, input_data::Predicer.InputData)
    processes = input_data.processes
    nodes = input_data.nodes
    is_valid = error_log["is_valid"]
    
    for p in keys(processes)
        topos = processes[p].topos
        if processes[p].conversion == 2
            sources = topos
            sinks = topos
        else
            sources = filter(t -> t.sink == p, topos)
            sinks = filter(t -> t.source == p, topos)
        end
        for topo in sinks
            if topo.sink in keys(nodes)
                if nodes[topo.sink].is_commodity
                    push!(error_log["errors"], "Invalid topology: Process " * p * ". A commodity node cannot be a sink.\n")
                    is_valid = false
                end
                if processes[p].conversion != 3 && nodes[topo.sink].is_market
                    push!(error_log["errors"], "Invalid topology: Process " * p * ". A process with conversion != 3 cannot have a market as a sink.\n")
                    is_valid = false
                end
            else
                push!(error_log["errors"], "Invalid topology: Process " * p * ". Process sink not found in nodes.\n")
                is_valid = false
            end
        end
        for topo in sources
            if topo.source in keys(nodes)
                if processes[p].is_cf
                    push!(error_log["errors"], "Invalid topology: Process " * p * ". A CF process can not have a source.\n")
                    is_valid = false
                end
                if nodes[topo.source].is_market
                    push!(error_log["errors"], "Invalid topology: Process " * p * ". A process cannot have a market as a source.\n")
                    is_valid = false
                end
            else
                push!(error_log["errors"], "Invalid topology: Process " * p * ". Process source not found in nodes.\n")
                is_valid = false
            end
        end
        if processes[p].conversion == 2
            if length(processes[p].topos) > 1
                push!(error_log["errors"], "Invalid topology: Process " * p * ". A transport process cannot have several branches.\n")
                is_valid = false
            end
            if p in map(t -> [t.source, t.sink], processes[p].topos)
                push!(error_log["errors"], "Invalid topology: Process " * p * ". A transport process cannot have itself as a source or sink.\n")
                is_valid = false
            end
        elseif processes[p].conversion == 1
            if !(p in map(x -> x.sink, sources) || p in map(x -> x.source, sinks))
                push!(error_log["errors"], "Invalid topology: Process " * p * ". A process with conversion 1 must have itself as a source or a sink.\n")
                is_valid = false
            end
        end
    end
    error_log["is_valid"] = is_valid
end


function validate_data(input_data)
    error_log = OrderedDict()
    error_log["is_valid"] = true
    error_log["errors"] = []
    # Call functions validating data
    validate_process_topologies(error_log, input_data)
    validate_processes(error_log, input_data)
    validate_nodes(error_log, input_data)
    validate_temporals(error_log, input_data)
    validate_unique_names(error_log, input_data)
    validate_gen_constraints(error_log, input_data)
    validate_inflow_blocks(error_log, input_data)
    validate_groups(error_log, input_data)
    validate_node_diffusion(error_log, input_data)
    validate_node_delay(error_log, input_data)
    # Return log. 
    return error_log
end