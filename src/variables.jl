using JuMP
using DataStructures

"""
    create_variables(model_contents::OrderedDict)

Create the variables used in the model, and save them in the model_contents dict.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::InputData`: struct containing user input.
"""
function create_variables(model_contents::OrderedDict, input_data::InputData)
    create_v_flow(model_contents, input_data)
    create_v_load(model_contents, input_data)
    create_v_online(model_contents, input_data)
    create_v_reserve(model_contents, input_data)
    create_v_state(model_contents, input_data)
    create_vq_ramp(model_contents, input_data)
    create_v_flow_op(model_contents, input_data)
    create_v_risk(model_contents, input_data)
    create_v_balance_market(model_contents, input_data)
    create_v_reserve_online(model_contents,input_data)
    create_v_setpoint(model_contents, input_data)
    create_v_block(model_contents, input_data)
    create_v_node_delay(model_contents, input_data)
    create_v_bid_volume(model_contents,input_data)
end


"""
    create_v_flow(model_contents::OrderedDict, input_data::InputData)

Set up v_flow variables, which symbolise flows between nodes and processes, accounting for reserve realisation. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::InputData`: struct containing user input.
"""
function create_v_flow(model_contents::OrderedDict, input_data::InputData)
    process_tuples = unique(Predicer.validate_tuple(model_contents, process_topology_tuples(input_data), 4))
    model = model_contents["model"]
    v_flow = @variable(model, v_flow[tup in process_tuples] >= 0)
end


"""
    create_v_load(model_contents::OrderedDict, input_data::InputData)

Set up v_load variables, which symbolise the flows of the processes between nodes and processes before accounting for reserve realisation. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::InputData`: struct containing user input.
"""
function create_v_load(model_contents::OrderedDict, input_data::InputData)
    if input_data.setup.contains_reserves
        reserve_processes = unique(Predicer.validate_tuple(model_contents, unique(map(x -> (x[3:end]), reserve_process_tuples(input_data))), 4))
        model = model_contents["model"]
        v_load = @variable(model, v_load[tup in reserve_processes] >= 0)
    end
end


"""
    create_v_online(model_contents::OrderedDict, input_data::InputData)

Set up binary online, start and stop variables for modeling online functionality for processes.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model.
- `input_data::InputData`: Struct containing the input data defined by the user, based on which the model is built. 
"""
function create_v_online(model_contents::OrderedDict, input_data::InputData)
    if input_data.setup.contains_online
        proc_online_tuple = unique(Predicer.validate_tuple(model_contents, online_process_tuples(input_data), 2))
        if !isempty(proc_online_tuple)
            model = model_contents["model"]
            v_online = @variable(model, v_online[tup in proc_online_tuple], Bin)
            v_start = @variable(model, v_start[tup in proc_online_tuple], Bin)
            v_stop = @variable(model, v_stop[tup in proc_online_tuple], Bin)
        end
    end
end


"""
    create_v_reserve(model_contents::OrderedDict, input_data::InputData)

Set up process, node and bid reserve variables used for modelling reserves.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::InputData`: struct containing user input.
"""
function create_v_reserve(model_contents::OrderedDict, input_data::InputData)
    if input_data.setup.contains_reserves
        model = model_contents["model"]

        res_potential_tuple = unique(Predicer.validate_tuple(model_contents, reserve_process_tuples(input_data), 6))
        if !isempty(res_potential_tuple)
        v_reserve = @variable(model, v_reserve[tup in res_potential_tuple] >= 0)
        end

        res_tuple = unique(Predicer.validate_tuple(model_contents, reserve_market_directional_tuples(input_data), 4))
        if !isempty(res_tuple)
            v_res = @variable(model, v_res[tup in res_tuple] >= 0)
        end

        res_final_tuple = unique(Predicer.validate_tuple(model_contents, reserve_market_tuples(input_data), 2))
        if !isempty(res_final_tuple)
            @variable(model, v_res_final[tup in res_final_tuple] >= 0)
        end
    end
end

