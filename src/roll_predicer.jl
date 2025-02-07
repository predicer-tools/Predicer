import Predicer

using DataFrames
using Dates
using HiGHS
using JuMP
using DataStructures

""" 
    function roll_predicer(input_data_path::String, horizon_length::Number, overlap::Number, roll_start::Number=0, roll_end::Number=8760000)

Rolling Predicer:

The idea of "rolling" Predicer is to divide a longer time horizon into smaller managable parts which are optimized separately, in sequence. Variable data is transferred
between these shorter horizons to ensure model continuity in regards to state (storage) variables, process online variables and process ramp rates. The shorter horizons
can be run with an overlap if needed. This could for example mean, that the last 24h of a horizon is optimized again the next horizon, and the starting values of the 
next horizon are taken from the start of the overlap period. This is useful for reducing unwanted model behaviour at the end of the horizon, for example when the model 
contains storages and the value of the energy/material which is left in the storage at the end of the horizon is poorly defined.

The residual value of the storage is a model-technical variable used to give a "value" to the energy/matter/something which remains in a storage at the end of the modelling 
horizon. If this is 0, the model will likely empty the storage before the end of the horizon as according to the model, there is nothing after the last timestep. We can thus
give a value to the storage contents to prevent the storage from emptying at the end. This value is defined as a constant parameter in the input data, but in reality the value 
of the storage contents varias between hours, days and seasons. For example heat in a heat storage is valued less during the summer when heat is abundant, compared to the
winter when heat is less abundant and the heat demand is (typically) higher. The same goes for hydro reservoirs, etc. In rolling models, the residaul value should thus change
between the horizons, perhaps based on the marginal heat production costs, or electricity market price. This has to be added by the user, as the calculation is model-specific
and difficult to generalize. 

Restrictions and limitations:
- Currently a deterministic model with only one scenario
- Models with larger storages may behave differently, as the long-term "view" of the model is lost when optimizing in smaller parts.
- Rebuilding the model from scratch for every new horizon can be slow, depending on the model. 
- Model input data should contain the WHOLE horizon, i.e. one month or year. The data for the whole year should have sufficient temporal resolution for the part horizons.
- Rolling models containing processes with long minimum or maximum online and offline periods should be rolled with a sufficient overlap. Otherwise there is a risk that 

# Arguments
- `input_data_path::String`: Path of the input data to be used. This input data should have the model for the WHOLE horizon.
- `horizon_length::Number`: Length of the part-horizons, given in hours. 
- `overlap::Number`: Length of the overlap period between part-horizons, given in hours. Should be smaller than the value given for "horizon_length"
- `roll_start::Number=0`: The starting point (in hours) for the rolling. Mainly used for debugging specific parts of the model data, without having o run the whole model.
- `roll_end::Number=8760000`: End point (in hours) for the rolling. Used for debugging or testing specific parts of the model data. Default is 1000 years, which is hopefully enough.

# Output
The function returns a dictionary ("data_log") with three entries, containing both variable values for each part-horizon, as well as metadata concerning the rolling of the model. 


The key "meta" contains information about the used model. Below is an example with a part-horizopn length of 30 days (30 * 24h), with a 72h overlap. The rolling finished successfully,
as "termination_code" is "OPTIMAL".

julia> data_log["meta"]
    Dict{Any, Any} with 4 entries:
    "input_data_path"  => "model_input_data_path.xlsx"
    "termination_code" => OPTIMAL
    "horizon_length"   => 720
    "overlap"          => 72


The key "runs_info" contains a dictionary, which in turn contains information about each (1...n) of the part-horizons of the rolled model. This information includes starting and ending 
time in hours, a list of all timesteps, as well as a DataFrame containing the costs of the model. 
julia> df["runs_info"][1]
Dict{Any, Any} with 4 entries:
  "t_end"     => 720
  "t_start"   => 0
  "timesteps" => [DateTime("2021-01-01T00:00:00"), DateTime("2021-01-01T01:00:00")…  
  "costs"     => 1×11 DataFrame…

Finally, the key "model_runs" a dictionary, which in turn contains the variable values for each (1...n) of the part-horizons in the rolled model. 
julia> df["model_runs"][1]
Dict{Any, Any} with 22 entries:
  "v_state"      => 720×4 DataFrame…
  "v_flow"       => 720×1 DataFrame…
  "v_bid_volume" => 720×1 DataFrame…
  "v_bid"        => 720×2 DataFrame…
  ⋮              => ⋮
    
"""
function roll_predicer(input_data_path::String, horizon_length::Number, overlap::Number, roll_start::Number=0, roll_end::Number=8760000)
    # save data into a log 
    data_log = OrderedDict()
    meta = Dict()
    meta["input_data_path"] = input_data_path
    meta["horizon_length"] = horizon_length
    meta["overlap"] = overlap
    data_log["meta"] = meta
    data_log["model_runs"] = OrderedDict()
    data_log["runs_info"] = OrderedDict()

    # get all the relevant data from the data file
    system_data, timeseries_data, temps = Predicer.read_xlsx(input_data_path, DateTime[]);

    temps = collect(temps)

    # create temporals struct based on temps?
    time_struct = Predicer.Temporals(collect(temps))

    if time_struct.is_variable_dt
        # sum of differences between timesteps
        t_len = sum(time_struct.variable_dt)
    else
        # length between timesteps * amount of timesteps.
        t_len = time_struct.dtf * length(temps)
    end


    # Loop through temps_ in suitable slices (based on h_len and overlap)
    # create input data based on temps
    # if not the first horizon, set some variables based on previous run
    # run model
    # save results in DataFrames

    ts_counter = roll_start
    t_0 = temps[begin]
    is_first_go = true

    mc = nothing
    input_data = nothing
    slice_timesteps = [nothing]
    slice_start = nothing
    slice_end = nothing
    # loop until all hours are done
    while ts_counter < t_len && ts_counter < roll_end
        # calculate new slice start and end (hours from start)
        if is_first_go
            slice_start = ts_counter
            slice_end = slice_start + horizon_length
            #update counter
            ts_counter += horizon_length
        else
            slice_start = slice_end - overlap
            slice_end = slice_start + horizon_length
            #update counter
            ts_counter += horizon_length - overlap
        end
        # save previous slice timesteps
        previous_slice_timesteps = copy(slice_timesteps)
        # calculate the respective timesteps for the slice start and end
        slice_timesteps = filter(x -> slice_start <= (convert(Dates.Second, x - t_0) / Dates.Second(3600)) < slice_end, temps);
        println("#########")
        println("Rolling horizon for timesteps ", slice_timesteps[begin], " to ", slice_timesteps[end], ".")
        println("Timesteps ", slice_start, " - ", slice_end)
        println("Input file: ", input_data_path, ".\n\n")
        if !is_first_go  
            # calculate last timestep from the last run, before the current horizon
            if overlap > 0
                previous_last_t = nothing
                for (i, pst) in enumerate(previous_slice_timesteps)
                    if pst == slice_timesteps[begin]
                        previous_last_t = previous_slice_timesteps[i-1]
                    end
                end
            else
                previous_last_t = previous_slice_timesteps[end]
            end
        end
        if !is_first_go
            #get relevant data to transfer from the previous horizon using the inputdata from the previous horizon
            transfer_data = Predicer.get_data_to_transfer(mc, input_data, previous_last_t)
        end
        # now create new input data using the timesteps for the current horizon
        input_data = Predicer.compile_input_data(system_data, timeseries_data, slice_timesteps);
        if !is_first_go
            # modify new input data with values from the previous model run.
            # these values include storage state, as well as process flow, load and online state
            # for the timestep before the new horizon. 
            input_data = Predicer.change_model_data(input_data, transfer_data);
        end


        ###
        # set the residual value of a state to be appropriate!
        # This short segment should be model-specific if needed.
        # Calculate a reasonable value for the residual value of a state.
        # It could be based on an externally supplied timeseries, or the prices of the next part-horizon.
        # The residual value is calculated based on the values of a timeseries in the model (in this case market prices)

        """
        res_value_calc_n = 3*24 # three days as an example
        next_slice_start = slice_end + 1 # set the starting point for the price calculation to be after the last timestep of the part-horizon
        next_slice_end = slice_end + res_value_calc_n # define end point of calculation
        next_slice_timesteps = filter(x -> next_slice_start <= (convert(Dates.Second, x - t_0) / Dates.Second(3600)) < next_slice_end, temps); # find relevant timesteps

        relevant_res_vals = filter(x -> DateTime(x.t) in next_slice_timesteps, timeseries_data["market_prices"]) # get relevant timeseries from the input data
        col_nr = 3 # In this case, the relevant timeseries data was in the third column of the dataframe. 
        if !isempty(relevant_res_vals)
            res_val = sum(relevant_res_vals[:, 3]) / res_value_calc_n # calculate average of prices for the timeseries
            input_data.nodes["INSERT_STATE_NODE_NAME"].state.residual_value = res_val # The residual value of the state is set based on the calculated average price.  
        end
        """


        # Check input_data. end rolling if data not valid. 
        validation_result = Predicer.validate_data(input_data);
        if !validation_result["is_valid"]
            unsucc_dict = Dict()
            unsucc_dict["termination_code"] = validation_result["errors"]
            unsucc_dict["model"] = nothing
            unsucc_dict["input_data"] = input_data
            unsucc_dict["t_start"] = slice_start
            unsucc_dict["t_end"] = slice_end
            unsucc_dict["timesteps"] = slice_timesteps
            data_log["failed_last_run"] = unsucc_dict
            return data_log
        end
        # Build market structures
        input_data = Predicer.resolve_market_nodes(input_data);
        # create model_contents
        mc = Predicer.build_model_contents_dict(input_data)
        mc["model"] = Predicer.setup_optimizer()
        # build model
        Predicer.build_model(mc, input_data)
        # solve model.
        Predicer.solve_model(mc)

        # check if model solved successfully, and store data based on results.
        if termination_status(mc["model"]) == MOI.TerminationStatusCode(1) # optimal solution, save results
            log_key = length(data_log["model_runs"])+1
            run_info = Dict()
            run_info["t_start"] = slice_start
            run_info["t_end"] = slice_end
            run_info["timesteps"] = slice_timesteps
            #log_key["model"] = mc
            #log_key["input_data"] = input_data
            run_info["costs"] = Predicer.get_costs_dataframe(mc, input_data)
            data_log["runs_info"][log_key] = run_info
            data_log["model_runs"][log_key] = Predicer.get_all_result_dataframes(mc, input_data, "", "")
            data_log["meta"]["termination_code"] = termination_status(mc["model"])
        else
            unsucc_dict = Dict()
            unsucc_dict["termination_code"] = termination_status(mc["model"])
            unsucc_dict["model"] = mc
            unsucc_dict["input_data"] = input_data
            unsucc_dict["t_start"] = slice_start
            unsucc_dict["t_end"] = slice_end
            unsucc_dict["timesteps"] = slice_timesteps
            data_log["failed_last_run"] = unsucc_dict
            return data_log
        end
        # set flag to false
        if is_first_go
            is_first_go = false
        end
    end
    return data_log
