using DataFrames
using XLSX
using DataStructures
using TimeZones

import Predicer

function import_input_data(input_data_path::String, t_horizon::Vector{ZonedDateTime}=ZonedDateTime[])
    system_data, timeseries_data, temps = Predicer.read_xlsx(input_data_path, t_horizon)
    return Predicer.compile_input_data(system_data, timeseries_data, temps)
end

function read_xlsx(input_data_path::String, t_horizon::Vector{ZonedDateTime}=ZonedDateTime[])

    sheetnames_system = ["setup", "nodes", "processes", "groups", "process_topology", "node_diffusion", "node_history", "node_delay", "inflow_blocks", "markets","scenarios","efficiencies", "reserve_type","risk", "cap_ts", "gen_constraint", "constraints", "bid_slots"]
    sheetnames_timeseries = ["cf", "inflow", "market_prices", "reserve_realisation", "reserve_activation_price", "price","eff_ts", "fixed_ts", "balance_prices"]

    system_data = OrderedDict()
    timeseries_data = OrderedDict()
    timeseries_data["scenarios"] = OrderedDict()

    xl = XLSX.readxlsx(input_data_path)

    for sn in sheetnames_system
        system_data[sn] = DataFrame(XLSX.gettable(xl[sn]))
    end

    for sn in sheetnames_timeseries
        timeseries_data[sn] = DataFrame(XLSX.gettable(xl[sn]))
    end

    if !isempty(t_horizon)
        temps = map(ts -> string(ts), t_horizon)
    else
        temps = map(t-> string(ZonedDateTime(t, tz"UTC")), DataFrame(XLSX.gettable(xl["timeseries"])).t)
    end

    return system_data, timeseries_data, temps
end

