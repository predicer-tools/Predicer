using JuMP
using Cbc
using DataFrames
using TimeZones
using Dates
using DataStructures
using XLSX

"""
    get_costs_dataframe(model_contents::OrderedDict, input_data::InputData, costs::Vector{String}, scenario::Vector{String})

Returns a dataframe containing all the costs related to the model. 

# Arguments
- `model_contents::OrderedDict`: Model contents dict.
- `input_data::Predicer.InputData`: Input data used in model.
- `costs::Vector{String}`: Type of cost(s) to show, such as 'commodity_costs' or 'total_costs'. If empty, return all relevant costs. 
- `scenario::Vector{String}`: The name of the scenario for which the value is to be shown. If left empty, return all relevant values. 
"""
function get_costs_dataframe(model_contents::OrderedDict, input_data::InputData, costs::Vector{String}=String[], scenario::Vector{String}=String[])
    if isempty(costs)
        costs = ["commodity_costs", "dummy_costs", "market_costs", "reserve_costs", "total_costs", "setpoint_deviation_costs", "start_costs", "state_residue_costs", "vom_costs"]
    end
    t_start = input_data.temporals.t[begin]
    t_end = input_data.temporals.t[end]
    df = DataFrame([[t_start], [t_end]], ["t_start", "t_end"])
    es = model_contents["expression"]
    if isempty(scenario)
        scens = Predicer.scenarios(input_data)
    else
        scens = scenario
    end
    for cost in costs
        for s in scens
            
            colname = cost * "_" * s
            df[!, colname] = [JuMP.value(es[cost][s])]
        end
    end
    return df
end


"""
    get_costs_dataframe(model_contents::OrderedDict, input_data::InputData, costs::String, scenario::String)

Returns a dataframe containing all the costs related to the model. 

# Arguments
- `model_contents::OrderedDict`: Model contents dict.
- `input_data::Predicer.InputData`: Input data used in model.
- `costs::String`: Type of cost(s) to show, such as 'commodity_costs' or 'total_costs'. If empty, return all relevant costs. 
- `scenario::String`: The name of the scenario for which the value is to be shown. If left empty, return all relevant values. 
"""
function get_costs_dataframe(model_contents::OrderedDict, input_data::InputData, costs::String, scenario::String)
    if isempty(costs)
        cs = String[]
    else
        cs = String[costs]
    end
    if isempty(scenario)
        ss = String[]
    else
        ss = String[scenario]
    end
    return get_costs_dataframe(model_contents, input_data, cs, ss)
end


"""
    get_node_balance(model_contents::OrderedDict, input_data::InputData, nodename::String, scenario::String)

Function to retrieve a DataFrame containing the balance of a specific node; i.e. all flows in and out of the node.

# Arguments
- `model_contents::OrderedDict`: Model contents dict.
- `input_data::Predicer.InputData`: Input data used in model.
- `nodename::String`: Name of the node to be studied. 
- `scenario::String`: Name of the scenario to be studied. 
"""
function get_node_balance(model_contents::OrderedDict, input_data::InputData, nodename::String, scenario::String)
    df = DataFrame(t=input_data.temporals.t)
    # inflow
    if input_data.nodes[nodename].is_inflow
        inflow_vals = map(x -> x[2], input_data.nodes[nodename].inflow(scenario).series)
    else
        inflow_vals = zeros(length(input_data.temporals.t))
    end
    df[!, "inflow"] = inflow_vals
    # state
    if input_data.nodes[nodename].is_state
        node_tups = filter(x -> x[1] == nodename && x[2] == scenario, state_node_tuples(input_data))
        state_vals = JuMP.value.(model.obj_dict[:v_state][node_tups]).data
        state_diff_vals = []
        for (i, sv) in enumerate(state_vals)
            if i == 1
                push!(state_diff_vals, state_vals[i] - input_data.nodes[nodename].state.initial_state)
            else
                push!(state_diff_vals, state_vals[i] - state_vals[i-1])
            end
        end
    else
        state_diff_vals = zeros(length(input_data.temporals.t))
    end
    df[!, "state_diff"] = state_diff_vals
    # diffusion
    if nodename in diffusion_nodes(input_data)
        node_diff_tups = filter(x -> x[1] == nodename && x[2] == scenario, node_diffusion_tuple(input_data))
        node_diff_e = model_contents["model"].obj_dict[:e_node_bal_eq_diffusion]
        node_diff_vals = map(x -> JuMP.value.(node_diff_e[x]), node_diff_tups)
    else
        node_diff_vals = zeros(length(input_data.temporals.t))
    end
    df[!, "node_diff"] = node_diff_vals
    # delay
    if nodename in Predicer.delay_nodes(input_data)
        delay_tups = filter(x -> x[1] == nodename && x[2] == scenario, balance_node_tuples(input_data))
        node_delay_e = model_contents["expression"]["e_node_delay"]
        node_delay_vals = map(x -> JuMP.value.(node_delay_e[x]), delay_tups)
    else
        node_delay_vals = zeros(length(input_data.temporals.t))
    end
    df[!, "node_delay"] = node_delay_vals
    # producer processes
    prod_tups = unique(map(y -> y[1:4], filter(x -> x[3] == nodename && x[4] == scenario, process_topology_tuples(input_data))))
    for pt in prod_tups
        colname = pt[1] * "_" * pt[2] * "_" * pt[3]
        tups = filter(x -> x[1:4] == pt, process_topology_tuples(input_data))
        df[!, colname] = JuMP.value.(model.obj_dict[:v_flow][tups]).data
    end
    # consumer processes
    cons_tups = unique(map(y -> y[1:4], filter(x -> x[2] == nodename && x[4] == scenario, process_topology_tuples(input_data))))
    for ct in cons_tups
        colname = ct[1] * "_" * ct[2] * "_" * ct[3]
        tups = filter(x -> x[1:4] == ct, process_topology_tuples(input_data))
        df[!, colname] = -1 .* JuMP.value.(model.obj_dict[:v_flow][tups]).data
    end
    return df
