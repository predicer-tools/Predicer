using JuMP
using Cbc
using DataFrames
using TimeZones
using Dates
using DataStructures
using XLSX


# Function used to setup model based on the given input data. This function 
# calls separate functions for setting up the variables and constraints used 
# in the model. Returns "model_contents"; a dictionary containing all variables,
# constraints, tuples, and expressions used to build the model.
"""
    Initialize(input_data::Predicer.InputData)

Function to initialize the model based on given input data. This function calls functions initializing the solver, model, etc. 

# Arguments
- `input_data::Predicer.InputData`: Dictionary containing data used to build the model. 

# Examples
```julia-repl
julia> model_contents = Initialize(input_data);
OrderedDict{Any, Any} with 8 entries:
  "constraint"     => ...
  "expression"     => ...
  "variable"       => ...
  "tuple"          => ...
  "gen_constraint" => ...
  "gen_expression" => ...
  "res_dir"        => ...
  "model"          => ...
```
"""
function Initialize(input_data::Predicer.InputData)
    input_data_check = validate_data(input_data)
    if input_data_check["is_valid"]
        model_contents = Initialize_contents()
        model = init_jump_model(Cbc.Optimizer)
        model_contents["model"] = model
        setup_model(model_contents, input_data)
        return model_contents
    else
        return input_data_check["errors"]
    end
end

# Function to run the model built based on the given input data. 

"""
    solve_model(model_contents::OrderedDict)

Function to use the optimizer to solve model. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function solve_model(model_contents::OrderedDict)
    model = model_contents["model"]
    optimize!(model)
end

# Function to initialize jump model with the given solver. 
function init_jump_model(solver)
    model = JuMP.Model(solver)
    set_optimizer_attributes(model, "LogLevel" => 1, "PrimalTolerance" => 1e-7)
    return model
end

# Add all constraints, (expressions? and variables?) into a large dictionary for easier access, 
# and being able to use the anonymous notation while still being conveniently accessible. 
function Initialize_contents()
    model_contents = OrderedDict()
    model_contents["constraint"] = OrderedDict() #constraints
    model_contents["expression"] = OrderedDict() #expressions?
    model_contents["variable"] = OrderedDict() #variables?
    model_contents["gen_constraint"] = OrderedDict() #GenericConstraints
    model_contents["gen_expression"] = OrderedDict() #GenericConstraints
    model_contents["res_dir"] = ["res_up", "res_down"]
    return model_contents
end

# Sets up the tuples, variables, constraints, etc used in the model using smaller functions. These functions 
# aim to do only one thing, such as create a necessary tuple or create a variable base on a tuple.  
function setup_model(model_contents, input_data)
    resolve_delays(input_data)
    create_variables(model_contents, input_data)
    create_constraints(model_contents, input_data)
end



"""
    get_result_dataframe(model_contents,type="",process="",node="",scenario="")

Returns a dataframe containing specific information from the model?

# Arguments
- `model_contents::OrderedDict`: ?
- `type`: ?
- `process`: ?
- `node`: ?
- `scenario`: ?
"""
function get_result_dataframe(model_contents,type="",process="",node="",scenario="")
    println("Getting results for:")
    tuples = model_contents["tuple"]
    temporals = unique(map(x->x[5],tuples["process_tuple"]))
    df = DataFrame(t = temporals)
    vars = model_contents["variable"]
    if type == "v_flow"
        v_flow = vars[type]
        tups = unique(map(x->(x[1],x[2],x[3]),filter(x->x[1]==process, tuples["process_tuple"])))
        for tup in tups
            colname = join(tup,"-")
            col_tup = filter(x->x[1:3]==tup && x[4]==scenario, tuples["process_tuple"])
            if !isempty(col_tup)
                df[!, colname] = value.(v_flow[col_tup].data)
            end
        end
    elseif type == "v_reserve"
        v_res = vars[type]
        tups = unique(map(x->(x[1],x[2],x[3],x[5]),filter(x->x[3]==process, tuples["res_potential_tuple"])))
        for tup in tups
            col_name = join(tup,"-")
            col_tup = filter(x->(x[1],x[2],x[3],x[5])==tup && x[6]==scenario, tuples["res_potential_tuple"])
            if !isempty(col_tup)
                df[!, col_name] = value.(v_res[col_tup].data)
            end
        end
    elseif type == "v_res_final"
        v_res = vars[type]
        ress = unique(map(x->x[1],tuples["res_final_tuple"]))
        for r in ress
            col_tup = filter(x->x[1]==r && x[2]==scenario, tuples["res_final_tuple"])
            if !isempty(col_tup)
                df[!, r] = value.(v_res[col_tup].data)
            end
        end

    elseif type == "v_online" || type == "v_start" || type == "v_stop"
        v_bin = vars[type]
        procs = unique(map(x->x[1],tuples["process_tuple"]))
        for p in procs
            col_tup = filter(x->x[1]==p && x[2]==scenario, tuples["proc_online_tuple"])
            if !isempty(col_tup)
                df[!, p] = value.(v_bin[col_tup].data)
            end
        end
    elseif type == "v_state"
        v_state = vars[type]
        nods = unique(map(x->x[1],tuples["node_state_tuple"]))
        for n in nods
            col_tup = filter(x->x[1]==n && x[2]==scenario, tuples["node_state_tuple"])
            if !isempty(col_tup)
                df[!, n] = value.(v_state[col_tup].data)
            end
        end
    elseif type == "vq_state_up" || type == "vq_state_dw"
        v_state = vars[type]
        nods = unique(map(x->x[1],tuples["node_balance_tuple"]))
        for n in nods
            col_tup = filter(x->x[1]==n && x[2]==scenario, tuples["node_balance_tuple"])
            if !isempty(col_tup)
                df[!, n] = value.(v_state[col_tup].data)
            end
        end
    else
        println("ERROR: incorrect type")
    end
    return df
end

"""
    write_bid_matrix(model_contents::OrderedDict, input_data::OrderedDict)

