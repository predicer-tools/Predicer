using JuMP
using Cbc
using DataFrames
using TimeZones
using Dates
using DataStructures
using XLSX

"""
    get_result_dataframe(model_contents::OrderedDict, input_data::Predicer.InputData,type::String="",process::String="",node::String="",scenario::String="")

Returns a dataframe containing specific information for a variable in the model. 

# Arguments
- `model_contents::OrderedDict`: Model contents dict.
- `input_data::Predicer.InputData`: Input data used in model.
- `type::String`: Type of variable to show, such as 'v_flow' or 'v_state'.
- `process::String`: The name of the process connected to the variable.
- `node::String`: The name of the node related to the variable.
- `scenario::String`: The name of the scenario for which the value is to be shown.
"""
function get_result_dataframe(model_contents::OrderedDict, input_data::Predicer.InputData,type::String="",process::String="",node::String="",scenario::String="")
    println("Getting results for:")
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
        tups = unique(map(x->(x[1],x[2],x[3]),filter(x->x[1]==process, vcat(tuples["process_tuple"], tuples["delay_tuple"]))))
        for tup in tups, s in scenarios
            colname = join(tup,"-") * "-" *s
            col_tup = filter(x->x[1:3]==tup && x[4]==s, vcat(tuples["process_tuple"], tuples["delay_tuple"]))
            if !isempty(col_tup)
                df[!, colname] = value.(v_flow[col_tup].data)
            end
        end
    elseif type == "v_reserve"
        v_res = vars[type]
        tups = unique(map(x->(x[1],x[2],x[3],x[5]),filter(x->x[3]==process, tuples["res_potential_tuple"])))
        for tup in tups, s in scenarios
            col_name = join(tup,"-")  * "-" *s
            col_tup = filter(x->(x[1],x[2],x[3],x[5])==tup && x[6]==s, tuples["res_potential_tuple"])
            if !isempty(col_tup)
                df[!, col_name] = value.(v_res[col_tup].data)
            end
        end
    elseif type == "v_res_final"
        v_res = vars[type]
        ress = unique(map(x->x[1],tuples["res_final_tuple"]))
        for r in ress, s in scenarios
            colname = r * "-" * s
            col_tup = filter(x->x[1]==r && x[2]==s, tuples["res_final_tuple"])
            if !isempty(col_tup)
                df[!, colname] = value.(v_res[col_tup].data)
            end
        end

    elseif type == "v_online" || type == "v_start" || type == "v_stop"
        v_bin = vars[type]
        procs = unique(map(x->x[1],tuples["process_tuple"]))
        for p in procs, s in scenarios
            col_tup = filter(x->x[1]==p && x[2]==s, tuples["proc_online_tuple"])
            colname = p * "-" * s
            if !isempty(col_tup)
                df[!, colname] = value.(v_bin[col_tup].data)
            end
        end
    elseif type == "v_state"
        v_state = vars[type]
        if !isempty(node)
            col_tup = filter(x->x[1]==node && x[2]==scenario, tuples["node_state_tuple"])
            if !isempty(col_tup)
                df[!, node] = value.(v_state[col_tup].data)
            end
        else
            tups = unique(map(t -> t[1], filter(x->x[2]==scenario, tuples["node_state_tuple"])))
            for tup in tups
                col_tup = filter(x->x[1]==tup && x[2]==scenario, tuples["node_state_tuple"])
                if !isempty(col_tup)
                    df[!, tup] = value.(v_state[col_tup].data)
                end
            end
        end
    elseif type == "vq_state_up" || type == "vq_state_dw"
        v_state = vars[type]
        nods = unique(map(x->x[1],tuples["node_balance_tuple"]))
        for n in nods, s in scenarios
            col_tup = filter(x->x[1]==n && x[2]==s, tuples["node_balance_tuple"])
            colname = n * "-" * s
            if !isempty(col_tup)
                df[!, colname] = value.(v_state[col_tup].data)
            end
        end
    elseif type == "v_bid"
        v_bid = expr[type]
        for s in scenarios
            bid_tups = unique(map(x->(x[1],x[3],x[4]),filter(x->x[1]==node && x[3]==s,tuples["balance_market_tuple"])))
            if !isempty(bid_tups)
                dat_vec = []
                colname = node * "-" * s
                for (i,tup) in enumerate(bid_tups)
                    push!(dat_vec,value(v_bid[tup]))
                end
                df[!,colname] = dat_vec
            end
        end
    elseif type == "v_flow_bal"
        v_bal = vars[type]
        dir = ["up","dw"]
        for d in dir, s in scenarios
            tup = filter(x->x[1]==node && x[2]==d && x[3]==s, tuples["balance_market_tuple"])
            colname = node * "-" * d * "-" * s
            if !isempty(tup)
                df[!,colname] = value.(v_bal[tup].data)
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
    v_bid = model_contents["expression"]["v_bid"]
    if input_data.contains_reserves
        v_res_final = vars["v_res_final"]
    end

    tuples = Predicer.create_tuples(input_data)
    temporals = input_data.temporals.t
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
                price = map(t -> markets[m].price(s, t),temporals)
                if markets[m].type == "energy"
                    bid_tuple = unique(map(x->(x[1],x[3],x[4]),filter(x->x[1]==markets[m].node && x[3]==s,tuples["balance_market_tuple"])))
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
        end
    end
end

function resolve_delays(input_data::Predicer.InputData)
    processes = input_data.processes
    for p in keys(processes)
        Predicer.add_delay(input_data.temporals, processes[p].delay)
    end
    input_data.temporals.t = input_data.temporals.delay_ts
    return input_data
end