end

"""
    set_state_initial_value(input_data::Predicer.InputData, transfer_data::Dict{Any, Any}, scenario::String="")

Function for setting the initial value of the state based on the results of the previous model run. If the scenario to be used is not defined, the function 
will take one of the scenarios and may work unpredictably if there are several scenarios. The data from the previous part-horizon in provided as a parameter.
"""
function set_state_initial_value(input_data::Predicer.InputData, transfer_data::Dict{Any, Any}, scenario::String="")
    if isempty(scenario)
        for k in collect(keys(transfer_data["state_value"]))
            input_data.nodes[k[1]].state.initial_state = transfer_data["state_value"][k]
        end
    else
        for k in unique(filter(x -> x[2] == scenario, collect(keys(transfer_data["state_value"]))))
            input_data.nodes[k[1]].state.initial_state = transfer_data["state_value"][k]
        end
    end
    return input_data
end


"""
    set_process_initial_flow(input_data::Predicer.InputData, transfer_data::Dict{Any, Any}, scenario::String="")

Function for setting the initial flow of processes based on the results of the previous model run. If the scenario to be used is not defined, the function 
will take one of the scenarios and may work unpredictably if there are several scenarios. The data from the previous part-horizon in provided as a parameter.
"""
function set_process_initial_flow(input_data::Predicer.InputData, transfer_data::Dict{Any, Any}, scenario::String="")
    if !isempty(scenario)
        flow_tups = unique(filter(x -> x[4] == scenario, collect(keys(transfer_data["process_flow"]))))
    else
        flow_tups = collect(keys(transfer_data["process_flow"]))
    end
    for ft in flow_tups
        topo = filter(x -> x.source == ft[2] && x.sink == ft[3], input_data.processes[ft[1]].topos)[1]
        topo.initial_flow = transfer_data["process_flow"][ft] / topo.capacity
    end
    return input_data
