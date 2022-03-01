# This file contains the AbstractModel package

module AbstractModel
    using JuMP
    using Cbc
    using DataFrames
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
    export solve_model
    #export set_generic_constraints

    # For debugging
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
        model_contents["gen_constraints"] = OrderedDict() #GenericConstraints
        model_contents["res_dir"] = ["res_up", "res_down"]
        return model_contents
    end

    # Sets up the tuples, variables, constraints, etc used in the model using smaller functions. These functions 
    # aim to do only one thing, such as create a necessary tuple or create a variable base on a tuple.  
    function setup_model(model_contents, input_data)
        create_tuples(model_contents, input_data)
        create_variables(model_contents, input_data)
        setup_node_balance(model_contents, input_data)
        setup_process_online_balance(model_contents, input_data)
        setup_process_balance(model_contents, input_data)
        setup_processes_limits(model_contents, input_data)
        setup_reserve_balances(model_contents, input_data)
        setup_ramp_constraints(model_contents, input_data)
        setup_fixed_values(model_contents, input_data)
        setup_bidding_constraints(model_contents, input_data)
        setup_generic_constraints(model_contents, input_data)
        setup_cost_calculations(model_contents, input_data)
        setup_objective_function(model_contents, input_data)
    end

    function setup_node_balance(model_contents, input_data)
        model = model_contents["model"]
        process_tuple = model_contents["tuple"]["process_tuple"]
        res_dir = model_contents["res_dir"]
        node_state_tuple = model_contents["tuple"]["node_state_tuple"]
        node_balance_tuple = model_contents["tuple"]["node_balance_tuple"]
        res_tuple = model_contents["tuple"]["res_tuple"]
        v_state = model_contents["variable"]["v_state"]
        v_flow = model_contents["variable"]["v_flow"]
        vq_state_up = model_contents["variable"]["vq_state_up"]
        vq_state_dw = model_contents["variable"]["vq_state_dw"]
        temporals = input_data["temporals"]  
        nodes = input_data["nodes"]
        markets = input_data["markets"]

        # Balance constraints
        # gather data in dicts, e_prod, etc, now point to a Dict()
        e_prod = model_contents["expression"]["e_prod"] = OrderedDict()
        e_cons = model_contents["expression"]["e_cons"] = OrderedDict()
        e_state = model_contents["expression"]["e_state"] = OrderedDict() 
        
        for (i, tu) in enumerate(node_balance_tuple)
            # tu of form (node, scenario, t)
            # process tuple of form (process_name, source, sink, scenario, t)
            cons = filter(x -> (x[2] == tu[1] && x[4] == tu[2] && x[5] == tu[3]), process_tuple)
            prod = filter(x -> (x[3] == tu[1] && x[4] == tu[2] && x[5] == tu[3]), process_tuple)

            # get reserve markets for realisation
            real_up = []
            real_dw = []
            # tu of form (node, scenario, t)
            # res_tuple of form (res_market, node, res_dir, scenario, t)
            resu = filter(x-> x[2] == tu[1] && x[3] == res_dir[1] && x[4] == tu[2] && x[5] == tu[3],res_tuple)
            for ru in resu
                push!(real_up,markets[ru[1]].realisation)
            end
            resd = filter(x-> x[2] == tu[1] && x[3] == res_dir[2] && x[4] == tu[2] && x[5] == tu[3],res_tuple)
            for rd in resd
                push!(real_dw,markets[rd[1]].realisation)
            end
            # Check inflow for node
            if nodes[tu[1]].is_inflow
                inflow_val = filter(x->x[1] == tu[3], filter(x->x.scenario == tu[2],nodes[tu[1]].inflow)[1].series)[1][2]
            else
                inflow_val = 0.0
            end

            v_res = model_contents["variable"]["v_res"]
            if isempty(cons)
                if isempty(resd)
                    cons_expr = @expression(model, -vq_state_dw[tu] + inflow_val)
                else
                    cons_expr = @expression(model, -vq_state_dw[tu] + inflow_val + sum(real_dw .* v_res[resd]))
                end
            else
                if isempty(resd)
                    cons_expr = @expression(model, -sum(v_flow[cons]) - vq_state_dw[tu] + inflow_val)
                else
                    cons_expr = @expression(model, -sum(v_flow[cons]) - vq_state_dw[tu] + inflow_val + sum(real_dw .* v_res[resd]))
                end
            end
            if isempty(prod)
                if isempty(resu)
                    prod_expr = @expression(model, vq_state_up[tu])
                else
                    prod_expr = @expression(model, vq_state_up[tu] - sum(real_up .* v_res[resu]))
                end
            else
                if isempty(resu)
                    prod_expr = @expression(model, sum(v_flow[prod]) + vq_state_up[tu])
                else
                    prod_expr = @expression(model, sum(v_flow[prod]) + vq_state_up[tu] - sum(real_up .* v_res[resu]))
                end
            end
            if nodes[tu[1]].is_state
                if tu[3] == temporals[1]
                    state_expr = @expression(model, v_state[tu])
                else
                    state_expr = @expression(model, v_state[tu] - v_state[node_balance_tuple[i-1]])
                end
            else
                state_expr = 0
            end

            e_prod[tu] = prod_expr
            e_cons[tu] = cons_expr
            e_state[tu] = state_expr
        end
        node_bal_eq = @constraint(model, node_bal_eq[tup in node_balance_tuple], e_prod[tup] + e_cons[tup] == e_state[tup])
        node_state_max_up = @constraint(model, node_state_max_up[tup in node_state_tuple], e_state[tup] <= nodes[tup[1]].state.in_max)
        node_state_max_dw = @constraint(model, node_state_max_dw[tup in node_state_tuple], -e_state[tup] <= nodes[tup[1]].state.out_max)  
        model_contents["constraint"]["node_bal_eq"] = node_bal_eq
        model_contents["constraint"]["node_state_max_up"] = node_state_max_up
        model_contents["constraint"]["node_state_max_dw"] = node_state_max_dw
        for tu in node_state_tuple
            set_upper_bound(v_state[tu], nodes[tu[1]].state.state_max)
        end
    end

    function setup_process_online_balance(model_contents, input_data)
        model = model_contents["model"]
        v_start = model_contents["variable"]["v_start"]
        v_stop = model_contents["variable"]["v_stop"]
        v_online = model_contents["variable"]["v_online"]
        proc_online_tuple = model_contents["tuple"]["proc_online_tuple"]
        processes = input_data["processes"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]

        # Dynamic equations for start/stop online variables
        online_expr = model_contents["expression"]["online_expr"] = OrderedDict()
        for (i,tup) in enumerate(proc_online_tuple)
            if tup[3] == temporals[1]
                # Note - initial online state is assumed 1!
                online_expr[tup] = @expression(model,v_start[tup]-v_stop[tup]-v_online[tup]+1)
            else
                online_expr[tup] = @expression(model,v_start[tup]-v_stop[tup]-v_online[tup]+v_online[proc_online_tuple[i-1]])
            end
        end
        online_dyn_eq =  @constraint(model,online_dyn_eq[tup in proc_online_tuple], online_expr[tup] == 0)
        model_contents["constraint"]["online_dyn_eq"] = online_dyn_eq

        # Minimum online and offline periods
        min_online_rhs = OrderedDict()
        min_online_lhs = OrderedDict()
        min_offline_rhs = OrderedDict()
        min_offline_lhs = OrderedDict()
        for p in keys(processes)
            if processes[p].is_online
                min_online = processes[p].min_online
                min_offline = processes[p].min_offline
                for s in scenarios
                    for t in temporals
                        on_hours = filter(x->0<=Dates.value(convert(Dates.Hour,x-t))<=min_online,temporals)
                        off_hours = filter(x->0<=Dates.value(convert(Dates.Hour,x-t))<=min_offline,temporals)
                        for h in on_hours
                            min_online_rhs[(p, s, t, h)] = v_start[(p,s,t)]
                            min_online_lhs[(p, s, t, h)] = v_online[(p,s,h)]
                        end
                        for h in off_hours
                            min_offline_rhs[(p, s, t, h)] = (1-v_stop[(p,s,t)])
                            min_offline_lhs[(p, s, t, h)] = v_online[(p,s,h)]
                        end
                    end
                end
            end
        end

        min_online_con = @constraint(model, min_online_con[tup in keys(min_online_lhs)], min_online_lhs[tup] >= min_online_rhs[tup])
        min_offline_con = @constraint(model, min_offline_con[tup in keys(min_offline_lhs)], min_offline_lhs[tup] <= min_offline_rhs[tup])

        model_contents["constraint"]["min_online_con"] = min_online_con
        model_contents["constraint"]["min_offline_con"] = min_offline_con

    end

    function setup_process_balance(model_contents, input_data)
        model = model_contents["model"]
        proc_balance_tuple = model_contents["tuple"]["proc_balance_tuple"]
        process_tuple = model_contents["tuple"]["process_tuple"]
        proc_op_tuple = model_contents["tuple"]["proc_op_tuple"]
        proc_op_balance_tuple = model_contents["tuple"]["proc_op_balance_tuple"]
        v_flow = model_contents["variable"]["v_flow"]
        #vq_flow_up = model_contents["variable"]["vq_flow_up"]
        #vq_flow_down = model_contents["variable"]["vq_flow_down"]

        v_flow_op_out = model_contents["variable"]["v_flow_op_out"]
        v_flow_op_in = model_contents["variable"]["v_flow_op_in"]
        v_flow_op_bin = model_contents["variable"]["v_flow_op_bin"]
        processes = input_data["processes"]

        # Fixed efficiency case:
        nod_eff = OrderedDict()
        for tup in proc_balance_tuple
            # fixed eff value
            if isempty(processes[tup[1]].eff_ts)
                eff = processes[tup[1]].eff
            # timeseries based eff
            else
                eff = filter(x->x[1] == tup[3],filter(x->x.scenario == tup[2],processes[tup[1]].eff_ts)[1].series)[1][2]
            end
            sources = filter(x -> (x[1] == tup[1] && x[3] == tup[1] && x[4] == tup[2] && x[5] == tup[3]), process_tuple)
            sinks = filter(x -> (x[1] == tup[1] && x[2] == tup[1] && x[4] == tup[2] && x[5] == tup[3]), process_tuple)
            nod_eff[tup] = sum(v_flow[sinks]) - eff * sum(v_flow[sources])
        end

        process_bal_eq = @constraint(model, process_bal_eq[tup in proc_balance_tuple], nod_eff[tup] == 0)
        model_contents["constraint"]["process_bal_eq"] = process_bal_eq

        # Piecewise linear efficiency curve case:
        op_min = OrderedDict()
        op_max = OrderedDict()
        op_eff = OrderedDict()

        for tup in proc_op_balance_tuple
            p = tup[1]
            cap = sum(map(x->x.capacity,filter(x->x.source == p,processes[p].topos)))

            i = parse(Int64,replace(tup[4], "op"=>""))# Clunky solution, how to improve?
            if i == 1 
                op_min[tup] = 0.0
            else
                op_min[tup] = processes[p].eff_fun[i-1][1]*cap
            end
            op_max[tup] = processes[p].eff_fun[i][1]*cap
            op_eff[tup] = processes[p].eff_fun[i][2]
        end

        flow_op_out_sum = @constraint(model,flow_op_out_sum[tup in proc_op_tuple],sum(v_flow_op_out[filter(x->x[1:3]==tup,proc_op_balance_tuple)]) == sum(v_flow[filter(x->x[2]==tup[1] && x[4] == tup[2] && x[5] == tup[3],process_tuple)]))
        flow_op_in_sum = @constraint(model,flow_op_in_sum[tup in proc_op_tuple],sum(v_flow_op_in[filter(x->x[1:3]==tup,proc_op_balance_tuple)]) == sum(v_flow[filter(x->x[3]==tup[1] && x[4] == tup[2] && x[5] == tup[3],process_tuple)]))
        model_contents["constraint"]["flow_op_out_sum"] = flow_op_out_sum
        model_contents["constraint"]["flow_op_in_sum"] = flow_op_in_sum

        flow_op_lo = @constraint(model,flow_op_lo[tup in proc_op_balance_tuple], v_flow_op_out[tup] >= v_flow_op_bin[tup] .* op_min[tup])
        flow_op_up = @constraint(model,flow_op_up[tup in proc_op_balance_tuple], v_flow_op_out[tup] <= v_flow_op_bin[tup] .* op_max[tup])
        flow_op_ef = @constraint(model,flow_op_ef[tup in proc_op_balance_tuple], v_flow_op_out[tup] == op_eff[tup] .* v_flow_op_in[tup])
        flow_bin = @constraint(model,flow_bin[tup in proc_op_tuple], sum(v_flow_op_bin[filter(x->x[1:3] == tup, proc_op_balance_tuple)]) == 1)
        model_contents["constraint"]["flow_op_lo"] = flow_op_lo
        model_contents["constraint"]["flow_op_up"] = flow_op_up
        model_contents["constraint"]["flow_op_ef"] = flow_op_ef
        model_contents["constraint"]["flow_bin"] = flow_bin

    end

    function setup_processes_limits(model_contents, input_data)
        model = model_contents["model"]
        trans_tuple = model_contents["tuple"]["trans_tuple"]
        lim_tuple = model_contents["tuple"]["lim_tuple"]
        cf_balance_tuple = model_contents["tuple"]["cf_balance_tuple"]
        res_pot_cons_tuple = model_contents["tuple"]["res_pot_cons_tuple"]
        res_pot_prod_tuple = model_contents["tuple"]["res_pot_prod_tuple"]
        v_flow = model_contents["variable"]["v_flow"]
        v_reserve = model_contents["variable"]["v_reserve"]
        v_online = model_contents["variable"]["v_online"]
        processes = input_data["processes"]
        res_typ = collect(keys(input_data["reserve_type"]))
        res_dir = model_contents["res_dir"]

        # Transport processes
        for tup in trans_tuple
            set_upper_bound(v_flow[tup], filter(x -> x.sink == tup[3], processes[tup[1]].topos)[1].capacity)
        end

        # cf processes
        cf_fac_fix = model_contents["expression"]["cf_fac_fix"] = OrderedDict()
        cf_fac_up = model_contents["expression"]["cf_fac_up"] = OrderedDict()
        for tup in cf_balance_tuple
            cf_val = filter(x->x[1] ==  tup[5], filter(x->x.scenario == tup[4],processes[tup[1]].cf)[1].series)[1][2]
            cap = filter(x -> (x.sink == tup[3]), processes[tup[1]].topos)[1].capacity
            if processes[tup[1]].is_cf_fix
                cf_fac_fix[tup] = @expression(model, sum(v_flow[tup]) - cf_val * cap)
            else
                cf_fac_up[tup] = @expression(model, sum(v_flow[tup]) - cf_val * cap)
            end
        end

        cf_fix_bal_eq = @constraint(model, cf_fix_bal_eq[tup in collect(keys(cf_fac_fix))], cf_fac_fix[tup] == 0)
        cf_up_bal_eq = @constraint(model, cf_up_bal_eq[tup in collect(keys(cf_fac_up))], cf_fac_up[tup] <= 0)
        model_contents["constraint"]["cf_fix_bal_eq"] = cf_fix_bal_eq
        model_contents["constraint"]["cf_up_bal_eq"] = cf_up_bal_eq

        # Other
        p_online = filter(x -> processes[x[1]].is_online, lim_tuple)
        p_offline = filter(x -> !(processes[x[1]].is_online), lim_tuple)
        p_reserve_cons = filter(x -> (res_dir[1], res_typ[1], x...) in res_pot_cons_tuple, lim_tuple)
        p_reserve_prod = filter(x -> (res_dir[1], res_typ[1], x...) in res_pot_prod_tuple, lim_tuple)
        p_noreserve = filter(x -> !(x in p_reserve_cons) && !(x in p_reserve_cons), lim_tuple)
        p_all = filter(x -> x in p_online || x in p_reserve_cons || x in p_reserve_prod, lim_tuple)

        # Base expressions as Dict:
        e_lim_max = model_contents["expression"]["e_lim_max"] = OrderedDict()
        e_lim_min = model_contents["expression"]["e_lim_min"] = OrderedDict()
        
        for tup in lim_tuple
            e_lim_max[tup] = AffExpr(0.0)
            e_lim_min[tup] = AffExpr(0.0)
        end

        for tup in p_reserve_prod
            res_up_tup = filter(x->x[1] == "res_up" && x[3:end] == tup,res_pot_prod_tuple)
            add_to_expression!(e_lim_max[tup], sum(v_reserve[(res_up_tup)]))
            res_down_tup = filter(x->x[1] == "res_down" && x[3:end] == tup,res_pot_prod_tuple)
            add_to_expression!(e_lim_min[tup], -sum(v_reserve[(res_down_tup)]))
        end
    
        for tup in p_reserve_cons
            res_up_tup = filter(x->x[1] == "res_down" && x[3:end] == tup,res_pot_cons_tuple)
            add_to_expression!(e_lim_max[tup], sum(v_reserve[(res_up_tup)]))
            res_down_tup = filter(x->x[1] == "res_up" && x[3:end] == tup,res_pot_cons_tuple)
            add_to_expression!(e_lim_min[tup], -sum(v_reserve[(res_down_tup)]))
        end
    
        for tup in p_online
            cap = filter(x->x.sink == tup[3] || x.source == tup[2], processes[tup[1]].topos)[1].capacity
            add_to_expression!(e_lim_max[tup], -processes[tup[1]].load_max * cap * v_online[(tup[1], tup[4], tup[5])])
            add_to_expression!(e_lim_min[tup], -processes[tup[1]].load_min * cap * v_online[(tup[1], tup[4], tup[5])])
        end
    
        for tup in p_offline
            cap = filter(x->x.sink == tup[3] || x.source == tup[2], processes[tup[1]].topos)[1].capacity
            if tup in p_reserve_prod || tup in p_reserve_cons
                add_to_expression!(e_lim_max[tup], -cap)
            else
                set_upper_bound(v_flow[tup], cap)
            end
        end
    
        con_max_tuples = filter(x -> !(e_lim_max[x] == AffExpr(0)), keys(e_lim_max))
        con_min_tuples = filter(x -> !(e_lim_min[x] == AffExpr(0)), keys(e_lim_min))
    
        max_eq = @constraint(model, max_eq[tup in con_max_tuples], v_flow[tup] + e_lim_max[tup] <= 0)
        min_eq = @constraint(model, min_eq[tup in con_min_tuples], v_flow[tup] + e_lim_min[tup] >= 0)
        model_contents["constraint"]["max_eq"] = max_eq
        model_contents["constraint"]["min_eq"] = min_eq
    end

    function setup_reserve_balances(model_contents, input_data)
        model = model_contents["model"]
        res_eq_tuple = model_contents["tuple"]["res_eq_tuple"]
        res_eq_updn_tuple = model_contents["tuple"]["res_eq_updn_tuple"]
        res_potential_tuple = model_contents["tuple"]["res_potential_tuple"]
        res_tuple = model_contents["tuple"]["res_tuple"]
        res_final_tuple = model_contents["tuple"]["res_final_tuple"]
        res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
        res_typ = collect(keys(input_data["reserve_type"]))
        res_dir = model_contents["res_dir"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        markets = input_data["markets"]
        v_reserve = model_contents["variable"]["v_reserve"]
        v_res = model_contents["variable"]["v_res"]
        v_res_final = model_contents["variable"]["v_res_final"]

        # Reserve balances (from reserve potential to reserve product):
        e_res_bal_up = model_contents["expression"]["e_res_bal_up"] = OrderedDict()
        e_res_bal_dn = model_contents["expression"]["e_res_bal_up"] = OrderedDict()
        for n in res_nodes_tuple, r in res_typ, s in scenarios, t in temporals
            tup = (n, r, s, t) # same as res_eq_tuple
            e_res_bal_up[tup] = AffExpr(0.0)
            e_res_bal_dn[tup] = AffExpr(0.0)

            res_pot_u = filter(x -> x[1] == res_dir[1] && x[2] == r && x[6] == s && x[7] == t && (x[4] == n || x[5] == n), res_potential_tuple)
            res_pot_d = filter(x -> x[1] == res_dir[2] && x[2] == r && x[6] == s && x[7] == t && (x[4] == n || x[5] == n), res_potential_tuple)
    
            res_u = filter(x -> x[3] == res_dir[1] && markets[x[1]].reserve_type == r && x[4] == s && x[5] == t && x[2] == n, res_tuple)
            res_d = filter(x -> x[3] == res_dir[2] && markets[x[1]].reserve_type == r && x[4] == s && x[5] == t && x[2] == n, res_tuple)
    
            if !isempty(res_pot_u)
                add_to_expression!(e_res_bal_up[tup], sum(v_reserve[res_pot_u]))
            end
            if !isempty(res_pot_d)
                add_to_expression!(e_res_bal_dn[tup], sum(v_reserve[res_pot_d]))
            end
    
            if !isempty(res_u)
                add_to_expression!(e_res_bal_up[tup], -sum(v_res[res_u]))
            end
            if !isempty(res_d)
                add_to_expression!(e_res_bal_dn[tup], -sum(v_res[res_d]))
            end
        end            

        # res_tuple is the tuple use for v_res (market, n, res_dir, s, t)
        # res_eq_updn_tuple (market, s, t)
        # the previously used tuple is res_eq_tuple, of form (n, rt, s, t)
        res_eq_updn = @constraint(model, res_eq_updn[tup in res_eq_updn_tuple], v_res[(tup[1], markets[tup[1]].node, res_dir[1], tup[2], tup[3])] - v_res[(tup[1], markets[tup[1]].node, res_dir[2], tup[2], tup[3])] == 0)
        res_eq_up = @constraint(model, res_eq_up[tup in res_eq_tuple], e_res_bal_up[tup] == 0)
        res_eq_dn = @constraint(model, res_eq_dn[tup in res_eq_tuple], e_res_bal_dn[tup] == 0)
        model_contents["constraint"]["res_eq_updn"] = res_eq_updn
        model_contents["constraint"]["res_eq_up"] = res_eq_up
        model_contents["constraint"]["res_eq_dn"] = res_eq_dn

        # Final reserve product:
        # res_final_tuple (m, s, t)
        # r_tup = res_tuple = (m, n, res_dir, s, t)
        reserve_final_exp = model_contents["expression"]["reserve_final_exp"] = OrderedDict()
        for tup in res_final_tuple
            r_tup = filter(x -> x[1] == tup[1] && x[4] == tup[2] && x[5] == tup[3], res_tuple)
            reserve_final_exp[tup] = @expression(model, sum(v_res[r_tup]) .* (tup[1] == "fcr_n" ? 0.5 : 1.0) .- v_res_final[tup])
        end
        reserve_final_eq = @constraint(model, reserve_final_eq[tup in res_final_tuple], reserve_final_exp[tup] == 0)
        model_contents["constraint"]["reserve_final_eq"] = reserve_final_eq
    end

    function setup_ramp_constraints(model_contents, input_data)
        model = model_contents["model"]
        ramp_tuple = model_contents["tuple"]["ramp_tuple"]
        process_tuple = model_contents["tuple"]["process_tuple"]
        res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
        res_potential_tuple = model_contents["tuple"]["res_potential_tuple"]
        v_reserve = model_contents["variable"]["v_reserve"]
        v_start = model_contents["variable"]["v_start"]
        v_stop = model_contents["variable"]["v_stop"]
        v_flow = model_contents["variable"]["v_flow"]

        res_dir = model_contents["res_dir"]
        reserve_types = input_data["reserve_type"]
       
        processes = input_data["processes"]
        temporals = input_data["temporals"]


        ramp_expr_up = model_contents["expression"]["ramp_expr_up"] = OrderedDict()
        ramp_expr_down = model_contents["expression"]["ramp_expr_down"] = OrderedDict()


        for tup in process_tuple
            if processes[tup[1]].conversion == 1 && !processes[tup[1]].is_cf
                if tup[5] != temporals[1]
                    ramp_expr_up[tup] = AffExpr(0.0)
                    ramp_expr_down[tup] = AffExpr(0.0)        
                    topo = filter(x -> x.source == tup[2] && x.sink == tup[3], processes[tup[1]].topos)[1]
                    ramp_up_cap = topo.ramp_up * topo.capacity
                    ramp_dw_cap = topo.ramp_down * topo.capacity
                    start_cap = max(0,processes[tup[1]].load_min-topo.ramp_up)*topo.capacity
                    stop_cap = max(0,processes[tup[1]].load_min-topo.ramp_down)*topo.capacity
                    if processes[tup[1]].is_online
                        if processes[tup[1]].is_res
                            res_tup_up = filter(x->x[1]==res_dir[1] && x[3:end]==tup,res_potential_tuple)
                            res_tup_down = filter(x->x[1]==res_dir[2] && x[3:end]==tup,res_potential_tuple)
                            if tup[2] in res_nodes_tuple
                                add_to_expression!(ramp_expr_up[tup], -1 * sum(values(reserve_types) .* v_reserve[res_tup_down]) + ramp_up_cap + start_cap * v_start[(tup[1], tup[4], tup[5])]) 
                                add_to_expression!(ramp_expr_down[tup], sum(values(reserve_types) .* v_reserve[res_tup_up]) - ramp_dw_cap - stop_cap * v_stop[(tup[1], tup[4], tup[5])]) 
                            elseif tup[3] in res_nodes_tuple
                                add_to_expression!(ramp_expr_up[tup], -1 * sum(values(reserve_types) .* v_reserve[res_tup_up]) + ramp_up_cap + start_cap * v_start[(tup[1], tup[4], tup[5])]) 
                                add_to_expression!(ramp_expr_down[tup], sum(values(reserve_types) .* v_reserve[res_tup_down]) - ramp_dw_cap - stop_cap * v_stop[(tup[1], tup[4], tup[5])]) 
                            else
                                add_to_expression!(ramp_expr_up[tup], ramp_up_cap + start_cap * v_start[(tup[1], tup[4], tup[5])]) 
                                add_to_expression!(ramp_expr_down[tup], - ramp_dw_cap - stop_cap * v_stop[(tup[1], tup[4], tup[5])]) 
                            end
                        else
                            add_to_expression!(ramp_expr_up[tup], ramp_up_cap + start_cap * v_start[(tup[1], tup[4], tup[5])]) 
                            add_to_expression!(ramp_expr_down[tup], - ramp_dw_cap - stop_cap * v_stop[(tup[1], tup[4], tup[5])]) 
                        end
                    else
                        if processes[tup[1]].is_res
                            res_tup_up = filter(x->x[1]==res_dir[1] && x[3:end]==tup,res_potential_tuple)
                            res_tup_down = filter(x->x[1]==res_dir[2] && x[3:end]==tup,res_potential_tuple)
                            if tup[2] in res_nodes_tuple
                                add_to_expression!(ramp_expr_up[tup], -sum(values(reserve_types) .* v_reserve[res_tup_down]) + ramp_up_cap) 
                                add_to_expression!(ramp_expr_down[tup], sum(values(reserve_types) .* v_reserve[res_tup_up]) - ramp_dw_cap) 
                            elseif tup[3] in res_nodes_tuple
                                add_to_expression!(ramp_expr_up[tup], -sum(values(reserve_types) .* v_reserve[res_tup_up]) + ramp_up_cap) 
                                add_to_expression!(ramp_expr_down[tup], sum(values(reserve_types) .* v_reserve[res_tup_down]) - ramp_dw_cap) 
                            else
                                add_to_expression!(ramp_expr_up[tup], ramp_up_cap)
                                add_to_expression!(ramp_expr_down[tup], - ramp_dw_cap)
                            end
                        else
                            add_to_expression!(ramp_expr_up[tup], ramp_up_cap)
                            add_to_expression!(ramp_expr_down[tup], - ramp_dw_cap)
                        end
                    end
                end
            end
        end

        ramp_up_eq = @constraint(model, ramp_up_eq[tup in ramp_tuple], v_flow[tup] - v_flow[process_tuple[findall(x->x==tup,process_tuple)[1]-1]] <= ramp_expr_up[tup])
        ramp_down_eq = @constraint(model, ramp_down_eq[tup in ramp_tuple], v_flow[tup] - v_flow[process_tuple[findall(x->x==tup,process_tuple)[1]-1]] >= ramp_expr_down[tup])
        model_contents["constraint"]["ramp_up_eq"] = ramp_up_eq
        model_contents["constraint"]["ramp_down_eq"] = ramp_down_eq
    end

    function setup_fixed_values(model_contents, input_data)
        model = model_contents["model"]
        
        process_tuple = model_contents["tuple"]["process_tuple"]
        fixed_value_tuple = model_contents["tuple"]["fixed_value_tuple"]
        v_flow = model_contents["variable"]["v_flow"]
        v_res_final = model_contents["variable"]["v_res_final"]
        markets = input_data["markets"]
        scenarios = collect(keys(input_data["scenarios"]))
        
        fix_expr = model_contents["expression"]["fix_expr"] = OrderedDict()
        for m in keys(markets)
            if !isempty(markets[m].fixed)
                temps = map(x->x[1],markets[m].fixed)
                fix_vec = map(x->x[2],markets[m].fixed)

                if markets[m].type == "energy"
                    for (t, fix_val) in zip(temps, fix_vec)
                        for s in scenarios
                            tup1 = filter(x->x[2]==m && x[4]==s && x[5]==t,process_tuple)[1]
                            tup2 = filter(x->x[3]==m && x[4]==s && x[5]==t,process_tuple)[1]
                            fix_expr[(m, s, t)] = @expression(model,v_flow[tup1]-v_flow[tup2]-fix_val)
                        end
                    end
                elseif markets[m].type == "reserve"
                    for (t, fix_val) in zip(temps, fix_vec)
                        for s in scenarios
                            fix(v_res_final[(m, s, t)], fix_val; force=true)
                        end
                    end
                end
            end
        end
        fixed_value_eq = @constraint(model, fixed_value_eq[tup in fixed_value_tuple], fix_expr[tup] == 0)
        model_contents["constraint"]["fixed_value_eq"] = fixed_value_eq
    end

    function setup_bidding_constraints(model_contents, input_data)
        model = model_contents["model"]
        markets = input_data["markets"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]

        process_tuple = model_contents["tuple"]["process_tuple"]
        v_res_final = model_contents["variable"]["v_res_final"]
        v_flow = model_contents["variable"]["v_flow"]
        
        price_matr = OrderedDict()
        for m in keys(markets)
            for (i,s) in enumerate(scenarios)
                vec = map(x->x[2],filter(x->x.scenario == s, markets[m].price)[1].series)
                if i == 1
                    price_matr[m] = vec
                else
                    price_matr[m] = hcat(price_matr[m],vec)
                end
            end
        end
        for m in keys(markets)
            for (i,t) in enumerate(temporals)
                s_indx = sortperm((price_matr[m][i,:]))
                if markets[m].type == "energy"
                    for k in 2:length(s_indx)
                        if price_matr[m][s_indx[k]] == price_matr[m][s_indx[k-1]]
                            @constraint(model, v_flow[filter(x->x[3]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k]],process_tuple)[1]]-v_flow[filter(x->x[2]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k]],process_tuple)[1]] == 
                                v_flow[filter(x->x[3]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k-1]],process_tuple)[1]]-v_flow[filter(x->x[2]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k-1]],process_tuple)[1]])
                        else
                            @constraint(model, v_flow[filter(x->x[3]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k]],process_tuple)[1]]-v_flow[filter(x->x[2]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k]],process_tuple)[1]] >= 
                                v_flow[filter(x->x[3]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k-1]],process_tuple)[1]]-v_flow[filter(x->x[2]==markets[m].node && x[5]==t && x[4]==scenarios[s_indx[k-1]],process_tuple)[1]])
                        end
                    end
                elseif markets[m].type == "reserve"
                    for k in 2:length(s_indx)
                        if price_matr[m][s_indx[k]] == price_matr[m][s_indx[k-1]]
                            @constraint(model, v_res_final[(m,scenarios[s_indx[k]],t)] == v_res_final[(m,scenarios[s_indx[k-1]],t)])
                        else
                            @constraint(model, v_res_final[(m,scenarios[s_indx[k]],t)] >= v_res_final[(m,scenarios[s_indx[k-1]],t)])
                        end
    
                    end
                end
            end
        end
    end

    function setup_generic_constraints(model_contents, input_data)
        model = model_contents["model"]
        process_tuple = model_contents["tuple"]["process_tuple"]
        v_flow = model_contents["variable"]["v_flow"]

        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        gen_constraints = input_data["gen_constraints"]

        const_expr = model_contents["gen_constraints"]["expression"] = OrderedDict()
        const_dict = model_contents["gen_constraints"]["constraint"] = OrderedDict()

        for c in keys(gen_constraints)
            const_expr[c] = OrderedDict((s,t) => AffExpr(0.0) for s in scenarios, t in temporals)
            facs = gen_constraints[c].factors
            consta = gen_constraints[c].constant
            eq_dir = gen_constraints[c].type
            for s in scenarios, t in temporals
                add_to_expression!(const_expr[c][(s,t)],filter(x->x[1] == t,filter(x->x.scenario == s,consta)[1].series)[1][2])

                for f in facs
                    p_flow = f.flow
                    tup = filter(x->x[1]==p_flow[1] && (x[2]==p_flow[2] || x[3]==p_flow[2]) && x[4]==s && x[5]==t,process_tuple)[1]
                    fac_data = filter(x->x[1] == t,filter(x->x.scenario == s,f.data)[1].series)[1][2]
                    add_to_expression!(const_expr[c][(s,t)],fac_data,v_flow[tup])
                end
            end 
            if eq_dir == "eq"
                const_dict[c] = @constraint(model,[s in scenarios,t in temporals],const_expr[c][(s,t)]==0.0)
            elseif eq_dir == "gt"
                const_dict[c] = @constraint(model,[s in scenarios,t in temporals],const_expr[c][(s,t)]>=0.0)
            else
                const_dict[c] = @constraint(model,[s in scenarios,t in temporals],const_expr[c][(s,t)]<=0.0)
            end
        end
    end

    function setup_cost_calculations(model_contents, input_data)
        model = model_contents["model"]
        process_tuple = model_contents["tuple"]["process_tuple"]
        proc_online_tuple = model_contents["tuple"]["proc_online_tuple"]
        res_final_tuple = model_contents["tuple"]["res_final_tuple"]
        node_balance_tuple = model_contents["tuple"]["node_balance_tuple"]
        v_flow = model_contents["variable"]["v_flow"]
        v_start = model_contents["variable"]["v_start"]
        v_res_final = model_contents["variable"]["v_res_final"]
        vq_state_up = model_contents["variable"]["vq_state_up"]
        vq_state_dw = model_contents["variable"]["vq_state_dw"]

        scenarios = collect(keys(input_data["scenarios"]))
        nodes = input_data["nodes"]
        markets = input_data["markets"]
        processes = input_data["processes"]

        # Commodity costs and marklet costs
        commodity_costs = model_contents["expression"]["commodity_costs"] = OrderedDict()
        market_costs = model_contents["expression"]["market_costs"] = OrderedDict()
        for s in scenarios
            commodity_costs[s] = AffExpr(0.0)
            market_costs[s] = AffExpr(0.0)
            for n in keys(nodes)
                #Commodity costs:
                if nodes[n].is_commodity
                    flow_tups = filter(x -> x[2] == n && x[4] == s, process_tuple)
                    cost_series = filter(x->x.scenario == s,nodes[n].cost)[1].series
                    # Add to expression for each t found in series
                    for cost in cost_series
                        flow = filter(x -> x[5] == cost[1], flow_tups)
                        add_to_expression!(commodity_costs[s], sum(v_flow[flow]) * cost[2])
                    end
                end
                # Spot-Market costs and profits
                if nodes[n].is_market
                    flow_out = filter(x -> x[2] == n && x[4] == s, process_tuple)
                    flow_in = filter(x -> x[3] == n && x[4] == s, process_tuple)
                    price_series = filter(x->x.scenario == s, markets[n].price)[1].series
                    for price in price_series
                        out = filter(x -> x[5] == price[1], flow_out)
                        in = filter(x -> x[5] == price[1], flow_in)
                        # Assuming what goes into the node is sold and has a negatuive cost
                        add_to_expression!(market_costs[s], sum(v_flow[out]) * price[2] - sum(v_flow[in]) * price[2])
                    end
                end
            end
        end

        # VOM_costs
        vom_costs = model_contents["expression"]["vom_costs"] = OrderedDict()
        for s in scenarios
            vom_costs[s] = AffExpr(0.0)
            for tup in unique(map(x->(x[1],x[2],x[3]),process_tuple))
                vom = filter(x->x.source == tup[2] && x.sink == tup[3], processes[tup[1]].topos)[1].VOM_cost
                if vom != 0
                    flows = filter(x -> x[1:3] == tup && x[4] == s, process_tuple)
                    add_to_expression!(vom_costs[s], sum(v_flow[flows]) * vom)
                end
            end
        end

        # Start costs
        start_costs = model_contents["expression"]["start_costs"] = OrderedDict()
        for s in scenarios
            start_costs[s] = AffExpr(0.0)
            for p in keys(processes)
                start_tup = filter(x->x[1] == p && x[2]==s,proc_online_tuple)
                if !isempty(start_tup)
                    cost = processes[p].start_cost
                    add_to_expression!(start_costs[s], sum(v_start[start_tup]) * cost)
                end
            end
        end

        # Reserve profits:
        reserve_costs = model_contents["expression"]["reserve_costs"] = OrderedDict()
        for s in scenarios
            reserve_costs[s] = AffExpr(0.0)
            for tup in filter(x -> x[2] == s, res_final_tuple)
                price = filter(x->x[1] == tup[3],filter(x->x.scenario == s, markets[tup[1]].price)[1].series)[1][2]
                add_to_expression!(reserve_costs[s],-price*v_res_final[tup])
            end
        end

        # Dummy variable costs
        dummy_costs = model_contents["expression"]["dummy_costs"] = OrderedDict()
        p = 1000000
        # State dummy variables
        # Process balance dummy variables?
        for s in scenarios
            dummy_costs[s] = AffExpr(0.0)
            for tup in node_balance_tuple
                add_to_expression!(dummy_costs[s], sum(vq_state_up[tup])*p + sum(vq_state_dw[tup])*p)
            end
        end


        # Total model costs
        total_costs = model_contents["expression"]["total_costs"] = OrderedDict()
        for s in scenarios
            total_costs[s] = sum(commodity_costs[s] + sum(market_costs[s]) + sum(vom_costs[s]) + sum(reserve_costs[s]) + sum(start_costs[s]) + sum(dummy_costs[s]))
        end
    end

    function setup_objective_function(model_contents, input_data)
        model = model_contents["model"]
        total_costs = model_contents["expression"]["total_costs"]
        scen_p = collect(values(input_data["scenarios"]))
        @objective(model, Min, sum(values(scen_p).*values(total_costs)))
    end

    function create_variables(model_contents, input_data)
        create_v_flow(model_contents)
        create_v_online(model_contents)
        create_v_reserve(model_contents)
        create_v_state(model_contents)
        create_v_flow_op(model_contents)
    end

    function create_v_flow(model_contents)
        process_tuple = model_contents["tuple"]["process_tuple"]
        model = model_contents["model"]
        v_flow = @variable(model, v_flow[tup in process_tuple] >= 0)
        model_contents["variable"]["v_flow"] = v_flow

        #vq_flow_up = @variable(model, v_q_flow_up[tup in process_tuple] >= 0)
        #vq_flow_down = @variable(model, v_q_flow_down[tup in process_tuple] >= 0)
        #model_contents["variable"]["vq_flow_up"] = vq_flow_up
        #model_contents["variable"]["vq_flow_down"] = vq_flow_down
    end

    function create_v_online(model_contents)
        proc_online_tuple = model_contents["tuple"]["proc_online_tuple"]
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

    function create_v_reserve(model_contents)
        model = model_contents["model"]

        res_potential_tuple = model_contents["tuple"]["res_potential_tuple"]
        if !isempty(res_potential_tuple)
           v_reserve = @variable(model, v_reserve[tup in res_potential_tuple] >= 0)
           model_contents["variable"]["v_reserve"] = v_reserve
        end

        res_tuple = model_contents["tuple"]["res_tuple"]
        if !isempty(res_tuple)
            v_res = @variable(model, v_res[tup in res_tuple] >= 0)
            model_contents["variable"]["v_res"] = v_res
        end

        res_final_tuple = model_contents["tuple"]["res_final_tuple"]
        if !isempty(res_final_tuple)
            @variable(model, v_res_final[tup in res_final_tuple] >= 0)
            model_contents["variable"]["v_res_final"] = v_res_final
        end
    end

    function create_v_state(model_contents)
        model = model_contents["model"]
        node_state_tuple = model_contents["tuple"]["node_state_tuple"]
        node_balance_tuple = model_contents["tuple"]["node_balance_tuple"]


        # Node state variable
        v_state = @variable(model, v_state[tup in node_state_tuple] >= 0)
        model_contents["variable"]["v_state"] = v_state

        # Dummy variables for node_states
        vq_state_up = @variable(model, vq_state_up[tup in node_balance_tuple] >= 0)
        vq_state_dw = @variable(model, vq_state_dw[tup in node_balance_tuple] >= 0)
        model_contents["variable"]["vq_state_up"] = vq_state_up
        model_contents["variable"]["vq_state_dw"] = vq_state_dw
    end

    function create_v_flow_op(model_contents)
        model = model_contents["model"]
        proc_op_balance_tuple = model_contents["tuple"]["proc_op_balance_tuple"]
        v_flow_op_in = @variable(model,v_flow_op_in[tup in proc_op_balance_tuple] >= 0)
        v_flow_op_out = @variable(model,v_flow_op_out[tup in proc_op_balance_tuple] >= 0)
        v_flow_op_bin = @variable(model,v_flow_op_bin[tup in proc_op_balance_tuple], Bin)
        model_contents["variable"]["v_flow_op_in"] = v_flow_op_in
        model_contents["variable"]["v_flow_op_out"] = v_flow_op_out
        model_contents["variable"]["v_flow_op_bin"] = v_flow_op_bin
    end


    # Calls for all tuples to be created and saved in the model dict. 
     function create_tuples(model_contents, input_data)
        create_res_nodes_tuple(model_contents, input_data)
        create_res_tuple(model_contents, input_data)
        create_process_tuple(model_contents, input_data)
        create_res_potential_tuple(model_contents, input_data)
        create_proc_online_tuple(model_contents, input_data)
        create_res_pot_prod_tuple(model_contents, input_data)
        create_res_pot_cons_tuple(model_contents, input_data)
        create_node_state_tuple(model_contents, input_data)
        create_node_balance_tuple(model_contents, input_data)
        create_proc_potential_tuple(model_contents, input_data)
        create_proc_balance_tuple(model_contents, input_data)
        create_proc_op_balance_tuple(model_contents, input_data)
        create_proc_op_tuple(model_contents, input_data)
        #create_op_tuples(model_contents, input_data)
        create_cf_balance_tuple(model_contents, input_data)
        create_lim_tuple(model_contents, input_data)
        create_trans_tuple(model_contents, input_data)
        create_res_eq_tuple(model_contents, input_data)
        create_res_eq_updn_tuple(model_contents, input_data)
        create_res_final_tuple(model_contents, input_data)
        create_fixed_value_tuple(model_contents, input_data)
        create_ramp_tuple(model_contents, input_data)
    end

    # Saves the contents of the model dict to an excel file. 
    function export_model_contents(model_contents, results)
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
                end
            end
        end
    end

    function create_res_nodes_tuple(model_contents, input_data)
        res_nodes_tuple = []
        markets = input_data["markets"]
        for m in keys(markets)
            if markets[m].type == "reserve"
                push!(res_nodes_tuple, markets[m].node)
            end
        end
        model_contents["tuple"]["res_nodes_tuple"] = unique(res_nodes_tuple)
    end

    function create_res_tuple(model_contents, input_data)
        res_tuple = []
        markets = input_data["markets"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        res_dir = model_contents["res_dir"]
        for m in keys(markets)
            if markets[m].type == "reserve"
                if markets[m].direction in res_dir
                    for s in scenarios, t in temporals
                        push!(res_tuple, (m, markets[m].node, markets[m].direction, s, t))
                    end
                else
                    for rd in res_dir, s in scenarios, t in temporals
                        push!(res_tuple, (m, markets[m].node, rd, s, t))
                    end
                end
            end
        end
        model_contents["tuple"]["res_tuple"] = res_tuple
    end

    function create_process_tuple(model_contents, input_data)
        process_tuple = []
        processes = input_data["processes"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        for p in keys(processes), s in scenarios, t in temporals
            for topo in processes[p].topos
                push!(process_tuple, (p, topo.source, topo.sink, s, t))
            end
        end
        model_contents["tuple"]["process_tuple"] = process_tuple
    end

    function create_proc_online_tuple(model_contents, input_data)
        proc_online_tuple = []
        processes = input_data["processes"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        for p in keys(processes)
            if processes[p].is_online
                for s in scenarios, t in temporals
                    push!(proc_online_tuple, (p, s, t))
                end
            end
        end
        model_contents["tuple"]["proc_online_tuple"] = proc_online_tuple
    end

    function create_res_pot_prod_tuple(model_contents, input_data)
        res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
        res_potential_tuple = model_contents["tuple"]["res_potential_tuple"]
        res_pot_prod_tuple = filter(x -> x[5] in res_nodes_tuple, res_potential_tuple)
        model_contents["tuple"]["res_pot_prod_tuple"] = res_pot_prod_tuple
    end

    function create_res_pot_cons_tuple(model_contents, input_data)
        res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
        res_potential_tuple = model_contents["tuple"]["res_potential_tuple"]
        res_pot_cons_tuple = filter(x -> x[4] in res_nodes_tuple, res_potential_tuple)
        model_contents["tuple"]["res_pot_cons_tuple"] = res_pot_cons_tuple
    end

    function create_node_state_tuple(model_contents, input_data)
        node_state_tuple = []
        nodes = input_data["nodes"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        for n in keys(nodes)
            if !(nodes[n].is_commodity) & !(nodes[n].is_market) & nodes[n].is_state
                for s in scenarios, t in temporals
                    push!(node_state_tuple, (n, s, t))
                end
            end
        end
        model_contents["tuple"]["node_state_tuple"] = node_state_tuple
    end

    function create_node_balance_tuple(model_contents, input_data)
        node_balance_tuple = []
        nodes = input_data["nodes"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        for n in keys(nodes)
            if !(nodes[n].is_commodity) & !(nodes[n].is_market)
                for s in scenarios, t in temporals
                    push!(node_balance_tuple, (n, s, t))
                end
            end
        end
        model_contents["tuple"]["node_balance_tuple"] = node_balance_tuple
    end

    function create_res_potential_tuple(model_contents, input_data)
        res_potential_tuple = []
        processes = input_data["processes"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
        res_typ = collect(keys(input_data["reserve_type"]))
        for p in keys(processes), s in scenarios, t in temporals
            for topo in processes[p].topos
                if (topo.source in res_nodes_tuple|| topo.sink in res_nodes_tuple) && processes[p].is_res
                    for r in model_contents["res_dir"], rt in res_typ
                        push!(res_potential_tuple, (r, rt, p, topo.source, topo.sink, s, t))
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
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
        res_typ = collect(keys(input_data["reserve_type"]))
        for p in keys(processes), s in scenarios, t in temporals
            for topo in processes[p].topos
                if (topo.source in res_nodes_tuple|| topo.sink in res_nodes_tuple) && processes[p].is_res
                    for r in res_dir, rt in res_typ
                        push!(res_potential_tuple, (r, rt, p, topo.source, topo.sink, s, t))
                    end
                end
            end
        end
        model_contents["tuple"]["res_potential_tuple"] = res_potential_tuple
    end

    function create_proc_balance_tuple(model_contents, input_data)
        proc_balance_tuple = []
        processes = input_data["processes"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        for p in keys(processes)
            if processes[p].conversion == 1 && !processes[p].is_cf
                if isempty(processes[p].eff_fun)
                    for s in scenarios, t in temporals
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
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        for p in keys(processes)
            if processes[p].conversion == 1 && !processes[p].is_cf
                if !isempty(processes[p].eff_fun)
                    for s in scenarios, t in temporals, o in processes[p].eff_ops
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

    #=function create_op_tuples(model_contents, input_data)
        op_min_tuple = []
        op_max_tuple = []
        op_eff_tuple = []
        processes = input_data["processes"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        for p in keys(processes) 
            if !isempty(processes[p].eff_fun)
                cap = sum(map(x->x.capacity,filter(x->x.source == p,processes[p].topos)))
                for s in scenarios, t in temporals
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
    end=#

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
        model_contents["tuple"]["trans_tuple"] = trans_tuple
    end

    function create_res_eq_tuple(model_contents, input_data)
        res_eq_tuple = []
        res_nodes_tuple = model_contents["tuple"]["res_nodes_tuple"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        res_typ = collect(keys(input_data["reserve_type"]))
        for n in res_nodes_tuple, r in res_typ, s in scenarios, t in temporals
            push!(res_eq_tuple, (n, r, s, t))
        end
        model_contents["tuple"]["res_eq_tuple"] = res_eq_tuple
    end

    function create_res_eq_updn_tuple(model_contents, input_data)
        res_eq_updn_tuple = []
        markets = input_data["markets"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        for m in keys(markets), s in scenarios, t in temporals
            if markets[m].direction == "up_down"
                push!(res_eq_updn_tuple, (m, s, t))
            end
        end
        model_contents["tuple"]["res_eq_updn_tuple"] = res_eq_updn_tuple
    end

    function create_res_final_tuple(model_contents, input_data)
        res_final_tuple = []
        markets = input_data["markets"]
        scenarios = collect(keys(input_data["scenarios"]))
        temporals = input_data["temporals"]
        for m in keys(markets)
            if markets[m].type == "reserve"
                for s in scenarios, t in temporals
                    push!(res_final_tuple, (m, s, t))
                end
            end
        end
        model_contents["tuple"]["res_final_tuple"] = res_final_tuple
    end

    function create_fixed_value_tuple(model_contents, input_data)
        fixed_value_tuple = []
        markets = input_data["markets"]
        scenarios = collect(keys(input_data["scenarios"]))
        for m in keys(markets)
            if !isempty(markets[m].fixed) && markets[m].type == "energy"
                temps = map(x->x[1],markets[m].fixed)
                for s in scenarios, t in temps
                    push!(fixed_value_tuple, (m, s, t))
                end
            end
        end
        model_contents["tuple"]["fixed_value_tuple"] = fixed_value_tuple
    end

    function create_ramp_tuple(model_contents, input_data)
        ramp_tuple = []
        processes = input_data["processes"]
        temporals = input_data["temporals"]
        for tup in model_contents["tuple"]["process_tuple"]
            if processes[tup[1]].conversion == 1 && !processes[tup[1]].is_cf
                if tup[5] != temporals[1]
                    push!(ramp_tuple,tup)
                end
            end
        end
        model_contents["tuple"]["ramp_tuple"] = ramp_tuple
    end





 #=    function read_GenExpr(ge::GenExpr)
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

 =#
end