function compile_input_data(system_data::OrderedDict, timeseries_data::OrderedDict, temps::Vector{String}=String[])

    processes = OrderedDict{String, Predicer.Process}()
    nodes = OrderedDict{String, Predicer.Node}()
    node_diffusion_tuples = []
    node_delay_tuples = []
    node_history = OrderedDict{String, Predicer.NodeHistory}()
    groups = OrderedDict{String, Predicer.Group}()

    markets = OrderedDict{String, Predicer.Market}()
    scens = OrderedDict{String, Float64}()
    reserve_type = OrderedDict{String, Float64}()
    risk = OrderedDict{String, Float64}()
    inflow_blocks = OrderedDict{String, Predicer.InflowBlock}()
    gen_constraints = OrderedDict{String, Predicer.GenConstraint}()
    
    bid_slots = OrderedDict{String, Predicer.BidSlot}()
    

    for i in 1:nrow(system_data["scenarios"])
        scens[system_data["scenarios"][i,1]] = system_data["scenarios"][i,2]
    end

    for i in 1:nrow(system_data["risk"])
        risk[system_data["risk"][i,1]] = system_data["risk"][i,2]
    end

    timeseries_data["scenarios"] = OrderedDict()
    # Divide timeseries data per scenario.
    for k in keys(timeseries_data)
        if k!="scenarios"
            for n in names(timeseries_data[k])
                if n != "t"
                    series_data = map(x -> strip(x), split(n, ","))
                    series = series_data[1]
                    if k == "balance_prices"# balance prices
                        is_balance_prices = true
                        if "up" in series_data  
                            series_direction = "up"
                        else
                            series_direction = "down"
                        end
                        sscens = series_data[3:end]
                    else # other series
                        is_balance_prices = false
                        sscens = series_data[2:end]
                        series_direction = nothing
                    end
                    if "ALL" in sscens || "all" in sscens || "All" in sscens
                        sscens = collect(keys(scens))
                    end
                    for scenario in sscens
                        if is_balance_prices
                            if !(scenario in keys(timeseries_data["scenarios"]))
                                timeseries_data["scenarios"][scenario] = OrderedDict()
                            end
                            if !(k in keys(timeseries_data["scenarios"][scenario]))
                                timeseries_data["scenarios"][scenario][k] = OrderedDict()
                            end
                            if !(series_direction in keys(timeseries_data["scenarios"][scenario][k]))
                                timeseries_data["scenarios"][scenario][k][series_direction] = DataFrame(t=temps)
                            end
                            sub_df = timeseries_data[k]
                            if isempty(temps)
                                timeseries_data["scenarios"][scenario][k][series_direction][!, series] = sub_df[!, n]
                            else
                                timeseries_data["scenarios"][scenario][k][series_direction][!, series] = filter(:t => x -> string(ZonedDateTime(x, tz"UTC")) in temps, sub_df)[!, n]
                            end
                            
                        else
                            if !(scenario in keys(timeseries_data["scenarios"]))
                                timeseries_data["scenarios"][scenario] = OrderedDict()
                            end
                            if !(k in keys(timeseries_data["scenarios"][scenario]))
                                timeseries_data["scenarios"][scenario][k] = DataFrame(t=temps)
                            end
                            sub_df = timeseries_data[k]
                            if isempty(temps)
                                timeseries_data["scenarios"][scenario][k][!, series] = sub_df[!, n]
                            else
                                timeseries_data["scenarios"][scenario][k][!, series] = filter(:t => x -> string(ZonedDateTime(x, tz"UTC")) in temps, sub_df)[!, n]
                            end
                        end
                    end
                end
            end
        end
    end

    for i in 1:nrow(system_data["nodes"])
        n = system_data["nodes"][i, :]
        nodes[n.node] = Predicer.Node(n.node)
        if Bool(n.is_commodity)
            Predicer.convert_to_commodity(nodes[n.node])
            for s in keys(scens)
                timesteps = timeseries_data["scenarios"][s]["price"].t
                prices = timeseries_data["scenarios"][s]["price"][!, n.node]
                ts = Predicer.TimeSeries(s, timesteps, prices)
                Predicer.add_cost(nodes[n.node], ts)
            end
        end
        if Bool(n.is_inflow)
            for s in keys(scens)
                timesteps = timeseries_data["scenarios"][s]["inflow"].t
                flows = timeseries_data["scenarios"][s]["inflow"][!, n.node]
                ts = Predicer.TimeSeries(s, timesteps, flows)
                Predicer.add_inflow(nodes[n.node], ts)
            end
        end
        if Bool(n.is_state)
            Predicer.add_state(nodes[n.node], Predicer.State(n.in_max, n.out_max, n.state_loss_proportional, n.state_max, n.state_min, n.initial_state, n.scenario_independent_state, n.is_temp, n.T_E_conversion, n.residual_value))
        end
        if Bool(n.is_res)
            Predicer.add_node_to_reserve(nodes[n.node])
        end
    end

    for i in 1:nrow(system_data["node_diffusion"])
        row = system_data["node_diffusion"][i, :]
        tup = (row.node1, row.node2, row.diff_coeff)
        push!(node_diffusion_tuples, tup)
    end

    for i in 1:nrow(system_data["node_delay"])
        row = system_data["node_delay"][i, :]
        tup = (row.node1, row.node2, row.delay_t, row.min_flow, row.max_flow)
        push!(node_delay_tuples, tup)
    end

    for i in 1:nrow(system_data["processes"])
        p = system_data["processes"][i, :]
        if p.conversion == 1
            processes[p.process] = Predicer.Process(p.process, 1)
        elseif p.conversion == 2
            processes[p.process] = Predicer.TransferProcess(p.process)
        elseif p.conversion == 3
            processes[p.process] = Predicer.MarketProcess(p.process)
        end
        Predicer.add_load_limits(processes[p.process], Float64(p.load_min), Float64(p.load_max))
        Predicer.add_eff(processes[p.process], Float64(p.eff))
        if Bool(p.is_cf)
            for s in keys(scens)
                timesteps = timeseries_data["scenarios"][s]["cf"].t
                cf = timeseries_data["scenarios"][s]["cf"][!, p.process]
                ts = Predicer.TimeSeries(s, timesteps, cf)
                Predicer.add_cf(processes[p.process], ts, Bool(p.is_cf_fix))
            end
        end
        sources = []
        sinks = []
        for j in 1:nrow(system_data["process_topology"])
            pt = system_data["process_topology"][j, :]
            if pt.process == p.process
                if pt.source_sink == "source"
                    push!(sources, (pt.node, pt.capacity, pt.VOM_cost, pt.ramp_up, pt.ramp_down, pt.initial_load, pt.initial_flow))
                elseif pt.source_sink == "sink"
                    push!(sinks, (pt.node, pt.capacity, pt.VOM_cost, pt.ramp_up, pt.ramp_down, pt.initial_load, pt.initial_flow))
                end
            end
        end
        if p.conversion == 1
            for so in sources
                Predicer.add_topology(processes[p.process], Predicer.Topology(so[1], p.process, Float64(so[2]), Float64(so[3]), Float64(so[4]), Float64(so[5]), Float64(so[6]), Float64(so[7])))
            end
            for si in sinks
                Predicer.add_topology(processes[p.process], Predicer.Topology(p.process, si[1], Float64(si[2]), Float64(si[3]), Float64(si[4]), Float64(si[5]), Float64(si[6]), Float64(si[7])))
            end
        elseif p.conversion == 2
            for so in sources, si in sinks
                Predicer.add_topology(processes[p.process], Predicer.Topology(so[1], si[1], Float64(min(so[2], si[2])), Float64(si[3]), Float64(si[4]), Float64(si[5]), Float64(si[6]), Float64(si[7])))
            end
        elseif p.conversion == 3
            for so in sources, si in sinks
                Predicer.add_topology(processes[p.process], Predicer.Topology(so[1], si[1], Float64(min(so[2], si[2])), Float64(so[3]), Float64(si[4]), Float64(si[5]), Float64(si[6]), Float64(so[7])))
                Predicer.add_topology(processes[p.process], Predicer.Topology(si[1], so[1], Float64(min(so[2], si[2])), Float64(si[3]), Float64(si[4]), Float64(si[5]), Float64(si[6]), Float64(so[7])))
            end
        end
        if Bool(p.is_res)
            Predicer.add_process_to_reserve(processes[p.process]) 
        end
        if Bool(p.is_online)
            Predicer.add_online(processes[p.process], Float64(p.start_cost), Float64(p.min_online), Float64(p.min_offline), Float64(p.max_online), Float64(p.max_offline), Bool(p.initial_state), Bool(p.scenario_independent_online))
        end
    end
    
    for n in names(system_data["cap_ts"])
        timesteps = map(x -> string(ZonedDateTime(x, tz"UTC")), system_data["cap_ts"].t)
        if n != "t"
            col = split(n,",")
            proc = col[1]
            nod = col[2]
            scen = col[3]
            data = system_data["cap_ts"][!,n]
            ts = Predicer.TimeSeries(scen, timesteps, data)
            push!(filter(x->x.source==nod || x.sink==nod,processes[proc].topos)[1].cap_ts, ts)
        end
    end

    for i in 1:nrow(system_data["groups"])
        d_row = system_data["groups"][i, :]
        gtype = d_row.type
        gname = d_row.group
        if gtype == "node" || gtype == "Node" || gtype == "NODE" || gtype == "n"
            if !(gname in collect(keys(groups)))
                groups[gname] = Predicer.NodeGroup(gname, d_row.entity)
            else
                add_group_members(groups[gname], d_row.entity)
            end
            add_group(nodes[d_row.entity], gname)
        else
            if !(d_row.group in collect(keys(groups)))
                groups[gname] = Predicer.ProcessGroup(gname, d_row.entity)
            else
                add_group_members(groups[gname], d_row.entity)
            end
            add_group(processes[d_row.entity], gname)
        end
    end

    # Get piecewise efficiencies from the input data.
    #-------------------------------------------
    # Get name of processes defined in the input data
    ps = unique(map(x->strip(split(x,",")[1]), system_data["efficiencies"].process))
    for p in ps
        p_data = filter(:process => x -> strip(split(x, ",")[1]) == p, system_data["efficiencies"])
        if nrow(p_data) != 2
            return error("Piecewise efficiency in input data encountered wrong number of input values for: "*p)
        end
        p_op_df = filter(:process => p -> strip(split(p, ",")[2]) == "op", p_data)
        p_eff_df = filter(:process => p -> strip(split(p, ",")[2]) == "eff", p_data)
        p_ops = filter(x -> typeof(x) != Missing, collect(i for i in p_op_df[1, 2:end]))
        p_effs = filter(x -> typeof(x) != Missing, collect(i for i in p_eff_df[1, 2:end]))
        if length(p_ops) != length(p_effs)
            return error("Defined operation/efficiency points for " * p *" are not the same length")
        end
        for i in 1:length(p_ops)
            if i < length(p_ops)
                if p_effs[i] != p_effs[i+1]
                    push!(processes[p].eff_fun, (p_ops[i], p_effs[i]))
                end
            else
                push!(processes[p].eff_fun, (p_ops[i], p_effs[i]))
            end
        end
        for j in 1:length(processes[p].eff_fun)
            push!(processes[p].eff_ops, "op"*string(j))
        end
    end

    # node history
    if length(names(system_data["node_history"])) > 1
        ns = names(system_data["node_history"])[2:end]
        ns_with_all = filter(x -> occursin("ALL", x) || !occursin("ALL", x) || !occursin("ALL", x), ns)
        ns_without_all = filter(x -> !occursin("ALL", x) || !occursin("ALL", x) || !occursin("ALL", x), ns)
        unique_nodenames_without_all = unique(map(x -> x[1], map(n -> map(x -> strip(x), split(n, ",")), ns_without_all)))
        unique_nodenames_with_all = unique(map(x -> x[1], map(n -> map(x -> strip(x), split(n, ",")), ns_with_all)))
        unique_scenarios_without_all = unique(map(x -> x[end], map(n -> map(x -> strip(x), split(n, ",")), ns_without_all)))

        for n in unique_nodenames_with_all
            node_history[n] = NodeHistory(n)
            cols = filter(x -> n == strip(split(x, ",")[1]), ns)

            if length(cols) != 2
                return Error("Invalid amount of columns for node: ", n, " and scenario: ", s, "!")
            else
                ts = []
                vals = []
                for c in cols
                    if length(split(c, ",")) == 3 # this column has the timesteps. 
                        raw_ts = filter(x -> typeof(x) != Missing, system_data["node_history"][!, c])
                        ts = map(t-> string(ZonedDateTime(t, tz"UTC")), raw_ts)
                    elseif length(split(c, ",")) == 2 # this columnn has the values. 
                        vals = filter(x -> typeof(x) != Missing, system_data["node_history"][!, c])
                    end
                end
                if isempty(ts) || isempty(vals) || length(ts) != length(vals)
                    return Error("Invalid node history column lengths for node: ", n, " and scenario: ", s, ".")
                else
                    for s in collect(keys(scens))
                        t_series = TimeSeries(s, ts, vals)
                        push!(node_history[n].steps, t_series)
                    end
                end
            end
        end
        for n in unique_nodenames_without_all
            node_history[n] = NodeHistory(n)
            for s in unique_scenarios_without_all
                cols = filter(x -> n == strip(split(x, ",")[1]) &&  s == strip(split(x, ",")[end]), ns)
                if length(cols) != 2
                    return Error("Invalid amount of columns for node: ", n, " and scenario: ", s, "!")
                else
                    ts = []
                    vals = []
                    for c in cols
                        if length(split(c, ",")) == 3 # this column has the timesteps. 
                            raw_ts = filter(x -> typeof(x) != Missing, system_data["node_history"][!, c])
                            ts = map(t-> string(ZonedDateTime(t, tz"UTC")), raw_ts)
                        elseif length(split(c, ",")) == 2 # this columnn has the values. 
                            vals = filter(x -> typeof(x) != Missing, system_data["node_history"][!, c])
                        end
                    end
                    if isempty(ts) || isempty(vals) || length(ts) != length(vals)
                        return Error("Invalid node history column lengths for node: ", n, " and scenario: ", s, ".")
                    else
                        t_series = TimeSeries(s, ts, vals)
                        push!(node_history[n].steps, t_series)
                    end
                end
            end
        end
    end

    # inflow blocks NEW
    if length(names(system_data["inflow_blocks"])) > 1
        ns = names(system_data["inflow_blocks"])[2:end]
        colnames = map(n -> map(x -> strip(x), split(n, ",")), ns)
        blocknames = filter(x->!(x[2] in collect(keys(scens))),colnames)
        for bn in blocknames
            inflow_blocks[String(bn[1])] = InflowBlock(String(bn[1]), String(bn[2]))
        end
        for b in collect(keys(inflow_blocks))
            t_col = collect(skipmissing(system_data["inflow_blocks"][!,inflow_blocks[b].name*","*inflow_blocks[b].node]))
            inflow_blocks[b].start_time = string(ZonedDateTime(t_col[1], tz"UTC"))
            for s in collect(keys(scens))
                s_col = collect(skipmissing(system_data["inflow_blocks"][!,inflow_blocks[b].name*","*s]))
                if length(t_col) != length(s_col)
                    msg = "The data columns of the inflow block " * String(b) * " are not the same length!"
                    throw(ErrorException(msg))
                end
                series = TimeSeries(
                    s, string.(ZonedDateTime.(t_col, tz"UTC")), s_col)
                push!(inflow_blocks[b].data,series)
            end
        end
    end

    for s in keys(scens)
        if "eff_ts" in collect(keys(timeseries_data["scenarios"][s]))
            timesteps = timeseries_data["scenarios"][s]["eff_ts"].t
            for n in names(timeseries_data["scenarios"][s]["eff_ts"])[2:end]
                mps = timeseries_data["scenarios"][s]["eff_ts"][!,n]
                ts = Predicer.TimeSeries(s, timesteps, mps)
                push!(processes[n].eff_ts, ts)
            end
        end
    end

    for i in 1:nrow(system_data["reserve_type"])
        tt = system_data["reserve_type"][i,:]
        reserve_type[tt.type] = tt.ramp_factor
    end

    #-----------------------------------------------
   
    for i in 1:nrow(system_data["markets"])
        mm = system_data["markets"][i, :]
        markets[mm.market] = Predicer.Market(mm.market, mm.type, mm.node, mm.processgroup, mm.direction, mm.reserve_type, mm.is_bid, mm.is_limited, mm.min_bid, mm.max_bid, mm.fee)
        #
        for s in keys(scens)
            timesteps = timeseries_data["scenarios"][s]["market_prices"].t
            mps = timeseries_data["scenarios"][s]["market_prices"][!, mm.market]
            ts = Predicer.TimeSeries(s, timesteps, mps)
            push!(markets[mm.market].price, ts)
        end
        if mm.market in names(timeseries_data["fixed_ts"])
            timestamps = timeseries_data["fixed_ts"].t
            data = timeseries_data["fixed_ts"][!,mm.market]
            for i in 1:length(timestamps)
                if !ismissing(data[i])
                    tup = (timestamps[i],data[i])
                    push!(markets[mm.market].fixed,tup)
                end
            end
        end
        if mm.type == "energy" && mm.is_bid == true
            for s in keys(scens)
                timesteps = timeseries_data["scenarios"][s]["balance_prices"]["up"].t
                up_data = timeseries_data["scenarios"][s]["balance_prices"]["up"][!, mm.market]
                down_data = timeseries_data["scenarios"][s]["balance_prices"]["down"][!, mm.market]
                up_ts = Predicer.TimeSeries(s, timesteps, up_data)
                down_ts = Predicer.TimeSeries(s, timesteps, down_data)
 
                push!(markets[mm.market].up_price, up_ts)
                push!(markets[mm.market].down_price, down_ts)
            end
        elseif mm.type == "reserve"
            for s in keys(scens)
                timesteps = timeseries_data["scenarios"][s]["reserve_realisation"].t
                rrs = timeseries_data["scenarios"][s]["reserve_realisation"][!, mm.market]
                ts = Predicer.TimeSeries(s)
                for i in 1:length(timesteps)
                    tup = (timesteps[i], rrs[i],)
                    push!(ts.series, tup)
                end
                push!(markets[mm.market].realisation.ts_data, ts)
            end
            for s in keys(scens)
                timesteps = timeseries_data["scenarios"][s]["reserve_activation_price"].t
                rap = timeseries_data["scenarios"][s]["reserve_activation_price"][!, mm.market]
                ts = Predicer.TimeSeries(s)
                for i in 1:length(timesteps)
                    tup = (timesteps[i], rap[i],)
                    push!(ts.series, tup)
                end
                push!(markets[mm.market].reserve_activation_price.ts_data, ts)
            end
        end
    end

    #---market bid slot----------------------------------

    if length(names(system_data["bid_slots"])) > 1
        system_data["bid_slots"].t = string.(ZonedDateTime.(system_data["bid_slots"].t, tz"UTC"))
        ns = names(system_data["bid_slots"])[2:end]
        market_names = unique(map(n -> map(x -> strip(x), split(n, ","))[1], ns))
        time_steps = system_data["bid_slots"].t

        for m in market_names
            price_dict = OrderedDict()
            alloc_dict = OrderedDict()
            slot_names = unique(map(x->x[2],filter(x->x[1]==m,map(n -> map(x -> strip(x), split(n, ",")), ns))))
            for s in slot_names
                for (i,t) in enumerate(time_steps)
                    tup = (t,string(s))
                    price_dict[tup]=system_data["bid_slots"][i,string(m*","*s)]
                end
            end
            prices = markets[m].price
            for (i,t) in enumerate(time_steps)
                bid_vec = collect(system_data["bid_slots"][i,filter(x->split(x,",")[1]==m,ns)])
                for s in keys(scens)
                    alloc_dict[s,t] = (slot_names[searchsorted(bid_vec,prices(s,t)).stop],slot_names[searchsorted(bid_vec,prices(s,t)).start])
                end
            end

            bid_slots[m] = BidSlot(m,time_steps,slot_names,price_dict,alloc_dict)
        end
    end


    #---


    for i in 1:nrow(system_data["constraints"])
        con = system_data["constraints"][i,1]
        con_dir = system_data["constraints"][i,2]
        is_setpoint = Bool(system_data["constraints"][i,3])
        penalty = Float64(system_data["constraints"][i,4])
        gen_constraints[con] = Predicer.GenConstraint(con,con_dir, is_setpoint, penalty)
    end

    con_vecs = OrderedDict()
    for n in names(system_data["gen_constraint"])
        timesteps = map(t-> string(ZonedDateTime(t, tz"UTC")), system_data["gen_constraint"].t)
        if n != "t"
            col = map(substr -> strip(substr), split(n,","))
            constr = col[1]
            scen = col[end]
            data = system_data["gen_constraint"][!,n]
            ts = Predicer.TimeSeries(scen, timesteps, data)
            if length(col) == 4 # This means it is a flow variable
                tup = ("flow", col[1],col[2],col[3])
                if tup in keys(con_vecs)
                    push!(con_vecs[tup],ts)
                else
                    con_vecs[tup] = []
                    push!(con_vecs[tup],ts)
                end
            elseif length(col) == 3 # This means it is either an online variable or a state variable
                if col[2] in collect(keys(nodes))
                    tup = ("state", col[1],col[2])
                elseif col[2] in collect(keys(processes))
                    tup = ("online", col[1],col[2])
                end
                if tup in keys(con_vecs)
                    push!(con_vecs[tup],ts)
                else
                    con_vecs[tup] = []
                    push!(con_vecs[tup],ts)
                end
            else
                push!(gen_constraints[constr].constant,ts)
            end
        end
    end

    for k in keys(con_vecs)
        if k[1] == "flow"
            con_fac = Predicer.FlowConFactor((k[3],k[4]))
        elseif k[1] == "online"
            con_fac = Predicer.OnlineConFactor((k[3],""))
        elseif k[1] == "state"
            con_fac = Predicer.StateConFactor((k[3],""))
        end
        push!(con_fac.data, con_vecs[k]...)
        push!(gen_constraints[k[2]].factors,con_fac)
    end
    
    
    contains_online = (true in map(p -> p.is_online, collect(values(processes))))
    contains_states = (true in map(n -> n.is_state, collect(values(nodes))))
    contains_piecewise_eff = (false in map(p -> isempty(p.eff_ops), collect(values(processes))))
    contains_risk = (risk["beta"] > 0)
    contains_diffusion = !isempty(node_diffusion_tuples)
    contains_delay = !isempty(node_delay_tuples)
    contains_markets = !isempty(markets)


    use_market_bids = Bool(filter(x -> x.parameter == "use_market_bids", eachrow(system_data["setup"]))[1].value)
    contains_reserves = Bool(filter(x -> x.parameter == "use_reserves", eachrow(system_data["setup"]))[1].value)
    if contains_reserves
        contains_reserves = (true in map(n -> n.is_res, collect(values(nodes))))
    end
    reserve_realisation = Bool(filter(x -> x.parameter == "use_reserve_realisation", eachrow(system_data["setup"]))[1].value)
    use_node_dummy_variables = Bool(filter(x -> x.parameter == "use_node_dummy_variables", eachrow(system_data["setup"]))[1].value)
    use_ramp_dummy_variables = Bool(filter(x -> x.parameter == "use_ramp_dummy_variables", eachrow(system_data["setup"]))[1].value)
    node_dummy_variable_cost = Float64(filter(x -> x.parameter == "node_dummy_variable_cost", eachrow(system_data["setup"]))[1].value)
    ramp_dummy_variable_cost = Float64(filter(x -> x.parameter == "ramp_dummy_variable_cost", eachrow(system_data["setup"]))[1].value)
    common_timesteps = Int(filter(x -> x.parameter == "common_timesteps", eachrow(system_data["setup"]))[1].value)
    common_scenario_name_p = filter(x -> x.parameter == "common_scenario_name", eachrow(system_data["setup"]))[1]
    if ismissing(common_scenario_name_p.value)
        common_scenario_name = ""
    else
        common_scenario_name = common_scenario_name_p.value
    end

    setup = InputDataSetup(contains_reserves, contains_online, contains_states, contains_piecewise_eff, contains_risk, contains_diffusion, contains_delay, contains_markets, 
        reserve_realisation, use_market_bids, common_timesteps, common_scenario_name, use_node_dummy_variables, use_ramp_dummy_variables, node_dummy_variable_cost, ramp_dummy_variable_cost)

    return  Predicer.InputData(Predicer.Temporals(unique(sort(temps))), setup, processes, nodes, node_diffusion_tuples, node_delay_tuples, node_history, markets, groups, scens, reserve_type, risk, inflow_blocks, bid_slots, gen_constraints)
end