Returns the bid matric generated by the model?
"""
function write_bid_matrix(model_contents::OrderedDict, input_data::Predicer.InputData)
    println("Writing bid matrix...")
    vars = model_contents["variable"]
    v_flow = vars["v_flow"]
    v_res_final = vars["v_res_final"]

    tuples = model_contents["tuple"]
    temporals = unique(map(x->x[5],tuples["process_tuple"]))
    markets = input_data.markets
    scenarios = keys(input_data.scenarios)

    if !isdir(pwd()*"\\results")
        mkdir("results")
    end
    output_path = string(pwd()) * "\\results\\bid_matrix_"*Dates.format(Dates.now(), "yyyy-mm-dd-HH-MM-SS")*".xlsx"
    XLSX.openxlsx(output_path, mode="w") do xf
        for (i,m) in enumerate(keys(markets))
            XLSX.addsheet!(xf, m)
            df = DataFrame(t = temporals)
            for s in scenarios
                p_name = "PRICE-"*s
                v_name = "VOLUME-"*s
                price = map(x->x[2],filter(x->x.scenario==s,markets[m].price)[1].series)
                if markets[m].type == "energy"
                    tup_b = filter(x->x[2]==m && x[4]==s,tuples["process_tuple"])
                    tup_s = filter(x->x[3]==m && x[4]==s,tuples["process_tuple"])
                    volume = value.(v_flow[tup_s].data)-value.(v_flow[tup_b].data)
                else
                    tup = filter(x->x[1]==m && x[2]==s,tuples["res_final_tuple"])
                    volume = value.(v_res_final[tup].data)
                end
                df[!,p_name] = price
                df[!,v_name] = volume
            end
            XLSX.writetable!(xf[i+1], collect(eachcol(df)), names(df))
        end
    end
end

"""
    export_model_contents(model_contents::OrderedDict, results::Bool)

