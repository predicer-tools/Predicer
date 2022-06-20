using Dates
using DataStructures


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

    # Check that each of the nodes and processes is valid. 

    # Ensure that the min_online and min_offline parameter can be divided with dtf, the time between timesteps. 
    # otherwise a process may need to be online or offline for 1.5 timesteps, which is difficult to solve. 

    # In constraints, chekc if e.g. v_start even exists before trying to force start constraints. 



"""
    function validate_processes(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that each Process is valid, for example a cf process cannot be part of a reserve. 
"""
function validate_processes(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    processes = input_data.processes
    for p in processes
        # conversion and rest match
        # eff < 0
        # !(is_cf && is_res)
        # !(is_cf && is_online)
        # 0 <= min_load <= 1
        # 0 <= max_load <= 1
        # min load <= max_load
        # min_offline >= 0
        # min_online >= 0

        if 0 > p.eff
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The efficiency of a Process cannot be negative. .\n")
            is_valid = false
        end
        if !(0 <= p.min_load <= 1)
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The min load of a process must be between 0 and 1.\n")
            is_valid = false 
        end
        if !(0 <= p.max_load <= 1)
            push!(error_log["errors"], "Invalid Process: ", p.name, ". The max load of a process must be between 0 and 1.\n")
            is_valid = false 
        end
        if p.min_load > p.max_load
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
            validate_timeseriesdata(error_log, p.cf, input_data.temporals.ts_format)
        end

        if !isempty(p.eff_ts)
            validate_timeseriesdata(error_log, p.eff_ts, input_data.temporals.ts_format)
        end


        #= name::String
        conversion::Integer # change to string-based: unit_based, market_based, transfer_based
        is_cf::Bool
        is_cf_fix::Bool
        is_online::Bool
        is_res::Bool
        eff::Float64
        load_min::Float64
        load_max::Float64
        start_cost::Float64
        min_online::Int64
        min_offline::Int64
        initial_state::Bool
        topos::Vector{Topology}
        cf::TimeSeriesData
        eff_ts::TimeSeriesData
        eff_ops::Vector{Any}
        eff_fun::Vector{Tuple{Any,Any}} =#

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
    for n in nodes
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
            validate_timeseriesdata(error_log, n.cost, input_data.temporals.ts_format)
        end
        if isempty(n.inflow) && n.is_inflow
            push!(error_log["errors"], "Invalid Node: ", n.name, ". A Node with inflow must have an inflow timeseries.\n")
            is_valid = false        
        else
            validate_timeseriesdata(error_log, n.inflow, input_data.temporals.ts_format)
        end
        if n.is_state
            if isnothing(n.state)
                push!(error_log["errors"], "Invalid Node: ", n.name, ". A Node with a state must have a State.\n")
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
    if s.state_max < 0
        push!(error_log["errors"], "Invalid state parameters. State max cannot be smaller than 0.\n")
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
    function validate_timeseriesdata(error_log::OrderedDict, tsd::TimeSeriesData, ts_format::String)

Checks that the TimeSeriesData struct has one timeseries per scenario, and that the timesteps are in chronological order.
"""
function validate_timeseriesdata(error_log::OrderedDict, tsd::TimeSeriesData, ts_format::String)
    is_valid = error_log["is_valid"]
    scenarios = map(x -> x.scenario, tsd.ts_data)
    if scenarios != unique(scenarios)
        push!(error_log["errors"], "Invalid timeseries data. Multiple timeseries for the same scenario.\n")
        is_valid = false
    else
        for s in scenarios
            ts = tsd(s)
            for i in 1:length(ts)-1
                if ZonedDateTime(ts[i+1], temporals.ts_format) - ZonedDateTime(ts[i], ts_format) <= Dates.Minute(0)
                    push!(error_log["errors"], "Invalid timeseries. Timesteps not in chronological order.\n")
                    is_valid = false
                end
            end
        end
    end
    error_log["is_valid"] = is_valid
end


"""
    validate_temporals(error_log::OrderedDict, input_data::Predicer.InputData)

Checks that the timeseries data in the model is valid. 
"""
function validate_temporals(error_log::OrderedDict, input_data::Predicer.InputData)
    is_valid = error_log["is_valid"]
    temporals = input_data.temporals
    for i in 1:length(temporals.t)-1
        if ZonedDateTime(temporals.t[i+1], temporals.ts_format) - ZonedDateTime(temporals.t[i], temporals.ts_format) <= Dates.Minute(0)
            push!(error_log["errors"], "Invalid timeseries. Timesteps not in chronological order.\n")
            is_valid = false
        end
    end
    error_log["is_valid"] = is_valid
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
        sources = filter(t -> t.sink == p, topos)
        sinks = filter(t -> t.source == p, topos)
        other = filter(t -> !(t in sources) && !(t in sinks), topos)
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
                if processes[topo.sink].is_cf
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
            if length(sources) > 0 || length(sinks) > 0
                push!(error_log["errors"], "Invalid topology: Process " * p * ". A transport process cannot have itself as a source or sink.\n")
                is_valid = false
            end
        elseif processes[p].conversion == 1
            if !(p in sources) || !(p in sinks)
                push!(error_log["errors"], "Invalid topology: Process " * p * ". A process with conversion 1 must have itself as a source or a sink.\n")
                is_valid = false
            end
        end
    end
    error_log["is_valid"] = is_valid
end



function validate_data(input_data)
   error_log = Dict()
    error_log["is_valid"] = true
    error_log["errors"] = []
    # Call functions validating data
    validate_process_topologies(error_log, input_data)
    validate_reserves(error_log, input_data)

    # Return log. 
    return error_log

end