end

"""
    set_process_initial_load(input_data::Predicer.InputData, transfer_data::Dict{Any, Any}, scenario::String="")

Function for setting the initial load of processes based on the results of the previous model run. If the scenario to be used is not defined, the function 
will take one of the scenarios and may work unpredictably if there are several scenarios. The data from the previous part-horizon in provided as a parameter.
"""
function set_process_initial_load(input_data::Predicer.InputData, transfer_data::Dict{Any, Any}, scenario::String="")
    if !isempty(scenario)
        load_tups = unique(filter(x -> x[4] == scenario, collect(keys(transfer_data["process_load"]))))
    else
        load_tups = collect(keys(transfer_data["process_load"]))
    end
    for lt in load_tups
        topo = filter(x -> x.source == lt[2] && x.sink == lt[3], input_data.processes[lt[1]].topos)[1]
        topo.initial_load = transfer_data["process_load"][lt]
    end
    return input_data
end


"""
    set_process_initial_online_state(input_data::Predicer.InputData, transfer_data::Dict{Any, Any}, scenario::String="")

Function for setting the initial online state processes based on the results of the previous model run. If the scenario to be used is not defined, the function 
will take one of the scenarios and may work unpredictably if there are several scenarios. The data from the previous part-horizon in provided as a parameter.
"""
function set_process_initial_online_state(input_data::Predicer.InputData, transfer_data::Dict{Any, Any}, scenario::String="")
    if !isempty(scenario)
        online_tups = unique(filter(x -> x[4] == scenario, collect(keys(transfer_data["process_online"]))))
    else
        online_tups = collect(keys(transfer_data["process_online"]))
    end
    for ot in online_tups
        input_data.processes[ot[1]].initial_state = Bool(round(transfer_data["process_online"][ot]))
    end
    return input_data
