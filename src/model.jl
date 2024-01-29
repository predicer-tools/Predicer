using JuMP
using Cbc
using DataFrames
using TimeZones
using Dates
using DataStructures
using XLSX

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
function get_result_dataframe(model_contents::OrderedDict, input_data::Predicer.InputData, type::String="", name::String="",scenario::String="")
    tuples = Predicer.create_tuples(input_data)
    temporals = input_data.temporals.t
    df = DataFrame(t = temporals)
    vars = model_contents["variable"]
    expr = model_contents["expression"]
    if !isempty(scenario)
        scenarios = [scenario]
    else
        scenarios = collect(keys(input_data.scenarios))
    end
    if type == "v_flow"
        v_flow = vars[type]
        if !isempty(name)
            tups = unique(map(x->(x[1],x[2],x[3]),filter(x->x[1]==name, vcat(tuples["process_tuple"], tuples["delay_tuple"]))))
        else
            tups = unique(map(x->(x[1],x[2],x[3]), vcat(tuples["process_tuple"], tuples["delay_tuple"])))
        end
        for tup in tups, s in scenarios
            colname = join(tup,"_") * "_" *s
            col_tup = filter(x->x[1:3]==tup && x[4]==s, vcat(tuples["process_tuple"], tuples["delay_tuple"]))
            if !isempty(col_tup)
                df[!, colname] = value.(v_flow[col_tup].data)
            end
        end
    elseif type == "v_load"
        v_load = vars[type]
        if !isempty(name)
            tups = unique(map(x->(x[1],x[2],x[3]),filter(x->x[1]==name, unique(map(x -> (x[3:end]), tuples["res_potential_tuple"])))))
        else
            tups = unique(map(x->(x[1],x[2],x[3]), unique(map(x -> (x[3:end]), tuples["res_potential_tuple"]))))
        end
        for tup in tups, s in scenarios
            colname = join(tup,"_") * "_" *s
            col_tup = filter(x->x[1:3]==tup && x[4]==s, unique(map(x -> (x[3:end]), tuples["res_potential_tuple"])))
            if !isempty(col_tup)
                df[!, colname] = value.(v_load[col_tup].data)
            end
        end
    elseif type == "v_reserve"
        v_res = vars[type]
        if !isempty(name)
            tups = unique(map(x->(x[1],x[2],x[3],x[5]),filter(x->x[3]==name, tuples["res_potential_tuple"])))
        else
            tups = unique(map(x->(x[1],x[2],x[3],x[5]),tuples["res_potential_tuple"]))
        end
        for tup in tups, s in scenarios
            col_name = join(tup,"_")  * "_" *s
            col_tup = filter(x->(x[1],x[2],x[3],x[5])==tup && x[6]==s, tuples["res_potential_tuple"])
            if !isempty(col_tup)
                df[!, col_name] = value.(v_res[col_tup].data)
            end
        end
    elseif type == "v_res_final"
        v_res = vars[type]
        ress = unique(map(x->x[1],tuples["res_final_tuple"]))
        for r in ress, s in scenarios
            colname = r * "_" * s
            col_tup = filter(x->x[1]==r && x[2]==s, tuples["res_final_tuple"])
            if !isempty(col_tup)
                df[!, colname] = value.(v_res[col_tup].data)
            end
        end
    elseif type == "v_online" || type == "v_start" || type == "v_stop"
        v_bin = vars[type]
        if !isempty(name)
            procs = unique(map(x->x[1],filter(y ->y[1] == name, tuples["process_tuple"])))
        else
            procs = unique(map(x->x[1],tuples["process_tuple"]))
        end
        for p in procs, s in scenarios
            col_tup = filter(x->x[1]==p && x[2]==s, tuples["proc_online_tuple"])
            colname = p * "_" * s
            if !isempty(col_tup)
                df[!, colname] = value.(v_bin[col_tup].data)
            end
        end
    elseif type == "v_state"
        v_state = vars[type]
        if !isempty(name)
            nods = map(y -> y[1], filter(x->x[1]==name, tuples["node_state_tuple"]))
        else
            nods = map(y -> y[1] , tuples["node_state_tuple"])
        end
        for n in nods, s in scenarios
            col_tup = filter(x -> x[1] == n && x[2] == s, tuples["node_state_tuple"])
            colname = n * "_" * s
            if !isempty(col_tup)
                df[!, colname] = value.(v_state[col_tup].data)
            end
        end
    elseif type == "vq_state_up" || type == "vq_state_dw"
        v_state = vars[type]
        if !isempty(name)
            nods = unique(map(x->x[1],filter(y -> y[1] == name, tuples["node_balance_tuple"])))
        else
            nods = unique(map(x->x[1],tuples["node_balance_tuple"]))
        end
        for n in nods, s in scenarios
            col_tup = filter(x->x[1]==n && x[2]==s, tuples["node_balance_tuple"])
            colname = n * "_" * s
            if !isempty(col_tup)
                df[!, colname] = value.(v_state[col_tup].data)
            end
        end
    elseif type == "v_bid"
        v_bid = expr[type]
        if !isempty(name)
            bid_tups = map(x->(x[1]),filter(x->x[1]==name,tuples["balance_market_tuple"]))
        else
            bid_tups = map(x->(x[1]),tuples["balance_market_tuple"])
        end
        for bt in bid_tups, s in scenarios
            col_tup = unique(map(x->(x[1],x[3],x[4]),filter(x->x[1]==bt && x[3]==s,tuples["balance_market_tuple"])))
            if !isempty(col_tup)
                dat_vec = []
                colname = name * "_" * s
                for tup in col_tup
                    push!(dat_vec,value(v_bid[tup]))
                end
                df[!,colname] = dat_vec
            end
        end
    elseif type == "v_flow_bal"
        v_bal = vars[type]
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
                df[!,colname] = value.(v_bal[col_tup].data)
            end
        end
    elseif type == "v_block"
        df = DataFrame()
        v_block = vars[type]
        if !isempty(name)
            blocks = unique(map(y -> (y[1], y[2], y[3]), filter(x -> x[1] == name, tuples["block_tuples"])))
        else
            blocks = unique(map(x -> (x[1], x[2], x[3]), tuples["block_tuples"]))
        end
        for block in blocks, s in scenarios
            colname = block[1] * "_" * block[2] * "_" * block[3]
            df[!, colname] = [JuMP.value.(v_block[block])]
        end
    elseif type == "v_setpoint" || type == "v_set_up" || type == "v_set_down"
        v_var = vars[type]
        if !isempty(name)
            setpoints = unique(map(x -> x[1], filter(y -> y[1] == name, tuples["setpoint_tuples"])))
        else
            setpoints = unique(map(x -> x[1], tuples["setpoint_tuples"]))
        end
        for sp in setpoints, s in scenarios
            col_tup = filter(x -> x[1] == sp && x[2] == s, tuples["setpoint_tuples"])
            if type == "v_set_up"
                colname = "up_" * sp * "_" * s
            elseif type == "v_set_down"
                colname = "down_" *  sp * "_" * s
            elseif type == "v_setpoint"
                colname = sp * "_" * s
            end
            if !isempty(col_tup)
                df[!,colname] = value.(v_var[col_tup].data)
            end
        end
    elseif type == "v_reserve_online"
        v_reserve_online = vars[type]
        if !isempty(name)
            ress = unique(map(y -> y[1], filter(x -> x[1] == name, tuples["reserve_limits"])))
        else
            ress = unique(map(y -> y[1], tuples["reserve_limits"]))
        end
        for r in ress, s in scenarios
            col_tup = filter(x -> x[1] == r && x[2] == s, tuples["reserve_limits"])
            colname = r * "_" * s
            if !isempty(col_tup)
                df[!,colname] = value.(v_reserve_online[col_tup].data)
            end
        end
    else
        println("ERROR: incorrect type")
    end
    return df
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
    vars = model_contents["variable"]
    v_bid = model_contents["expression"]["v_bid"]
    if input_data.contains_reserves
        v_res_final = vars["v_res_final"]
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
                if markets[m].type == "energy"
                    bid_tuple = unique(map(x->(x[1],x[3],x[4]),filter(x->x[1]==m && x[3]==s,tuples["balance_market_tuple"])))
                    volume = []
                    for tup in bid_tuple
                        push!(volume,value(v_bid[tup]))
                    end
                else
                    if input_data.contains_reserves
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

function resolve_delays(input_data::Predicer.InputData)
    processes = input_data.processes
    for p in keys(processes)
        Predicer.add_delay(input_data.temporals, processes[p].delay)
    end
    input_data.temporals.t = input_data.temporals.delay_ts
    return input_data
end


"""
    resolve_market_nodes(input_data::InputData) 

Function to construct market nodes based on the input data
"""
function resolve_market_nodes(input_data::InputData)
    markets = input_data.markets
    for m in collect(keys(markets))
        if markets[m].type == "energy"
            node_name = m
            input_data.nodes[node_name] = Predicer.Node(node_name, false, true)
            pname = markets[m].node * "_" * m * "_trade_process"
            market_p = Predicer.MarketProcess(pname)
            Predicer.add_topology(market_p, Predicer.Topology(markets[m].node, node_name, 0.0, 0.00001, 1.0, 1.0))
            Predicer.add_topology(market_p, Predicer.Topology(node_name, markets[m].node, 0.0, 0.0, 1.0, 1.0))
            input_data.processes[pname] = market_p
        end
    end
    return input_data
end
