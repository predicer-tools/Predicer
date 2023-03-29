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
    create_v_load(model_contents, input_data)
    create_v_online(model_contents, input_data)
    create_v_reserve(model_contents, input_data)
    create_v_state(model_contents, input_data)
    create_v_flow_op(model_contents, input_data)
    create_v_risk(model_contents, input_data)
    create_v_balance_market(model_contents, input_data)
    create_v_reserve_online(model_contents,input_data)
    create_v_setpoint(model_contents, input_data)
    create_v_block(model_contents, input_data)
end


"""
    create_v_flow(model_contents::OrderedDict, input_data::InputData)

Set up v_flow variables, which symbolise flows between nodes and processes, accounting for reserve realisation. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_flow(model_contents::OrderedDict, input_data::InputData)
    process_tuples = process_topology_tuples(input_data)
    delay_tuples = create_delay_process_tuple(input_data)
    model = model_contents["model"]
    v_flow = @variable(model, v_flow[tup in vcat(process_tuples, delay_tuples)] >= 0)
    model_contents["variable"]["v_flow"] = v_flow
end


"""
    create_v_load(model_contents::OrderedDict, input_data::InputData)

Set up v_load variables, which symbolise the flows of the processes between nodes and processes before accounting for reserve realisation. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_load(model_contents::OrderedDict, input_data::InputData)
    if input_data.contains_reserves
        reserve_processes = unique(map(x -> (x[3:end]), reserve_process_tuples(input_data)))
        model = model_contents["model"]
        v_load = @variable(model, v_load[tup in reserve_processes] >= 0)
        model_contents["variable"]["v_load"] = v_load
    end
end


"""
    create_v_online(model_contents::OrderedDict, input_data::InputData)

Set up binary online, start and stop variables for modeling online functionality for processes.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_online(model_contents::OrderedDict, input_data::InputData)
    if input_data.contains_online
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
end


"""
    create_v_reserve(model_contents::OrderedDict, input_data::InputData)

Set up process, node and bid reserve variables used for modelling reserves.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_reserve(model_contents::OrderedDict, input_data::InputData)
    if input_data.contains_reserves
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

    if input_data.contains_states
        # Node state variable
        v_state = @variable(model, v_state[tup in node_state_tuple] >= 0)
        model_contents["variable"]["v_state"] = v_state
    end
    
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
    if input_data.contains_piecewise_eff
        model = model_contents["model"]
        proc_op_balance_tuple = operative_slot_process_tuples(input_data)
        v_flow_op_in = @variable(model,v_flow_op_in[tup in proc_op_balance_tuple] >= 0)
        v_flow_op_out = @variable(model,v_flow_op_out[tup in proc_op_balance_tuple] >= 0)
        v_flow_op_bin = @variable(model,v_flow_op_bin[tup in proc_op_balance_tuple], Bin)
        model_contents["variable"]["v_flow_op_in"] = v_flow_op_in
        model_contents["variable"]["v_flow_op_out"] = v_flow_op_out
        model_contents["variable"]["v_flow_op_bin"] = v_flow_op_bin
    end
end


"""
    create_v_risk(model_contents::OrderedDict, input_data::InputData)

Set up variables for CVaR risk measure.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_risk(model_contents::OrderedDict, input_data::InputData)
    if input_data.contains_risk
        model = model_contents["model"]
        risk_tuple = scenarios(input_data)
        v_var = @variable(model,v_var)
        v_cvar_z = @variable(model,v_cvar_z[tup in risk_tuple] >= 0)
        model_contents["variable"]["v_var"] = v_var
        model_contents["variable"]["v_cvar_z"] = v_cvar_z
    end
end

"""
    create_v_balance_market(model_contents::OrderedDict, input_data::InputData)

Set up variables for balance market volumes.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_balance_market(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    bal_market_tuple = create_balance_market_tuple(input_data)
    v_flow_bal = @variable(model,v_flow_bal[tup in bal_market_tuple] >= 0)
    model_contents["variable"]["v_flow_bal"] = v_flow_bal
end

"""
    create_v_reserve_online(model_contents::OrderedDict, input_data::InputData)

Set up online variables for reserve market participation.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
"""
function create_v_reserve_online(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    res_online_tuple = create_reserve_limits(input_data)
    v_reserve_online = @variable(model,v_reserve_online[tup in res_online_tuple], Bin)
    model_contents["variable"]["v_reserve_online"] = v_reserve_online
end



"""
    create_v_setpoint(model_contents::OrderedDict, input_data::InputData)

Set up variables for general constraints with a setpoint functionality. 
"""
function create_v_setpoint(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    setpoint_tuples = Predicer.setpoint_tuples(input_data)
    v_set_up = @variable(model, v_set_up[tup in setpoint_tuples] >= 0)
    v_set_down = @variable(model, v_set_down[tup in setpoint_tuples] >= 0)
    v_setpoint = @variable(model, v_setpoint[tup in setpoint_tuples] >= 0)
    model_contents["variable"]["v_set_up"] = v_set_up
    model_contents["variable"]["v_set_down"] = v_set_down
    model_contents["variable"]["v_setpoint"] = v_setpoint
end


""" 
    create_v_block(model_contents::OrderedDict, input_data::InputData)

Function to setup variables needed for inflow blocks.
"""
function create_v_block(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    block_tuples = Predicer.block_tuples(input_data)
    var_tups = unique(map(x -> (x[1], x[2], x[3]), block_tuples))
    v_block = @variable(model, v_block[tup in var_tups], Bin) 
    model_contents["variable"]["v_block"] = v_block
end