end


"""
    get_process_balance(model_contents::OrderedDict, input_data::InputData, procname::String, scenario::String)

Function to retrieve a DataFrame containing the balance of a specific process; i.e. all flows in and out of the node, as well as the efficiency losses.

# Arguments
- `model_contents::OrderedDict`: Model contents dict.
- `input_data::Predicer.InputData`: Input data used in model.
- `procname::String`: Name of the process to be studied. 
- `scenario::String`: Name of the scenario to be studied. 
"""
function get_process_balance(model_contents::OrderedDict, input_data::InputData, procname::String, scenario::String="")
    df = DataFrame(t=input_data.temporals.t)

    # producing flows
    prod_flows = unique(map(y -> y[1:4], filter(x -> x[1] == procname && x[3] == procname && x[4] == scenario, process_topology_tuples(input_data))))
    for pf in prod_flows
        colname = pf[1] * "_" * pf[2] * "_" * pf[3]
        tups = filter(x -> x[1:4] == pf, process_topology_tuples(input_data))
        df[!, colname] = JuMP.value.(model.obj_dict[:v_flow][tups]).data
    end

    # consuming flows
    cons_flows = unique(map(y -> y[1:4], filter(x -> x[1] == procname && x[2] == procname && x[4] == scenario, process_topology_tuples(input_data))))
    for cf in cons_flows
        colname = cf[1] * "_" * cf[2] * "_" * cf[3]
        tups = filter(x -> x[1:4] == cf, process_topology_tuples(input_data))
        df[!, colname] = -1.0 .*JuMP.value.(model.obj_dict[:v_flow][tups]).data
    end

    # efficiency losses are incoming - outcoming
    df[!, "eff_losses"] = map(x -> -sum(x[2:end]), eachrow(df))
    return df
end


