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
function Initialize(input_data)
    model_contents = Initialize_contents()
    model = init_jump_model(Cbc.Optimizer)
    model_contents["model"] = model
    setup_model(model_contents, input_data)
    return model_contents
end

# Function to run the model built based on the given input data. 
function solve_model(model_contents)
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
    model_contents["tuple"] = OrderedDict() #tuples used by variables?
    model_contents["gen_constraint"] = OrderedDict() #GenericConstraints
    model_contents["gen_expression"] = OrderedDict() #GenericConstraints
    model_contents["res_dir"] = ["res_up", "res_down"]
    return model_contents
end

# Sets up the tuples, variables, constraints, etc used in the model using smaller functions. These functions 
# aim to do only one thing, such as create a necessary tuple or create a variable base on a tuple.  
function setup_model(model_contents, input_data)
    create_tuples(model_contents, input_data)
    create_variables(model_contents, input_data)
    create_constraints(model_contents, input_data)
end

function setup_objective_function(model_contents, input_data)
    model = model_contents["model"]
    total_costs = model_contents["expression"]["total_costs"]
    scen_p = collect(values(input_data["scenarios"]))
    @objective(model, Min, sum(values(scen_p).*values(total_costs)))
end

# Saves the contents of the model dict to an excel file. 
function export_model_contents(model_contents, results)
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