"""
    create_v_state(model_contents::OrderedDict, input_data::InputData)

Set up state variables and surplus and shortage slack variables used for modeling node state (storage).

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::InputData`: struct containing user input.
"""
function create_v_state(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    node_state_tuple = unique(Predicer.validate_tuple(model_contents, state_node_tuples(input_data), 2))
    node_balance_tuple = unique(Predicer.validate_tuple(model_contents, balance_node_tuples(input_data), 2))

    if input_data.setup.contains_states
        # Node state variable
        v_state = @variable(model, v_state[tup in node_state_tuple] >= 0)
    end
    
    if input_data.setup.use_node_dummy_variables
        # Slack variables for node_states
        vq_state_up = @variable(model, vq_state_up[tup in node_balance_tuple] >= 0)
        vq_state_dw = @variable(model, vq_state_dw[tup in node_balance_tuple] >= 0)
    end
end


"""
    create_vq_ramp(model_contents::OrderedDict, input_data::InputData)

Set up ramp variables and surplus and shortage slack variables.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model.
- `input_data::InputData`: struct containing user input.
"""
function create_vq_ramp(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    if input_data.setup.use_ramp_dummy_variables
        ramp_tups = unique(Predicer.validate_tuple(model_contents, process_topology_ramp_times_tuples(input_data), 4))
        vq_ramp_up = @variable(model, vq_ramp_up[tup in ramp_tups] >= 0)
        vq_ramp_dw = @variable(model, vq_ramp_dw[tup in ramp_tups] >= 0)
    end
end


"""
    create_v_flow_op(model_contents::OrderedDict, input_data::InputData)

Set up operational slot flow variables and binary slot indicator variable for processes with piecewise efficiency functionality.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model.
- `input_data::InputData`: struct containing user input.
"""
function create_v_flow_op(model_contents::OrderedDict, input_data::InputData)
    if input_data.setup.contains_piecewise_eff
        model = model_contents["model"]
        proc_op_balance_tuple = unique(Predicer.validate_tuple(model_contents, operative_slot_process_tuples(input_data), 2))
        v_flow_op_in = @variable(model,v_flow_op_in[tup in proc_op_balance_tuple] >= 0)
        v_flow_op_out = @variable(model,v_flow_op_out[tup in proc_op_balance_tuple] >= 0)
        v_flow_op_bin = @variable(model,v_flow_op_bin[tup in proc_op_balance_tuple], Bin)
    end
end


"""
    create_v_risk(model_contents::OrderedDict, input_data::InputData)

Set up variables for CVaR risk measure.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model.
- `input_data::InputData`: struct containing user input.
"""
function create_v_risk(model_contents::OrderedDict, input_data::InputData)
    if input_data.setup.contains_risk
        model = model_contents["model"]
        risk_tuple = scenarios(input_data)
        v_var = @variable(model,v_var)
        v_cvar_z = @variable(model,v_cvar_z[tup in risk_tuple] >= 0)
    end
end

"""
    create_v_balance_market(model_contents::OrderedDict, input_data::InputData)

Set up variables for balance market volumes.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model.
- `input_data::InputData`: struct containing user input.
"""
function create_v_balance_market(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    bal_market_tuple = unique(Predicer.validate_tuple(model_contents, create_balance_market_tuple(input_data), 3))
    v_flow_bal = @variable(model,v_flow_bal[tup in bal_market_tuple] >= 0)
end

"""
    create_v_reserve_online(model_contents::OrderedDict, input_data::InputData)

Set up online variables for reserve market participation.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model.
- `input_data::InputData`: struct containing user input.
"""
function create_v_reserve_online(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    res_online_tuple = unique(Predicer.validate_tuple(model_contents, create_reserve_limits(input_data), 2))
    v_reserve_online = @variable(model,v_reserve_online[tup in res_online_tuple], Bin)
end



"""
    create_v_setpoint(model_contents::OrderedDict, input_data::InputData)

Set up variables for general constraints with a setpoint functionality. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::InputData`: struct containing user input.
"""
function create_v_setpoint(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    setpoint_tuples = unique(Predicer.validate_tuple(model_contents, Predicer.setpoint_tuples(input_data), 2))
    v_set_up = @variable(model, v_set_up[tup in setpoint_tuples] >= 0)
    v_set_down = @variable(model, v_set_down[tup in setpoint_tuples] >= 0)
    v_setpoint = @variable(model, v_setpoint[tup in setpoint_tuples] >= 0)
end


""" 
    create_v_block(model_contents::OrderedDict, input_data::InputData)

Function to setup variables needed for inflow blocks.

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::InputData`: struct containing user input.
"""
function create_v_block(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    block_tuples = Predicer.block_tuples(input_data)
    var_tups = unique(map(x-> (x[1],x[2],Predicer.validate_tuple(model_contents,(x[3],input_data.inflow_blocks[x[1]].start_time),1)[1]),block_tuples))
    v_block = @variable(model, v_block[tup in var_tups], Bin)
end


"""
    create_v_node_delay(model_contents::OrderedDict, input_data::InputData)

Function to create variables needed for delay flow between nodes. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::InputData`: struct containing user input.
"""
function create_v_node_delay(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    delay_tups = node_delay_tuple(input_data)
    v_node_delay = @variable(model, v_node_delay[tup in delay_tups] >= 0)
end


"""
    create_v_bid_volume(model_contents::OrderedDict, input_data::InputData)

Function to create variables needed for bid curve creation. 

# Arguments
- `model_contents::OrderedDict`: Dictionary containing all data and structures used in the model. 
- `input_data::InputData`: struct containing user input.
"""
function create_v_bid_volume(model_contents::OrderedDict, input_data::InputData)
    model = model_contents["model"]
    bid_slot_tups = bid_slot_tuples(input_data)
    v_bid_volume = @variable(model, v_bid_volume[tup in bid_slot_tups])
end