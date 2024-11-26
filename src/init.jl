using JuMP
using HiGHS
using DataFrames
using Dates
using DataStructures
using XLSX


function get_data(fpath::String, t_horizon::Vector{DateTime}=DateTime[])
    return import_input_data(fpath, t_horizon)
end


function create_validation_dict(input_data::InputData)
    val_dict = OrderedDict()
    if input_data.setup.common_start_timesteps > 0
        temps = input_data.temporals.t[1:input_data.setup.common_start_timesteps]
        for s in Predicer.scenarios(input_data), i in 1:1:input_data.setup.common_start_timesteps
            val_dict[(s, temps[i])] = (input_data.setup.common_scenario_name, temps[i])
        end
    end
    if input_data.setup.common_end_timesteps > 0
        temps = input_data.temporals.t[end-input_data.setup.common_end_timesteps+1:end]
        for s in Predicer.scenarios(input_data), i in 1:1:input_data.setup.common_end_timesteps
            val_dict[(s, temps[i])] = (input_data.setup.common_scenario_name, temps[i])
        end
    end
    return val_dict
end

function build_model_contents_dict(input_data::Predicer.InputData)
    model_contents = OrderedDict()
    model_contents["expression"] = OrderedDict() #expressions?
    model_contents["gen_constraint"] = OrderedDict() #GenericConstraints
    model_contents["gen_expression"] = OrderedDict() #GenericConstraints
    model_contents["validation_dict"] = create_validation_dict(input_data)
    if input_data.setup.common_start_timesteps > 0
        model_contents["common_timesteps"] = input_data.temporals.t[1:input_data.setup.common_start_timesteps]
    else
        model_contents["common_timesteps"] = []
    end
    if input_data.setup.common_end_timesteps > 0
        model_contents["common_timesteps"] = [model_contents["common_timesteps"] ; input_data.temporals.t[end-input_data.setup.common_end_timesteps+1:end]]
    end
    input_data_dirs = unique(map(m -> m.direction, collect(values(input_data.markets))))
    res_dir = []
    for d in input_data_dirs
        if d == "up" || d == "res_up"
            push!(res_dir, "res_up")
        elseif d == "dw" || d == "res_dw" || d == "dn" || d == "res_dn" || d == "down" || d == "res_down"
            push!(res_dir, "res_down")
        elseif d == "up/down" || d == "up/dw" || d == "up/dn" ||d == "up_down" || d == "up_dw" || d == "up_dn"
            push!(res_dir, "res_up")
            push!(res_dir, "res_down")
        elseif d != "none"
            msg = "Invalid reserve direction given: " * d
            throw(ErrorException(msg))
        end
    end
    model_contents["res_dir"] = unique(res_dir)
    return model_contents
end

function setup_optimizer()
    m = JuMP.Model(HiGHS.Optimizer)
    set_optimizer_attribute(m, "presolve", "on")
    return m
end

function build_model(model_contents::OrderedDict, input_data::Predicer.InputData)
    create_variables(model_contents, input_data)
    create_constraints(model_contents, input_data)
end

function tweak_input!(input_data :: InputData) :: InputData
    # Check input_data
    validation_result = Predicer.validate_data(input_data)
    if !validation_result["is_valid"]
        throw(Predicer.PredicerUserError(validation_result["errors"]))
    end
    # Build market structures
    return Predicer.resolve_market_nodes(input_data)
end

function generate_model(model :: Model, input_data :: InputData)
    # create model_contents
    model_contents = Predicer.build_model_contents_dict(input_data)
    model_contents["model"] = model
    # build model
    Predicer.build_model(model_contents, input_data)
    return model_contents
end

function generate_model(fpath::String, t_horizon::Vector{DateTime}=DateTime[])
    # get input_data
    input_data = Predicer.get_data(fpath, t_horizon) |> tweak_input!
    return generate_model(Predicer.setup_optimizer(), input_data), input_data
end

function generate_model(input_data::InputData)
    input_data = tweak_input!(input_data)
    return generate_model(Predicer.setup_optimizer(), input_data), input_data
end

function solve_model(model_contents::OrderedDict)
    optimize!(model_contents["model"])
end