Saves the contents of the model dict to an excel file.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function export_model_contents(model_contents::OrderedDict, results::Bool)
    if !isdir(pwd()*"\\results")
        mkdir("results")
    end
    output_path = string(pwd()) * "\\results\\model_contents_"*(results ? "results_" : "")*Dates.format(Dates.now(), "yyyy-mm-dd-HH-MM-SS")*".xlsx"
    XLSX.openxlsx(output_path, mode="w") do xf
        for (key_index, key1) in enumerate(collect(keys(model_contents)))
            XLSX.addsheet!(xf, string(key1))
            if key1 == "tuple"
                for (colnr, key2) in enumerate(collect(keys(model_contents[key1])))
                    xf[key_index+1][XLSX.CellRef(1, colnr)] = string(key2)
                    for (i, e) in enumerate(model_contents[key1][key2])
                        output = string(e)
                        xf[key_index+1][XLSX.CellRef(i+1, colnr)] = first(output, 32000)
                    end
                end

            elseif key1 == "expression"
                for (colnr, key2) in enumerate(collect(keys(model_contents[key1])))
                    xf[key_index+1][XLSX.CellRef(1, colnr)] = string(key2)
                    if typeof(model_contents[key1][key2]) == OrderedDict{Any, Any}
                        for (i, (key3, val3)) in enumerate(zip(keys(model_contents[key1][key2]), values(model_contents[key1][key2])))
                            if results
                                output = string(key3) * " : " * string(JuMP.value.(val3))
                                xf[key_index+1][XLSX.CellRef(i+1, colnr)] = first(output, 32000)
                            else
                                output = string(key3)*" : "*string(val3)
                                xf[key_index+1][XLSX.CellRef(i+1, colnr)] = first(output, 32000)
                            end
                        end
                    else
                        if results
                            output = string(key2) * " : " * string(JuMP.value.(model_contents[key1][key2]))
                            xf[key_index+1][XLSX.CellRef(1, colnr)] = first(output, 32000)
                        else
                            output = string(key2) * " : " * string(model_contents[key1][key2])
                            xf[key_index+1][XLSX.CellRef(1, colnr)] = first(output, 32000)
                        end
                    end
                end

            elseif key1 == "constraint"
                for (colnr, key2) in enumerate(collect(keys(model_contents[key1])))
                    xf[key_index+1][XLSX.CellRef(1, colnr)] = string(key2)
                    for (i, val) in enumerate(values(model_contents["model"].obj_dict[Symbol(key2)]))
                        if results
                            output = string(val) * " : " * string(JuMP.value.(val))
                            xf[key_index+1][XLSX.CellRef(i+1, colnr)] = first(output, 32000)
                        else
                            output = string(val)
                            xf[key_index+1][XLSX.CellRef(i+1, colnr)] = first(output, 32000)
                        end
                    end
                end

            elseif key1 == "variable"
                for (colnr, key2) in enumerate(collect(keys(model_contents[key1])))
                    xf[key_index+1][XLSX.CellRef(1, colnr)] = string(key2)
                    for (i, val) in enumerate(values(model_contents["model"].obj_dict[Symbol(key2)]))
                        if results
                            output = string(val) * " : " * string(JuMP.value.(val))
                            xf[key_index+1][XLSX.CellRef(i+1, colnr)] = first(output, 32000)
                        else
                            output = string(val)
                            xf[key_index+1][XLSX.CellRef(i+1, colnr)] = first(output, 32000)
                        end
                    end
                end
            elseif key1 == "gen_constraint"
                for (colnr, key2) in enumerate(collect(keys(model_contents[key1])))
                    xf[key_index+1][XLSX.CellRef(1, colnr)] = string(key2)

                    for (i, (key3,val3)) in enumerate(zip(keys(model_contents[key1][key2]), values(model_contents[key1][key2])))
                        if results
                            output = string(key3) * " : " * string(JuMP.value.(val3))
                            xf[key_index+1][XLSX.CellRef(i+1, colnr)] = first(output, 32000)
                        else
                            output = string(key3)*" : "*string(val3)
                            xf[key_index+1][XLSX.CellRef(i+1, colnr)] = first(output, 32000)
                        end
                    end
                end
            elseif key1 == "gen_expression"
                for (colnr, key2) in enumerate(collect(keys(model_contents[key1])))
                    xf[key_index+1][XLSX.CellRef(1, colnr)] = string(key2)
                    for (i, (key3, val3)) in enumerate(zip(keys(model_contents[key1][key2]), values(model_contents[key1][key2])))
                        if results
                            output = string(key3) * " : " * string(JuMP.value.(val3))
                            xf[key_index+1][XLSX.CellRef(i+1, colnr)] = first(output, 32000)
                        else
                            output = string(key3)*" : "*string(val3)
                            xf[key_index+1][XLSX.CellRef(i+1, colnr)] = first(output, 32000)
                        end
                    end
                end
            end
        end
    end
end

function resolve_delays(input_data::Predicer.InputData)
    processes = input_data.processes
    processes_to_add = []
    nodes_to_add = []
    highest_delay = 0
    for p in keys(processes)
        delay_topos = filter(t -> t.delay > 0, processes[p].topos)
        if !isempty(delay_topos)
            for topo in delay_topos
                highest_delay = max(topo.delay, highest_delay)
                if processes[p].conversion == 2 # transfer process
                    Predicer.add_delay(processes[p], topo.delay)
                    topo.delay = 0
                elseif processes[p].conversion == 1 # unit based process
                    # create node
                    delay_n_name = "delayNode_" * processes[p].name * "_" * topo.source * "_to_" * topo.sink
                    dn = Node(delay_n_name)
                    push!(nodes_to_add, dn)

                    # create transfer process
                    delay_p_name = "delayProcess_" * processes[p].name * "_" * topo.source * "_to_" * topo.sink
                    dp = TransferProcess(delay_p_name, topo.delay)
                    add_eff(dp, 1.0)
                    add_load_limits(dp, 0.0, 1.0)

                    # add topos to new delay/transport process
                    # - if topo is a sink of p, add the delay node after p
                    # - if topo is a source of p, add the delay node before p
                    if topo.source == processes[p].name # The topo is a sink, as it goes from the process, 
                        add_topology(dp, Topology(delay_n_name, topo.sink, topo.capacity, 0.0, 1.0, 1.0, 0.0))

                    elseif topo.sink == processes[p].name
                        add_topology(dp, Topology(topo.source, delay_n_name, topo.capacity, 0.0, 1.0, 1.0, 0.0))
                    end
                    push!(processes_to_add, dp)

                    # change p topos depending on if it is a so or si. 
                    # - delay node as so if topo is a so
                    # - delay node as si if topo is a sink
                    if topo.source == processes[p].name
                        for t in processes[p].topos
                            if t == topo
                                t.sink = delay_n_name
                                t.delay = 0
                            end
                        end
                    else
                        for t in processes[p].topos
                            if t == topo
                                t.source = delay_n_name
                                t.delay = 0
                            end
                        end
                    end
                    # manage "history" of original nodes.
                end
            end
        end
    end
    for p in processes_to_add
        input_data.processes[p.name] = p
    end
    for n in nodes_to_add
        input_data.nodes[n.name] = n
    end
    return input_data
end