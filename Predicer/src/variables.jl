using JuMP
using DataStructures

"""
    create_variables(model_contents::OrderedDict)

Create the variables used in the model, and save them in the model_contents dict.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_variables(model_contents::OrderedDict, input_data::InputData)
    create_v_flow(model_contents, input_data)
    create_v_online(model_contents, input_data)
    create_v_reserve(model_contents, input_data)
    create_v_state(model_contents, input_data)
    create_v_flow_op(model_contents, input_data)
    create_v_risk(model_contents, input_data)
end


"""
    create_v_flow(model_contents::OrderedDict, input_data::InputData)

Set up v_flow variables, which symbolise flows between nodes and processes.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_flow(model_contents::OrderedDict, input_data::InputData)
    process_tuples = process_topology_tuples(input_data)
    model = model_contents["model"]
    v_flow = @variable(model, v_flow[tup in process_tuples] >= 0)
    model_contents["variable"]["v_flow"] = v_flow
end


"""
    create_v_online(model_contents::OrderedDict, input_data::InputData)

Set up binary online, start and stop variables for modeling online functionality for processes.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_online(model_contents::OrderedDict, input_data::InputData)
    proc_online_tuple = online_process_tuples(input_data)
    if !isempty(proc_online_tuple)
        model = model_contents["model"]
        v_online = @variable(model, v_online[tup in proc_online_tuple], Bin)
        v_start = @variable(model, v_start[tup in proc_online_tuple], Bin)
        v_stop = @variable(model, v_stop[tup in proc_online_tuple], Bin)
        model_contents["variable"]["v_online"] = v_online
        model_contents["variable"]["v_start"] = v_start
        model_contents["variable"]["v_stop"] = v_stop
    end
end


"""
    create_v_reserve(model_contents::OrderedDict, input_data::InputData)

Set up process, node and bid reserve variables used for modelling reserves.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_reserve(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]

    res_potential_tuple = reserve_process_tuples(input_data)
    if !isempty(res_potential_tuple)
       v_reserve = @variable(model, v_reserve[tup in res_potential_tuple] >= 0)
       model_contents["variable"]["v_reserve"] = v_reserve
    end

    res_tuple = reserve_market_directional_tuples(input_data)
    if !isempty(res_tuple)
        v_res = @variable(model, v_res[tup in res_tuple] >= 0)
        model_contents["variable"]["v_res"] = v_res
    end

    res_final_tuple = reserve_market_tuples(input_data)
    if !isempty(res_final_tuple)
        @variable(model, v_res_final[tup in res_final_tuple] >= 0)
        model_contents["variable"]["v_res_final"] = v_res_final
    end
end


"""
    create_v_state(model_contents::OrderedDict, input_data::InputData)

Set up state variables and surplus and shortage slack variables used for modeling node state (storage).

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_state(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    node_state_tuple = state_node_tuples(input_data)
    node_balance_tuple = balance_node_tuples(input_data)


    # Node state variable
    v_state = @variable(model, v_state[tup in node_state_tuple] >= 0)
    model_contents["variable"]["v_state"] = v_state

    # Slack variables for node_states
    vq_state_up = @variable(model, vq_state_up[tup in node_balance_tuple] >= 0)
    vq_state_dw = @variable(model, vq_state_dw[tup in node_balance_tuple] >= 0)
    model_contents["variable"]["vq_state_up"] = vq_state_up
    model_contents["variable"]["vq_state_dw"] = vq_state_dw
end


"""
    create_v_flow_op(model_contents::OrderedDict, input_data::InputData)

Set up operational slot flow variables and binary slot indicator variable for processes with piecewise efficiency functionality.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_flow_op(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    proc_op_balance_tuple = operative_slot_process_tuples(input_data)
    v_flow_op_in = @variable(model,v_flow_op_in[tup in proc_op_balance_tuple] >= 0)
    v_flow_op_out = @variable(model,v_flow_op_out[tup in proc_op_balance_tuple] >= 0)
    v_flow_op_bin = @variable(model,v_flow_op_bin[tup in proc_op_balance_tuple], Bin)
    model_contents["variable"]["v_flow_op_in"] = v_flow_op_in
    model_contents["variable"]["v_flow_op_out"] = v_flow_op_out
    model_contents["variable"]["v_flow_op_bin"] = v_flow_op_bin
end


"""
    create_v_risk(model_contents::OrderedDict, input_data::InputData)

Set up variables for CVaR risk measure.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_risk(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    risk_tuple = scenarios(input_data)
    v_var = @variable(model,v_var)
    v_cvar_z = @variable(model,v_cvar_z[tup in risk_tuple] >= 0)
    model_contents["variable"]["v_var"] = v_var
    model_contents["variable"]["v_cvar_z"] = v_cvar_z
end