"""
    get_result_dataframe(model_contents::OrderedDict, input_data::Predicer.InputData, type::String="", name::String="",scenario::String="")

Returns a dataframe containing specific information for a variable in the model.

# Arguments
- `model_contents::OrderedDict`: Model contents dict.
- `input_data::Predicer.InputData`: Input data used in model.
- `type::String`: Type of variable to show, such as 'v_flow' or 'v_state'.
- `name::String`: The name of the entity (process, node, block,) connected to the variable. If left empty, return all relevant values. 
- `scenario::String`: The name of the scenario for which the value is to be shown. If left empty, return all relevant values. 
"""
function get_result_dataframe(model_contents::OrderedDict, input_data::Predicer.InputData, e_type::String="", name::String="",scenario::String="")
    model = model_contents["model"]
    tuples = Predicer.create_tuples(input_data)
    temporals = input_data.temporals.t
    df = DataFrame(t = temporals)
    expr = model_contents["expression"]
    if !isempty(scenario)
        scenarios = [scenario]
    else
        scenarios = collect(keys(input_data.scenarios))
    end
    if e_type == "v_flow"
        v_flow = model.obj_dict[Symbol(e_type)]
        if !isempty(name)
            tups = unique(map(x->(x[1],x[2],x[3]),filter(x->x[1]==name, tuples["process_tuple"])))
        else
            tups = unique(map(x->(x[1],x[2],x[3]), tuples["process_tuple"]))
        end
        for tup in tups, s in scenarios
            colname = join(tup,"_") * "_" *s
            col_tup = filter(x->x[1:3]==tup && x[4]==s, tuples["process_tuple"])
            if !isempty(col_tup)
                df[!, colname] = value.(v_flow[validate_tuples(model_contents, col_tup, 4)].data)
            end
        end
    elseif e_type == "v_load"
        if input_data.setup.contains_reserves
            v_load = model.obj_dict[Symbol(e_type)]
            if !isempty(name)
                tups = unique(map(x->(x[1],x[2],x[3]),filter(x->x[1]==name, unique(map(x -> (x[3:end]), tuples["res_potential_tuple"])))))
            else
                tups = unique(map(x->(x[1],x[2],x[3]), unique(map(x -> (x[3:end]), tuples["res_potential_tuple"]))))
            end
            for tup in tups, s in scenarios
                colname = join(tup,"_") * "_" *s
                col_tup = filter(x->x[1:3]==tup && x[4]==s, unique(map(x -> (x[3:end]), tuples["res_potential_tuple"])))
                if !isempty(col_tup)
                    df[!, colname] = value.(v_load[validate_tuples(model_contents, col_tup, 4)].data)
                end
            end
        end
    elseif e_type == "v_reserve"
        if input_data.setup.contains_reserves
            v_res = model.obj_dict[Symbol(e_type)]
            if !isempty(name)
                tups = unique(map(x->(x[1],x[2],x[3],x[5]),filter(x->x[3]==name, tuples["res_potential_tuple"])))
            else
                tups = unique(map(x->(x[1],x[2],x[3],x[5]),tuples["res_potential_tuple"]))
            end
            for tup in tups, s in scenarios
                col_name = join(tup,"_")  * "_" *s
                col_tup = filter(x->(x[1],x[2],x[3],x[5])==tup && x[6]==s, tuples["res_potential_tuple"])
                if !isempty(col_tup)
                    df[!, col_name] = value.(v_res[validate_tuples(model_contents, col_tup, 6)].data)
                end
            end
        end
    elseif e_type == "v_res_final"
        if input_data.setup.contains_reserves
            v_res = model.obj_dict[Symbol(e_type)]
            ress = unique(map(x->x[1],tuples["res_final_tuple"]))
            for r in ress, s in scenarios
                colname = r * "_" * s
                col_tup = filter(x->x[1]==r && x[2]==s, tuples["res_final_tuple"])
                if !isempty(col_tup)
                    df[!, colname] = value.(v_res[validate_tuples(model_contents, col_tup, 2)].data)
                end
            end
        end
    elseif e_type == "v_online" || e_type == "v_start" || e_type == "v_stop"
        if input_data.setup.contains_online
            v_bin = model.obj_dict[Symbol(e_type)]
            if !isempty(name)
                procs = unique(map(x->x[1],filter(y ->y[1] == name, tuples["process_tuple"])))
            else
                procs = unique(map(x->x[1],tuples["process_tuple"]))
            end
            for p in procs, s in scenarios
                col_tup = filter(x->x[1]==p && x[2]==s, tuples["proc_online_tuple"])
                colname = p * "_" * s
                if !isempty(col_tup)
                    df[!, colname] = value.(v_bin[validate_tuples(model_contents, col_tup, 2)].data)
                end
            end
        end
    elseif e_type == "v_state"
        if input_data.setup.contains_states
            v_state = model.obj_dict[Symbol(e_type)]
            if !isempty(name)
                nods = map(y -> y[1], filter(x->x[1]==name, tuples["node_state_tuple"]))
            else
                nods = map(y -> y[1] , tuples["node_state_tuple"])
            end
            for n in nods, s in scenarios
                col_tup = filter(x -> x[1] == n && x[2] == s, tuples["node_state_tuple"])
                colname = n * "_" * s
                if !isempty(col_tup)
                    df[!, colname] = value.(v_state[validate_tuples(model_contents, col_tup, 2)].data)
                end
            end
        end
    elseif e_type == "vq_state_up" || e_type == "vq_state_dw"
        if input_data.setup.use_node_dummy_variables
            v_state = model.obj_dict[Symbol(e_type)]
            if !isempty(name)
                nods = unique(map(x->x[1],filter(y -> y[1] == name, tuples["node_balance_tuple"])))
            else
                nods = unique(map(x->x[1],tuples["node_balance_tuple"]))
            end
            for n in nods, s in scenarios
                col_tup = filter(x->x[1]==n && x[2]==s, tuples["node_balance_tuple"])
                colname = n * "_" * s
                if !isempty(col_tup)
                    df[!, colname] = value.(v_state[validate_tuples(model_contents, col_tup, 2)].data)
                end
            end
        end
    elseif e_type == "vq_ramp_up" || e_type == "vq_ramp_dw"
        if input_data.setup.use_ramp_dummy_variables
            v_ramp = model.obj_dict[Symbol(e_type)]
            if !isempty(name)
                procs = unique(map(x->(x[1:3]),filter(y -> y[1] == name, tuples["ramp_tuple"])))
            else
                procs = unique(map(x->(x[1:3]),tuples["ramp_tuple"]))
            end
            for p in procs, s in scenarios
                col_tup = filter(x->x[1:3] == p && x[4]==s, tuples["ramp_tuple"])
                colname = p[1] * "_" * p[2] * "_" * p[3] * "_" * s
                if !isempty(col_tup)
                    df[!, colname] = value.(v_ramp[validate_tuples(model_contents, col_tup, 4)].data)
                end
            end
        end
    elseif e_type == "v_bid"
        v_bid = expr[e_type]
        if !isempty(name)
            bid_tups = unique(map(x->(x[1]),filter(x->x[1]==name,tuples["balance_market_tuple"])))
        else
            bid_tups = map(x->(x[1]),tuples["balance_market_tuple"])
        end
        for bt in bid_tups, s in scenarios
            col_tup = unique(map(x->(x[1],x[3],x[4]),filter(x->x[1]==bt && x[3]==s,tuples["balance_market_tuple"])))
            if !isempty(col_tup)
                dat_vec = []
                colname = col_tup[1][1] * "_" * s
                for tup in col_tup
                    push!(dat_vec,value(v_bid[tup]))
                end
                df[!,colname] = dat_vec
            end
        end
    elseif e_type == "v_bid_volume"
        v_bid_vol = model.obj_dict[Symbol(e_type)]
        if !isempty(name)
            bid_vol_tups = unique(map(x -> (x[1], x[2]), filter(y -> y[1] == name, tuples["bid_slot_tuple"])))
        else
            bid_vol_tups = unique(map(x ->(x[1], x[2]), tuples["bid_slot_tuple"]))
        end
        for bvt in bid_vol_tups
            dat_vec = []
            colname = bvt[1] * ", " * bvt[2]
            for tup in tuples["bid_slot_tuple"]
                if tup[2] == bvt[2] && tup[1] == bvt[1]
                    push!(dat_vec, JuMP.value.(v_bid_vol[tup]))
                end
            end
            df[!,colname] = dat_vec
        end
    elseif e_type == "v_flow_bal"
        v_bal = model.obj_dict[Symbol(e_type)]
        if !isempty(name)
            nods = unique(map(y -> y[1], filter(x->x[1]==name, tuples["balance_market_tuple"])))
        else
            nods = unique(map(y -> y[1], tuples["balance_market_tuple"]))
        end
        dir = ["up","dw"]
        for n in nods, d in dir, s in scenarios
            col_tup = filter(x->x[1]==n && x[2]==d && x[3]==s, tuples["balance_market_tuple"])
            colname = n * "_" * d * "_" * s
            if !isempty(col_tup)
                df[!,colname] = value.(v_bal[validate_tuples(model_contents, col_tup, 3)].data)
            end
        end
    elseif e_type == "v_block"
        df = DataFrame()
        v_block = model.obj_dict[Symbol(e_type)]
        if !isempty(name)
            blocks = unique(map(y -> (y[1], y[2], y[3]), filter(x -> x[1] == name, tuples["block_tuples"])))
        else
            blocks = unique(map(x -> (x[1], x[2], x[3]), tuples["block_tuples"]))
        end
        for block in blocks
            colname = block[1] * "_" * block[2] * "_" * block[3]
            b_tup = (block..., input_data.inflow_blocks[block[1]].start_time)
            df[!, colname] = [JuMP.value.(v_block[validate_tuple(model_contents, b_tup, 3)[begin:3]])]
        end
    elseif e_type == "v_setpoint" || e_type == "v_set_up" || e_type == "v_set_down"
        v_var = model.obj_dict[Symbol(e_type)]
        if !isempty(name)
            setpoints = unique(map(x -> x[1], filter(y -> y[1] == name, tuples["setpoint_tuples"])))
        else
            setpoints = unique(map(x -> x[1], tuples["setpoint_tuples"]))
        end
        for sp in setpoints, s in scenarios
            col_tup = filter(x -> x[1] == sp && x[2] == s, tuples["setpoint_tuples"])
            if e_type == "v_set_up"
                colname = "up_" * sp * "_" * s
            elseif e_type == "v_set_down"
                colname = "down_" *  sp * "_" * s
            elseif e_type == "v_setpoint"
                colname = sp * "_" * s
            end
            if !isempty(col_tup)
                df[!,colname] = value.(v_var[validate_tuples(model_contents, col_tup, 2)].data)
            end
        end
    elseif e_type == "v_reserve_online"
        if input_data.setup.contains_reserves
            v_reserve_online = model.obj_dict[Symbol(e_type)]
            if !isempty(name)
                ress = unique(map(y -> y[1], filter(x -> x[1] == name, tuples["reserve_limits"])))
            else
                ress = unique(map(y -> y[1], tuples["reserve_limits"]))
            end
            for r in ress, s in scenarios
                col_tup = filter(x -> x[1] == r && x[2] == s, tuples["reserve_limits"])
                colname = r * "_" * s
                if !isempty(col_tup)
                    df[!,colname] = value.(v_reserve_online[validate_tuples(model_contents, col_tup, 2)].data)
                end
            end
        end
    elseif e_type == "v_node_diffusion" # only returns an expression with node diff info, no variable. 
        if input_data.setup.contains_diffusion
            node_diffs = model_contents["model"].obj_dict[:e_node_bal_eq_diffusion]
            if isempty(name)
                nodenames = unique(map(y -> y[1], map(x -> x.I[1], collect(keys(node_diffs)))))
            else
                nodenames = unique(map(y -> y[1], filter(x -> x[1] == name, map(x -> x.I[1], collect(keys(node_diffs))))))
            end
            for n in nodenames, s in scenarios
                diffs = []
                colname = n * "_" * s
                for t in input_data.temporals.t
                    diff_k = filter(x -> x == (n, s, t),  map(x -> x.I[1], collect(keys(node_diffs))))[1]
                    push!(diffs, value.(node_diffs[diff_k]))
                end
                if !isempty(diffs)
                    df[!, colname] = diffs
                end
            end
        end
    elseif e_type == "v_node_delay"
        if input_data.setup.contains_delay
            v_node_delays = model.obj_dict[:v_node_delay]
            if isempty(name)
                conn_names = unique(map(x -> (x[1], x[2]), node_delay_tuple(input_data)))
            else
                conn_names = unique(filter(y -> name in y, map(x -> (x[1], x[2]), node_delay_tuple(input_data))))
            end
            for c in conn_names, s in scenarios
                d_conn = filter(x -> x[1] == c[1] && x[2] == c[2] && x[3] == s, node_delay_tuple(input_data))
                colname = c[1] * "_" * c[2] * "_" * s
                if !isempty(d_conn)
                    df[!, colname] = value.(v_node_delays[d_conn].data)
                end
            end
        end
    else
        println("ERROR: incorrect type")
    end
    return df