end

"""
    change_model_data(input_data::Predicer.InputData, transfer_data::Dict)

Function changing input data parameters to match values obtained from variable results from the previous part-horizon.
"""
function change_model_data(input_data::Predicer.InputData, transfer_data::Dict)
    input_data = set_state_initial_value(input_data, transfer_data);
    input_data = set_process_initial_flow(input_data, transfer_data);
    input_data = set_process_initial_load(input_data, transfer_data);
    input_data = set_process_initial_online_state(input_data, transfer_data);
    return input_data
end

"""
    get_data_to_transfer(mc::OrderedDict{Any, Any}, old_input_data::Predicer.InputData, previous_last_t::DateTime)

    Function to get relevant variable values from the previous part-horizon for the last timestep before the overlap period. 
    Notice that this function only works with deterministic models with one scenario. 
    The variable values to be transferred are:
     - State values (state_initial_value)
     - Process online state (initial_state)
     - Process load (initial_load)
     - Process flow (initial_flow)
"""
function get_data_to_transfer(mc::OrderedDict{Any, Any}, old_input_data::Predicer.InputData, previous_last_t::DateTime)
    transfer_data = Dict()
    # state values
    transfer_data["state_value"] = Dict()
    map(x -> transfer_data["state_value"][x] = JuMP.value(mc["model"][:v_state][x]), filter(x -> x[3] == string(previous_last_t), Predicer.state_node_tuples(old_input_data)))
    
    # process flow
    transfer_data["process_flow"] = Dict()
    flow_tups = filter(x -> x[5] == string(previous_last_t), Predicer.process_topology_tuples(old_input_data))
    for ft in flow_tups
        if old_input_data.processes[ft[1]].conversion == 1
            transfer_data["process_flow"][ft] = JuMP.value(mc["model"][:v_flow][ft])
        end
    end

    # process load
    transfer_data["process_load"] = Dict()
    if old_input_data.setup.contains_reserves
        load_tups = filter(x -> x[5] == string(previous_last_t), unique(map(x -> x[3:end], Predicer.reserve_process_tuples(old_input_data))))
        for lt in load_tups
            transfer_data["process_load"][lt] = JuMP.value(mc["model"][:v_load][lt])
        end
    end

    # process online state
    transfer_data["process_online"] = Dict()
    online_tups = filter(x -> x[3] == string(previous_last_t), Predicer.online_process_tuples(old_input_data))
    for ot in online_tups
        transfer_data["process_online"][ot] = JuMP.value(mc["model"][:v_online][ot])
    end
    return transfer_data
