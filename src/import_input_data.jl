using DataFrames
using XLSX
using DataStructures
using TimeZones
import Predicer

function import_input_data()
    sheetnames_system = ["nodes", "processes", "process_topology", "markets","scenarios","efficiencies", "reserve_type","risk"]#, "energy_market", "reserve_market"]
    sheetnames_timeseries = ["cf", "inflow", "market_prices", "price","eff_ts"]
    # Assuming this file is under \predicer\model
    wd = split(string(@__DIR__), "src")[1]
    input_data_path = wd * "input_data\\input_data.xlsx"
    

    system_data = OrderedDict()
    timeseries_data = OrderedDict()
    timeseries_data["scenarios"] = OrderedDict()

    processes = OrderedDict{String, Predicer.Process}()
    nodes = OrderedDict{String, Predicer.Node}()
    markets = OrderedDict{String, Predicer.Market}()
    scenarios = OrderedDict{String, Float64}()
    reserve_type = OrderedDict{String, Float64}()
    risk = OrderedDict{String, Float64}()
    gen_constraints = OrderedDict{String, Predicer.GenConstraint}()

    for sn in sheetnames_system
        system_data[sn] = DataFrame(XLSX.readtable(input_data_path, sn)...)
    end

    for sn in sheetnames_timeseries
        timeseries_data[sn] = DataFrame(XLSX.readtable(input_data_path, sn)...)
    end

    temps = map(t-> string(ZonedDateTime(t, tz"Europe/Helsinki")), DataFrame(XLSX.readtable(input_data_path, "timeseries")...).t)

    fixed_data = DataFrame(XLSX.readtable(input_data_path, "fixed_ts")...)
    cap_ts = DataFrame(XLSX.readtable(input_data_path, "cap_ts")...)    
    constraint_data = DataFrame(XLSX.readtable(input_data_path, "gen_constraint")...) 
    constraint_type = DataFrame(XLSX.readtable(input_data_path, "constraints")...)


    for i in 1:nrow(system_data["scenarios"])
        scenarios[system_data["scenarios"][i,1]] = system_data["scenarios"][i,2]
    end

    for i in 1:nrow(system_data["risk"])
        risk[system_data["risk"][i,1]] = system_data["risk"][i,2]
    end
    


    # Divide timeseries data per scenario.
    for k in keys(timeseries_data)
        if k!="scenarios"
            for n in names(timeseries_data[k])
                if n != "t"
                    series = split(n, ",")[1]
                    scens = map(x -> strip(x), split(n, ",")[2:end])
                    if "ALL" in scens
                        scens = collect(keys(scenarios))
                    end
                    for scenario in scens
                        if !(scenario in keys(timeseries_data["scenarios"]))
                            timeseries_data["scenarios"][scenario] = OrderedDict()
                        end
                        if !(k in keys(timeseries_data["scenarios"][scenario]))
                            timeseries_data["scenarios"][scenario][k] = DataFrame(t=timeseries_data[k].t)
                        end
                        timeseries_data["scenarios"][scenario][k][!, series] = timeseries_data[k][!, n]
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
            for s in keys(scenarios)
                timesteps = map(t-> string(ZonedDateTime(t, tz"Europe/Helsinki")), timeseries_data["scenarios"][s]["price"].t)
                prices = timeseries_data["scenarios"][s]["price"][!, n.node]
                ts = Predicer.TimeSeries(s)
                for i in 1:length(timesteps)
                    tup = (timesteps[i], prices[i],)
                    push!(ts.series, tup)
                end
                Predicer.add_cost(nodes[n.node], ts)
            end
        elseif Bool(n.is_market)
            Predicer.convert_to_market(nodes[n.node])
        end
        if Bool(n.is_inflow)
            for s in keys(scenarios)
                timesteps = map(t-> string(ZonedDateTime(t, tz"Europe/Helsinki")), timeseries_data["scenarios"][s]["inflow"].t)
                flows = timeseries_data["scenarios"][s]["inflow"][!, n.node]
                ts = Predicer.TimeSeries(s)
                for i in 1:length(timesteps)
                    tup = (timesteps[i], flows[i],)
                    push!(ts.series, tup)
                end
                Predicer.add_inflow(nodes[n.node], ts)
            end
        end
        if Bool(n.is_state)
            Predicer.add_state(nodes[n.node], Predicer.State(n.in_max, n.out_max, n.state_loss_proportional, n.state_max, 0.0, n.initial_state, n.residual_value))
        end
        if Bool(n.is_res)
            Predicer.add_node_to_reserve(nodes[n.node])
        end
    end
    

    for i in 1:nrow(system_data["processes"])
        p = system_data["processes"][i, :]
        if p.conversion == 1
            processes[p.process] = Predicer.Process(p.process)
        elseif p.conversion == 2
            processes[p.process] = Predicer.TransferProcess(p.process)
        elseif p.conversion == 3
            processes[p.process] = Predicer.MarketProcess(p.process)
        end
        Predicer.add_load_limits(processes[p.process], Float64(p.load_min), Float64(p.load_max))
        Predicer.add_eff(processes[p.process], Float64(p.eff))
        if Bool(p.is_cf)
            for s in keys(scenarios)
                timesteps = map(t-> string(ZonedDateTime(t, tz"Europe/Helsinki")), timeseries_data["scenarios"][s]["cf"].t)
                cf = timeseries_data["scenarios"][s]["cf"][!, p.process]
                ts = Predicer.TimeSeries(s)
                for i in 1:length(timesteps)
                    tup = (timesteps[i], cf[i],)
                    push!(ts.series, tup)
                end
                Predicer.add_cf(processes[p.process], ts, Bool(p.is_cf_fix))
            end
        end
        sources = []
        sinks = []
        for j in 1:nrow(system_data["process_topology"])
            pt = system_data["process_topology"][j, :]
            if pt.process == p.process
                if pt.source_sink == "source"
                    push!(sources, (pt.node, pt.capacity, pt.VOM_cost, pt.ramp_up, pt.ramp_down, pt.delay))
                elseif pt.source_sink == "sink"
                    push!(sinks, (pt.node, pt.capacity, pt.VOM_cost, pt.ramp_up, pt.ramp_down, pt.delay))
                end
            end
        end
        if p.conversion == 1
            for so in sources
                Predicer.add_topology(processes[p.process], Predicer.Topology(so[1], p.process, Float64(so[2]), Float64(so[3]), Float64(so[4]), Float64(so[5]), Float64(so[6])))
            end
            for si in sinks
                Predicer.add_topology(processes[p.process], Predicer.Topology(p.process, si[1], Float64(si[2]), Float64(si[3]), Float64(si[4]), Float64(si[5]), Float64(si[6])))
            end
        elseif p.conversion == 2
            for so in sources, si in sinks

                if so[6] == si[6]
                    topo_delay = so[6]
                elseif abs(so[6]) > abs(si[6])
                    topo_delay = so[6]
                elseif abs(so[6]) < abs(si[6])
                    topo_delay = si[6]
                end
                Predicer.add_topology(processes[p.process], Predicer.Topology(so[1], si[1], Float64(min(so[2], si[2])), Float64(si[3]), Float64(si[4]), Float64(si[5]), Float64(topo_delay)))
            end
        elseif p.conversion == 3
            for so in sources, si in sinks
                Predicer.add_topology(processes[p.process], Predicer.Topology(so[1], si[1], Float64(min(so[2], si[2])), Float64(si[3]), Float64(si[4]), Float64(si[5]), Float64(si[6])))
                Predicer.add_topology(processes[p.process], Predicer.Topology(si[1], so[1], Float64(min(so[2], si[2])), Float64(si[3]), Float64(si[4]), Float64(si[5]), Float64(si[6])))

            end
        end
        if Bool(p.is_res)
            Predicer.add_process_to_reserve(processes[p.process]) 
        end
        if Bool(p.is_online)
            Predicer.add_online(processes[p.process], Float64(p.start_cost), Float64(p.min_online), Float64(p.min_offline), Bool(p.initial_state))
        end
    end
    
    for n in names(cap_ts)
        timesteps = map(t-> string(ZonedDateTime(t, tz"Europe/Helsinki")), cap_ts.t)
        if n != "t"
            col = split(n,",")
            proc = col[1]
            nod = col[2]
            scen = col[3]
            ts = Predicer.TimeSeries(scen)
            data = cap_ts[!,n]
            for i in 1:length(timesteps)
                push!(ts.series,(timesteps[i],data[i]))
            end
            push!(filter(x->x.source==nod || x.sink==nod,processes[proc].topos)[1].cap_ts.ts_data, ts)
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

    for s in keys(scenarios)
        if "eff_ts" in collect(keys(timeseries_data["scenarios"][s]))
            timesteps = map(t-> string(ZonedDateTime(t, tz"Europe/Helsinki")), timeseries_data["scenarios"][s]["eff_ts"].t)
            for n in names(timeseries_data["scenarios"][s]["eff_ts"])[2:end]
                mps = timeseries_data["scenarios"][s]["eff_ts"][!,n]
                ts = Predicer.TimeSeries(s)
                for i in 1:length(timesteps)
                    tup = (timesteps[i], mps[i],)
                    push!(ts.series, tup)
                end
                push!(processes[n].eff_ts.ts_data,ts)
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
        markets[mm.market] = Predicer.Market(mm.market, mm.type, mm.node, mm.direction, mm.realisation, mm.reserve_type, mm.is_bid)
        #
        for s in keys(scenarios)
            timesteps = map(t-> string(ZonedDateTime(t, tz"Europe/Helsinki")), timeseries_data["scenarios"][s]["market_prices"].t)
            mps = timeseries_data["scenarios"][s]["market_prices"][!, mm.market]
            ts = Predicer.TimeSeries(s)
            for i in 1:length(timesteps)
                tup = (timesteps[i], mps[i],)
                push!(ts.series, tup)
            end
            push!(markets[mm.market].price.ts_data, ts)
        end
        if mm.market in names(fixed_data)
            timestamps = map(t-> string(ZonedDateTime(t, tz"Europe/Helsinki")), fixed_data.t)
            data = fixed_data[!,mm.market]
            for i in 1:length(timestamps)
                if !ismissing(data[i])
                    tup = (timestamps[i],data[i])
                    push!(markets[mm.market].fixed,tup)
                end
            end
        end
    end

    for i in 1:nrow(constraint_type)
        con = constraint_type[i,1]
        con_dir = constraint_type[i,2]
        gen_constraints[con] = Predicer.GenConstraint(con,con_dir)
    end

    con_vecs = OrderedDict()
    for n in names(constraint_data)
        timesteps = map(t-> string(ZonedDateTime(t, tz"Europe/Helsinki")), constraint_data.t)
        if n != "t"
            col = split(n,",")
            constr = col[1]
            scen = col[end]
            data = constraint_data[!,n]
            ts = Predicer.TimeSeries(scen)
            for i in 1:length(timesteps)
                push!(ts.series,(timesteps[i],data[i]))
            end
            if length(col) == 4
                tup = (col[1],col[2],col[3])
                if tup in keys(con_vecs)
                    push!(con_vecs[tup],ts)
                else
                    con_vecs[tup] = []
                    push!(con_vecs[tup],ts)
                end
            else
                push!(gen_constraints[constr].constant.ts_data,ts)
            end
        end
    end

    for k in keys(con_vecs)
        con_fac = Predicer.ConFactor((k[2],k[3]))
        append!(con_fac.data.ts_data, con_vecs[k])
        push!(gen_constraints[k[1]].factors,con_fac)
    end
    
    return  Predicer.InputData(Predicer.Temporals(unique(sort(temps))), processes, nodes, markets, scenarios, reserve_type, risk, gen_constraints)
end