end
 
"""
    get_all_result_dataframes(model_contents::OrderedDict, input_data::InputData, scenario="", name="")

Collect all of the available variable results into DataFrames collected in a dictionary. 
"""
function get_all_result_dataframes(model_contents::OrderedDict, input_data::InputData, scenario="", name="")
    dfs = Dict()
    e_types = ["v_flow", "v_load", "v_reserve", "v_res_final", "v_online", "v_start", "v_stop", "v_state", "vq_state_up", "vq_state_dw", "v_bid", "v_bid_volume",
        "vq_ramp_up", "vq_ramp_dw", "v_flow_bal", "v_block", "v_setpoint", "v_set_up", "v_set_down", "v_reserve_online", "v_node_diffusion", "v_node_delay"]
    for e_type in e_types
        dfs[e_type] = Predicer.get_result_dataframe(model_contents, input_data, e_type, name, scenario)
    end
    return dfs
end


"""
    write_bid_matrix(model_contents::OrderedDict, input_data::OrderedDict)

Outputs the bid matrix generated by the model. The matrix is output into an excel-file in the "results" folder. 

# Arguments
- `model_contents::OrderedDict`: Model contents dict.
- `input_data::InputData`: Model input data. 
"""
function write_bid_matrix(model_contents::OrderedDict, input_data::Predicer.InputData)
    println("Writing bid matrix...")
    vars = model_contents["model"].obj_dict
    v_bid = model_contents["expression"]["v_bid"]
    if input_data.setup.contains_reserves
        v_res_final = vars[Symbol("v_res_final")]
    end

    tuples = Predicer.create_tuples(input_data)
    temporals = input_data.temporals.t
    markets = input_data.markets
    scenarios = collect(keys(input_data.scenarios))

    dfs = Dict()

    if !isdir("results")
        mkdir("results")
    end
    date = Dates.format(Dates.now(), "yyyy-mm-dd-HH-MM-SS")
    output_path = joinpath("results", "bid_matrix_$date.xlsx")
    XLSX.openxlsx(output_path, mode="w") do xf
        for (i,m) in enumerate(keys(markets))
            XLSX.addsheet!(xf, m)
            df = DataFrame(t = temporals)
            for s in scenarios
                p_name = "PRICE-"*s
                v_name = "VOLUME-"*s
                price = map(t -> markets[m].price(s, t),temporals)
                if markets[m].m_type == "energy"
                    bid_tuple = unique(map(x->(x[1],x[3],x[4]),filter(x->x[1]==m && x[3]==s,tuples["balance_market_tuple"])))
                    volume = []
                    for tup in bid_tuple
                        push!(volume,value(v_bid[tup]))
                    end
                else
                    if input_data.setup.contains_reserves
                        tup = filter(x->x[1]==m && x[2]==s,tuples["res_final_tuple"])
                        volume = value.(v_res_final[tup].data)
                    end
                end
                df[!,p_name] = price
                df[!,v_name] = volume
            end
            XLSX.writetable!(xf[i+1], collect(eachcol(df)), names(df))
            dfs[m] = df
        end
    end
    return dfs
