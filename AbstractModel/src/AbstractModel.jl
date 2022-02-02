# This file contains the AbstractModel package

module AbstractModel
    using JuMP
    using Cbc
    using DataFrames
    using StatsPlots
    using Plots
    using TimeZones
    using Dates
    using DataStructures
    using XLSX

    include("structures.jl")

    # Run parallell version of AbstractModel. This version is used until it has been implemented
    # as a part of the AbstractModel module. 
    export run_AM
    function run_AM(imported_data)
        return include(".\\AbstractModel\\src\\AM.jl")(imported_data)
    end

    export Initialize
    #export solve_model
    #export set_generic_constraints

    # For debugging
    export create_tuples
    export export_model_contents

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
    function solve_model(model, save_results)
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
        model_contents["genericconstraint"] = OrderedDict() #GenericConstraints
        model_contents["expression"] = OrderedDict() #expressions?
        model_contents["variable"] = OrderedDict() #variables?
        model_contents["tuple"] = OrderedDict() #tuples used by variables?
        model_contents["res_dir"] = ["res_up", "res_down"]
        return model_contents
    end

    # Sets up the tuples, variables, constraints, etc used in the model using smaller functions. These functions 
    # aim to do only one thing, such as create a necessary tuple or create a variable base on a tuple.  
    function setup_model(model_contents, input_data)
        create_tuples(model_contents, input_data)
    end

    # Calls for all tuples to be created and saved in the model dict. 
    function create_tuples(model_contents, input_data)
        create_res_nodes_tuple(model_contents, input_data)
        create_process_tuple(model_contents, input_data)
        create_res_potential_tuple(model_contents, input_data)
        create_proc_potential_tuple(model_contents, input_data)
        create_proc_balance_tuple(model_contents, input_data)
        create_proc_op_balance_tuple(model_contents, input_data)
        create_proc_op_tuple(model_contents, input_data)
        create_op_tuples(model_contents, input_data)
        create_cf_balance_tuple(model_contents, input_data)
        create_lim_tuple(model_contents, input_data)
        create_trans_tuple(model_contents, input_data)
        create_res_tuple(model_contents, input_data)
    end

    # Saves the contents of the model dict to an excel file. 
    function export_model_contents(model_contents)
        output_path = string(pwd()) * "\\debug\\model_contents_"*Dates.format(Dates.now(), "yyyy-mm-dd-HH-MM-SS")*".xlsx"
        XLSX.openxlsx(output_path, mode="w") do xf
            for (key_index, key1) in enumerate(collect(keys(model_contents)))
                XLSX.addsheet!(xf, string(key1))
                if key1 in ["tuple", "variable", "expression", "constraint"] 
                    for (colnr, key2) in enumerate(collect(keys(model_contents[key1])))
                        xf[key_index+1][XLSX.CellRef(1, colnr)] = string(key2)
                        if typeof(model_contents[key1][key2]) == OrderedDict
                            # Iterate through keys of dict with dictname in AffExpr
                            # And key : value pairs in Bx:Nx
                            for (i, key3) in enumerate(collect(keys(model_contents[key1][key2])))
                                xf[key_index+1][XLSX.CellRef(i+1, colnr)]=string(key3)*" : "*string(model_contents[key1][key2][key3])
                            end
                        else
                            # Print name of vector in Ax and values in Bx:Nx
                            for (i, e) in enumerate(model_contents[key1][key2])
                                xf[key_index+1][XLSX.CellRef(i+1, colnr)] = string(e)
                            end
                        end
                    end
                end
            end
        end
    end

    function create_process_tuple(model_contents, input_data)
        process_tuple = []
        processes = input_data["processes"]
        scenarios = input_data["scenarios"]
        temporals = input_data["temporals"]
        for p in keys(processes), s in keys(scenarios), t in temporals
            for topo in processes[p].topos
                push!(process_tuple, (p, topo.source, topo.sink, s, t))
            end
        end
        model_contents["tuple"]["process_tuple"] = process_tuple
    end

    function create_res_potential_tuple(model_contents, input_data)
        res_potential_tuple = []
        processes = input_data["processes"]
        scenarios = input_data["scenarios"]
        temporals = input_data["temporals"]
        res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
        for p in keys(processes), s in keys(scenarios), t in temporals
            for topo in processes[p].topos
                if (topo.source in res_nodes_tuple|| topo.sink in res_nodes_tuple) && processes[p].is_res
                    for r in model_contents["res_dir"]
                        push!(res_potential_tuple, (r, p, topo.source, topo.sink, s, t))
                    end
                end
            end
        end
        model_contents["tuple"]["res_potential_tuple"] = res_potential_tuple
    end

    function create_proc_potential_tuple(model_contents, input_data)
        res_potential_tuple = []
        res_dir = ["res_up", "res_down"]
        processes = input_data["processes"]
        scenarios = input_data["scenarios"]
        temporals = input_data["temporals"]
        res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
        for p in keys(processes), s in keys(scenarios), t in temporals
            for topo in processes[p].topos
                if (topo.source in res_nodes_tuple|| topo.sink in res_nodes_tuple) && processes[p].is_res
                    for r in res_dir
                        push!(res_potential_tuple, (r, p, topo.source, topo.sink, s, t))
                    end
                end
            end
        end
        model_contents["tuple"]["res_potential_tuple"] = res_potential_tuple
    end

    function create_proc_balance_tuple(model_contents, input_data)
        proc_balance_tuple = []
        processes = input_data["processes"]
        scenarios = input_data["scenarios"]
        temporals = input_data["temporals"]
        for p in keys(processes)
            if processes[p].conversion == 1 && !processes[p].is_cf
                if isempty(processes[p].eff_fun)
                    for s in keys(scenarios), t in temporals
                        push!(proc_balance_tuple, (p, s, t))
                    end
                end
            end
        end
        model_contents["tuple"]["proc_balance_tuple"] = proc_balance_tuple
    end

    function create_proc_op_balance_tuple(model_contents, input_data)
        proc_op_balance_tuple = []
        processes = input_data["processes"]
        scenarios = input_data["scenarios"]
        temporals = input_data["temporals"]
        for p in keys(processes)
            if processes[p].conversion == 1 && !processes[p].is_cf
                if !isempty(processes[p].eff_fun)
                    for s in keys(scenarios), t in temporals, o in processes[p].eff_ops
                        push!(proc_op_balance_tuple, (p, s, t, o))
                    end
                end
            end
        end
        model_contents["tuple"]["proc_op_balance_tuple"] = proc_op_balance_tuple
    end

    function create_proc_op_tuple(model_contents, input_data)
        proc_op_tuple = unique(map(x->(x[1],x[2],x[3]),model_contents["tuple"]["proc_op_balance_tuple"]))
        model_contents["tuple"]["proc_op_tuple"] = proc_op_tuple
    end

    function create_op_tuples(model_contents, input_data)
        op_min_tuple = []
        op_max_tuple = []
        op_eff_tuple = []
        processes = input_data["processes"]
        scenarios = input_data["scenarios"]
        temporals = input_data["temporals"]
        for p in keys(processes) 
            if !isempty(processes[p].eff_fun)
                cap = sum(map(x->x.capacity,filter(x->x.source == p,processes[p].topos)))
                for s in keys(scenarios), t in temporals
                    for i in 1:length(processes[p].eff_ops)
                        if i==1
                            push!(op_min_tuple,0.0)
                        else
                            push!(op_min_tuple,processes[p].eff_fun[i-1][1]*cap)
                        end
                        push!(op_max_tuple,processes[p].eff_fun[i][1]*cap)
                        push!(op_eff_tuple,processes[p].eff_fun[i][2])
                    end
                end
            end
        end
        model_contents["tuple"]["op_min_tuple"] = op_min_tuple
        model_contents["tuple"]["op_max_tuple"] = op_max_tuple
        model_contents["tuple"]["op_eff_tuple"] = op_eff_tuple
    end

    function create_cf_balance_tuple(model_contents, input_data)
        cf_balance_tuple = []
        processes = input_data["processes"]
        for p in keys(processes)
            if processes[p].is_cf
                push!(cf_balance_tuple, filter(x -> (x[1] == p), model_contents["tuple"]["process_tuple"])...)
            end
        end
        model_contents["tuple"]["cf_balance_tuple"] = cf_balance_tuple
    end
    
    function create_lim_tuple(model_contents, input_data)
        lim_tuple = []
        processes = input_data["processes"]
        process_tuple = model_contents["tuple"]["process_tuple"]
        res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
        for p in keys(processes)
            if !processes[p].is_cf && (processes[p].conversion == 1)
                push!(lim_tuple, filter(x -> x[1] == p && (x[2] == p || x[2] in res_nodes_tuple), process_tuple)...)
            end
        end
        model_contents["tuple"]["lim_tuple"] = lim_tuple
    end

    function create_trans_tuple(model_contents, input_data)
        trans_tuple = []
        processes = input_data["processes"]
        process_tuple = model_contents["tuple"]["process_tuple"]
        for p in keys(processes)
            if !processes[p].is_cf && processes[p].conversion == 2
                push!(trans_tuple, filter(x -> x[1] == p, process_tuple)...)
            end
        end
        model_contents["tuple"]["lim_tuple"] = trans_tuple
    end

    function create_res_nodes_tuple(model_contents, input_data)
        res_nodes_tuple = []
        markets = input_data["markets"]
        for m in keys(markets)
            if markets[m].type == "reserve"
                push!(res_nodes_tuple, markets[m].node)
            end
        end
        model_contents["tuple"]["res_nodes_tuple"] = res_nodes_tuple
    end

    function create_res_tuple(model_contents, input_data)
        res_tuple = []
        markets = input_data["markets"]
        scenarios = input_data["scenarios"]
        temporals = input_data["temporals"]
        res_dir = model_contents["res_dir"]
        for m in keys(markets)
            if markets[m].type == "reserve"
                if markets[m].direction == "up"
                    for s in keys(scenarios), t in temporals
                        push!(res_tuple, (m, markets[m].node, res_dir[1], s, t))
                    end
                elseif markets[m].direction == "down"
                    for s in keys(scenarios), t in temporals
                        push!(res_tuple, (m, markets[m].node, res_dir[2], s, t))
                    end
                else
                    for s in keys(scenarios), t in temporals
                        push!(res_tuple, (m, markets[m].node, res_dir[1], s, t))
                        push!(res_tuple, (m, markets[m].node, res_dir[2], s, t))
                    end
                end
            end
        end
        model_contents["tuple"]["res_tuple"] = res_tuple
    end







    function read_GenExpr(ge::GenExpr)
        # Reads a GenExpr, and returns the value
        if ge.c_type == AbstractExpr
            c_coeff = read_GenExpr(ge.coeff) #Returns value of nested GenExpr
        elseif ge.c_type <: Real
            c_coeff = ge.coeff
        end
        if ge.e_type == AbstractExpr
            return ge.c_coeff.* read_GenExpr(ge.entity)
        elseif ge.e_type == Process # do different things depending on the datatype of the GenExpr
            pname = ge.entity.name
            tup = model_contents["t"][pname] # This could return all variables associated with the process
            if ge.time_specific
                return c_coeff .* v_flow[filter(t -> t[4] == ge.timestep, tup)]
            else
                return c_coeff .* v_flow[tup]
            end
        elseif ge.e_type == TimeSeries
            if ge.time_specific
                return c_coeff * filter(t -> t[1] == ge.timestep, ge.entity.series)[1][2]
            elseif !ge.time_specific
                return c_coeff .* map(t -> t[2], ge.entity.series)
            end
        elseif ge.e_type <: Real
            return ge.coeff * ge.entity
        end
    end

    function set_gc(gc)
        if !(length(gc.left_f) - length(gc.left_op) == 1)
            return error("Invalid general constraint parameters. Lefthandside invalid")
        elseif !(length(gc.right_f) - length(gc.right_op) == 1)
            return error("Invalid general constraint parameters. Righthandside invalid")
        end
        # Build lefthand side of constraint
        left_expr = @expression(model, read_GenExpr(gc.left_f[1]))
        if length(gc.left_f) > 1
            for ge_i in 2:length(gc.left_expr)
                left_expr = eval(Meta.parse(gc.left_op[i-1]))(left_expr, read_GenExpr(gc.left_f[i]))
            end
        end
        right_expr = @expression(model, read_GenExpr(gc.right_f[1]))
        if length(gc.right_f) > 1
            for ge_i in 2:length(gc.right_expr)
                right_expr = eval(Meta.parse(gc.right_op[i-1]))(right_expr, read_GenExpr(gc.right_f[i]))
            end
        end
        if gc.symbol == ">="
            model_contents["c"]["gcs"][gc.name] = @constraint(model, left_expr .>= right_expr)
        elseif gc.symbol == "=="
            model_contents["c"]["gcs"][gc.name] = @constraint(model, left_expr .== right_expr)
        elseif gc.symbol == "<="
            model_contents["c"]["gcs"][gc.name] = @constraint(model, left_expr .<= right_expr)
        end
    end

    function set_generic_constraints(gcs)
        for gc in gcs
            set_gc(gc)
        end
    end
end