end


""" 
    collect_cost_dfs(data_log)

    Function to collect costs of each part-horizon to one dataframe, with each row being one run. Keep in mind that each row contains the values for the horizon overlap as well. 
    The data_log parameter is the data log returned by the roll_predicer-function.  
"""
function collect_cost_dfs(data_log)
    model_run_keys = collect(keys(data_log["model_runs"]))
    dfs = DataFrame()
    for mrk in model_run_keys
        append!(dfs, data_log["runs_info"][mrk]["costs"])
    end
    return dfs
end


""" 
    collect_result_dfs(data_log)

    Function to collect variable values of each part-horizon to one dataframe, if overlap has been used, only the variables for timesteps before the overlap are included. 
    The data_log parameter is the data log is the result of the roll_predicer-function.  
"""
function collect_result_dfs(data_log)
    dfs = Dict()
    run_keys = collect(keys(data_log["model_runs"]))
    if !isempty(run_keys)
        dfs_names = collect(keys(data_log["model_runs"][run_keys[1]]))
    else
        return dfs
    end
    rk_len = length(run_keys)
    for i in run_keys
        if i < rk_len
            timesteps = data_log["runs_info"][i]["timesteps"]
            next_timesteps = data_log["runs_info"][i+1]["timesteps"]
            if data_log["model_runs"][1]["v_flow"].t == data_log["model_runs"][2]["v_flow"].t
                timesteps_to_include = data_log["model_runs"][1]["v_flow"].t
            else
                timesteps_to_include = filter(x -> !(x in next_timesteps), timesteps) #exclude timesteps within overlap region
            end
            for dfn in dfs_names
                if !isempty(data_log["model_runs"][i][dfn])
                    if i == 1
                        run_df = filter(:t => x -> DateTime(x) in timesteps_to_include, data_log["model_runs"][i][dfn])
                        run_df.t = map(x -> x, timesteps_to_include)
                        dfs[dfn] = run_df
                    else
                        run_df = filter(:t => x -> DateTime(x) in timesteps_to_include, data_log["model_runs"][i][dfn])
                        run_df.t = map(x -> x, timesteps_to_include)
                        append!(dfs[dfn], run_df)
                    end
                end
            end
        else
            timesteps = data_log["runs_info"][i]["timesteps"]
            if data_log["model_runs"][1]["v_flow"].t == data_log["model_runs"][2]["v_flow"].t
                timesteps_to_include = data_log["model_runs"][1]["v_flow"].t
            else
                timesteps_to_include = collect(values(timesteps)) #take all remaining timesteps
            end
            for dfn in dfs_names
                if !isempty(data_log["model_runs"][i][dfn])
                    run_df = filter(:t => x -> DateTime(x) in timesteps_to_include, data_log["model_runs"][i][dfn])
                    run_df.t = map(x -> x, timesteps_to_include)
                    append!(dfs[dfn], run_df)
                end
            end
        end
    end
    return dfs
end