end

"""
    dfs_to_xlsx(df::DataFrame, fpath::String, fname::String="")

Function to export a DataFrame to an xlsx file. 

# Arguments
- `dfs::DataFrame`: Dataframes 
- `fpath::String`: Path to the folder where the xlsx file is to be stored. 
- `fname::String`: Name of the xlsx file. (a suffix of date, time, and ".xlsx" are added automatically)
"""
function dfs_to_xlsx(df::DataFrame, fpath::String, fname::String="")
    output_path = joinpath(fpath, fname * "_" * Dates.format(Dates.now(), "yyyy-mm-dd-HH-MM-SS")*".xlsx")
    XLSX.openxlsx(output_path, mode="w") do xf
        XLSX.addsheet!(xf, "df")
        XLSX.writetable!(xf[2], collect(eachcol(df)), names(df))
    end
    return output_path
end


"""
    dfs_to_xlsx(dfs::Dict{String, DataFrame}, fpath::String, fname::String="")

Function to export a dictionary containing DataFrames to an xlsx file. 

# Arguments
- `dfs::Dict{String, DataFrame}`: Dictionary containing dataframes. The key should be a string. 
- `fpath::String`: Path to the folder where the xlsx file is to be stored. 
- `fname::String`: Name of the xlsx file. (a suffix of date, time, and ".xlsx" are added automatically)
"""
function dfs_to_xlsx(dfs::Dict{Any, Any}, fpath::String, fname::String="")
    output_path = joinpath(fpath, fname * "_" * Dates.format(Dates.now(), "yyyy-mm-dd-HH-MM-SS")*".xlsx")
    XLSX.openxlsx(output_path, mode="w") do xf
        for (i, sn) in enumerate(collect(keys(dfs)))
            XLSX.addsheet!(xf, sn)
            if !isempty(dfs[sn])
                XLSX.writetable!(xf[i+1], collect(eachcol(dfs[sn])), names(dfs[sn]))
            end
        end
    end
    return output_path
