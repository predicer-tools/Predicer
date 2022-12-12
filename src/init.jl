using JuMP
using HiGHS
using DataFrames
using TimeZones
using Dates
using DataStructures
using XLSX


function get_data(fpath::String, t_horizon::Vector{ZonedDateTime}=ZonedDateTime[])
    return import_input_data(fpath, t_horizon)
end

function build_model_contents_dict()
    model_contents = OrderedDict()
    model_contents["constraint"] = OrderedDict() #constraints
    model_contents["expression"] = OrderedDict() #expressions?
    model_contents["variable"] = OrderedDict() #variables?
    model_contents["gen_constraint"] = OrderedDict() #GenericConstraints
    model_contents["gen_expression"] = OrderedDict() #GenericConstraints
    model_contents["res_dir"] = ["res_up", "res_down"]
    return model_contents
end

function setup_optimizer(solver::Any)
    m = JuMP.Model(solver)
    set_optimizer_attribute(m, "presolve", "on")
    return m
end

function build_model(model_contents::OrderedDict, input_data::Predicer.InputData)
    create_variables(model_contents, input_data)
    create_constraints(model_contents, input_data)
end

function Initialize(input_data::Predicer.InputData)
    input_data_check = validate_data(input_data)
    if input_data_check["is_valid"]
        model_contents = Initialize_contents()
        model = init_jump_model(HiGHS.Optimizer)
        model_contents["model"] = model
        setup_model(model_contents, input_data)
        return model_contents
    else
        return input_data_check["errors"]
    end
end

function generate_model(fpath::String, t_horizon::Vector{ZonedDateTime}=ZonedDateTime[])
    # get input_data
    input_data = Predicer.get_data(fpath, t_horizon)
    # Check input_data
    validation_result = Predicer.validate_data(input_data)
    if !validation_result["is_valid"]
        return validation_result["errors"]
    end
    # Resolve potential delays
    if input_data.contains_delay
        input_data = Predicer.resolve_delays(input_data)
    end
    # create mc
    mc = build_model_contents_dict()
    mc["model"] = setup_optimizer(HiGHS.Optimizer)
    # build model
    build_model(mc, input_data)
    return mc, input_data
end

function solve_model(mc)
    optimize!(mc["model"])
end