# The functions of this file are used to check the validity of the imported input data,
# which at this time should be mostly in struct form

# Check list for errors:
    # X Process sink: commodity (ERROR) 
    # X Process (non-market) sink: market (ERROR)
    # X Process source: market
    # Conversion 2 and several branches (ERROR)
    # X Source in CF process (ERROR)
    # Reserve in CF process
    # Conversion 1 and neither source nor sink is p (error?)

    # Check integrity of timeseries
    # Check that there is equal amount of scenarios at all points

#@doc"""
#Function to validate input data\n
#params:\n
#input_data :: Dict() containing imported input data in struct form.
#"""


function validate_process_topologies(log, input_data)
    processes = input_data["processes"]
    nodes = input_data["nodes"]
    is_valid = log["is_valid"]
    
    for p in keys(processes)
        topos = processes[p].topos
        sources = filter(t -> t.sink == p, topos)
        sinks = filter(t -> t.source == p, topos)
        other = filter(t -> !(t in sources) && !(t in sinks), topos)
        for topo in sinks
            if topo.sink in keys(nodes)
                if nodes[topo.sink].is_commodity
                    push!(log["errors"], "Invalid topology: Process " * p * ". A commodity node cannot be a sink.\n")
                    is_valid = false
                end
                if processes[p].conversion != 3 && nodes[topo.sink].is_market
                    push!(log["errors"], "Invalid topology: Process " * p * ". A process with conversion != 3 cannot have a market as a sink.\n")
                    is_valid = false
                end
            else
                push!(log["errors"], "Invalid topology: Process " * p * ". Process sink not found in nodes.\n")
                is_valid = false
            end
        end
        for topo in sources
            if topo.source in keys(nodes)
                if processes[topo.sink].is_cf
                    push!(log["errors"], "Invalid topology: Process " * p * ". A CF process can not have a source.\n")
                    is_valid = false
                end
                if nodes[topo.source].is_market
                    push!(log["errors"], "Invalid topology: Process " * p * ". A process cannot have a market as a source.\n")
                    is_valid = false
                end
            else
                push!(log["errors"], "Invalid topology: Process " * p * ". Process source not found in nodes.\n")
                is_valid = false
            end
        end
        if processes[p].conversion == 2
            if length(processes[p].topos) > 1
                push!(log["errors"], "Invalid topology: Process " * p * ". A transport process cannot have several branches.\n")
                is_valid = false
            end
            if length(sources) > 0 || length(sinks) > 0
                push!(log["errors"], "Invalid topology: Process " * p * ". A transport process cannot have itself as a source or sink.\n")
                is_valid = false
            end
        end
    end
    log["is_valid"] = is_valid
end

function validate_data(input_data)
    log = Dict()
    log["is_valid"] = true
    log["errors"] = []
    # Call functions validating data
    validate_process_topologies(log, input_data)

    # Return log. 
    return log

end