end


"""
    resolve_market_nodes(input_data::InputData) 

Function to construct market nodes based on the input data
"""
function resolve_market_nodes(input_data::InputData)
    markets = input_data.markets
    for m in collect(keys(markets))
        if markets[m].m_type == "energy"
            node_name = m
            input_data.nodes[node_name] = Predicer.Node(node_name, false, true)
            pname = markets[m].node * "_" * m * "_trade_process"
            market_p = Predicer.MarketProcess(pname)
            Predicer.add_topology(market_p, Predicer.Topology(markets[m].node, node_name, 0.0, 0.00001, 1.0, 1.0, 1.0, 1.0))
            Predicer.add_topology(market_p, Predicer.Topology(node_name, markets[m].node, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0))
            input_data.processes[pname] = market_p
        end
    end
    return input_data
end


"""
    predicer_graph(input_data::Input_data)

Function to collect the Predicer model structure into a form, which can be used to generate a figure of the model structure. 
"""
function predicer_graph(input_data::InputData)
    graph = Dict()
    graph["nodes"] = Dict()
    graph["processes"] = Dict()
    connections = []

    for n in collect(keys(input_data.nodes))
        graph["nodes"][n] = Dict()
        graph["nodes"][n]["type"] = "node"       
        properties = String[]
        input_data.nodes[n].is_inflow ? push!(properties, "Inflow") : nothing
        input_data.nodes[n].is_commodity ? push!(properties, "Commodity") : nothing
        input_data.nodes[n].is_state ? push!(properties, "Storage") : nothing
        input_data.nodes[n].is_market ? push!(properties, "Market") : nothing
        input_data.nodes[n].is_res ? push!(properties, "Reserve") : nothing
        graph["nodes"][n]["properties"] = properties
    end
    for p in collect(keys(input_data.processes))
        graph["processes"][p] = Dict()
        graph["processes"][p]["type"] = "process"
        properties = String[]
        input_data.processes[p].is_online ? push!(properties, "Online") : nothing
        input_data.processes[p].is_cf ? push!(properties, "Cf") : nothing
        input_data.processes[p].is_res ? push!(properties, "Reserve") : nothing
        graph["processes"][p]["properties"] = properties
        for topo in input_data.processes[p].topos
            push!(connections, (topo.source, p))
            push!(connections, (p, topo.sink))
        end
    end
    graph["connections"] = unique(filter(x -> x[1] != x[2], connections))
    graph["diffusion"] = unique(filter(x -> x[1] != x[2], map(y -> [y.node1, y.node2], input_data.node_diffusion)))
    graph["delay"] = unique(filter(x -> x[1] != x[2], map(y -> y[1:2], input_data.node_delay)))
    return graph
end


"""
    function generate_mermaid_diagram(graph::Dict)

Function to build a string which can be used to generate flowcharts using mermaid.
"""
function generate_mermaid_diagram(graph::Dict)
    d = "```\nflowchart LR\n"
    for n in collect(keys(graph["nodes"]))
        d *= n * "((" * n * "))\n"
    end
    for p in collect(keys(graph["processes"]))
        d *= p * "[" * p * "]\n"
    end
    for e in graph["connections"]
        d *= e[1] * " --> " * e[2] * "\n"
    end
    for del in graph["delay"]
        d *= del[1] * " -.-> " * del[2] * "\n"
    end
    for diff in graph["diffusion"]
        d *= diff[1] * " -.-> " * diff[2] * "\n"
    end
    #for n in collect(keys(graph["nodes"]))
    #    for prop in graph["nodes"][n]["properties"]
    #        d *= n * " ~~~|\"" * prop * "\" |" * n * "\n"
    #    end
    #end
    d *= "\n```"
end
