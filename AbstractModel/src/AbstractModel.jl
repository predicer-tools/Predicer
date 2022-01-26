# This file contains the AbstractModel package

module AbstractModel
    using JuMP
    using Cbc
    using DataFrames
    using StatsPlots
    using Plots
    using TimeZones

    include("structures.jl")

    export test_AM

    function test_AM(imported_data)
        return include(".\\AbstractModel\\src\\AM.jl")(imported_data)
    end

    export Initialize
    export Initialize_contents
    export set_generic_constraints

    # Basic settings
    function Initialize()
        model = JuMP.Model(Cbc.Optimizer)
        set_optimizer_attributes(model, "LogLevel" => 1, "PrimalTolerance" => 1e-7)
        return model
    end

    function setup_model(model, temporals, scenarios, nodes, processes, markets)
        model = JuMP.Model(Cbc.Optimizer)
        set_optimizer_attributes(model, "LogLevel" => 1, "PrimalTolerance" => 1e-7)

        model_contents = Initialize_contents()

        return 0

    end

        # Add all constraints, (expressions? and variables?) into a large dictionary for easier access, and being able to use the anonymous notation
    # while still being conveniently accessible. 
    # Alternatively, everything in a one layer solution: model_contents[(type, name)], eg: model_contents[("variable", "v_flow")]
    function Initialize_contents()
        model_contents = Dict()
        model_contents["constraint"] = Dict() #constraints
        model_contents["genericconstraint"] = Dict() #GenericConstraints
        model_contents["expression"] = Dict() #expressions?
        model_contents["variable"] = Dict() #variables?
        model_contents["tuple"] = Dict() #tuples used by variables?
        return model_contents
    end

    function create_process_tuple(model_contents, temporals, scenarios, processes)
        process_tuple = []
        model_contents["tuple"]["process"] = Dict()
        for p in keys(processes)
            p_tup = []
            for t in temporals, s in scenarios
                for topo in processes[p].topos
                    push!(p_tup, (p, topo.source, topo.sink, s, t))
                end
            end
            model_contents["t"]["process"][p] = p_tup
            append!(process_tuple, p_tup)
        end
        return process_tuple
    end

    function create_node_state_tuple(model_contents, temporals, scenarios, nodes)
        node_state_tuple = []
        model_contents["t"]["node_state"] = Dict()
        for n in keys(nodes)
            n_tup = []
            for t in temporals, s in scenarios
                if nodes[n].is_state
                    push!(n_tup, (n, s, t))
                end
            end
            model_contents["t"]["node_state"][n] = n_tup
            append!(node_tuple, n_tup)
        end
        return node_state_tuple
    end

    function create_node_balance_tuple(mode_contents, temporals, scenarios, nodes)
        node_balance_tuple = []
        model_contents["t"]["node_balance"] = Dict()
        for n in nodes
            n_tup = []
            for t in temporals, s in scenarios
                if !(nodes[n].is_commodity) & !(nodes[n].is_market)
                    push!(node_balance_tuple, (n,s, t))
                end
            end
            model_contents["t"]["node_balance"][n] = n_tup
            append!(node_balance_tuple, n_tup)
        end
        return node_balance_tuple
    end

    function solve_model(model)
        optimize!(model)
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