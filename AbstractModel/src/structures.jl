# --- State ---
"""
    struct State
        in_max::Float64
        out_max::Float64
        state_max::Float64
        state_min::Float64
        initial_state::Float64
        state_loss::Float64
        function State(in_max, out_max, initial_state, state_max, state_loss, state_min=0)
            return new(in_max, out_max, state_max, state_min, initial_state, state_loss)
        end
    end

A struct for node states (storage), holds information on the parameters of the state.
# Fields
- `in_max::Float64`: Value for maximum increase of state variable value between timesteps. 
- `out_max::Float64`: Value for maximum decrease of state variable value between timesteps. 
- `state_max::Float64`: Maximum value for state variable. 
- `state_min::Float64`: Minimum value for state variable. 
- `initial_state::Float64`: Initial value of the state variable at t = 0.
- `state_loss`: Losses over time in the state. 
"""
struct State
    in_max::Float64
    out_max::Float64
    state_max::Float64
    state_min::Float64
    initial_state::Float64
    state_loss::Float64
    function State(in_max, out_max, initial_state, state_max, state_loss, state_min=0)
        return new(in_max, out_max, state_max, state_min, initial_state, state_loss)
    end
end


# --- TimeSeries ---
"""
    mutable struct TimeSeries
        scenario::Any
        series::Vector{Tuple{Any, Any}}
        function TimeSeries(scenario="", series=0)
            if series != 0
                return new(scenario, series)
            else
                return new(scenario, [])
            end
        end
    end

A struct for time series. Includes linked scenario and a vector containing tuples of time and value.
"""
mutable struct TimeSeries
    scenario::Any
    series::Vector{Tuple{Any, Any}}
    function TimeSeries(scenario="", series=0)
        if series != 0
            return new(scenario, series)
        else
            return new(scenario, [])
        end
    end
end


# --- Node ---
"""
    struct Node
        name::String
        is_commodity::Bool
        is_state::Bool
        is_res::Bool
        is_inflow::Bool
        is_market::Bool
        state::State
        cost::Vector{TimeSeries}
        inflow::Vector{TimeSeries}
        function Node(name, is_commodity, is_state, is_res, is_inflow, is_market, state_max, in_max, out_max, initial_state)
            return new(name, is_commodity, is_state, is_res, is_inflow, is_market, State(in_max, out_max, initial_state, state_max), [], [])
        end
    end 

A struct for nodes.
# Fields
- `name::String`: Name of the node. 
- `is_commodity::Bool`: Flag indicating of the node is a commodity.
- `is_state::Bool`:  Flag indicating of the node has a state (storage).
- `is_res::Bool`: Flag indicating of the node participates as a reserve.
- `is_inflow::Bool`: Flag indicating of the node has a inflow. 
- `is_market::Bool`: Flag indicating of the node is a market node.
- `state::State`: The state of the node. 
- `cost::Vector{TimeSeries}`: Vector containing TimeSeries with the costs for each scenario. 
- `inflow::Vector{TimeSeries}`: Vector contining TimeSeries with the inflows for each scenario. 
"""
struct Node
    name::String
    is_commodity::Bool
    is_state::Bool
    is_res::Bool
    is_inflow::Bool
    is_market::Bool
    state::State
    cost::Vector{TimeSeries}
    inflow::Vector{TimeSeries}
    function Node(name, is_commodity, is_state, is_res, is_inflow, is_market, state_max, in_max, out_max, initial_state, state_loss)
        return new(name, is_commodity, is_state, is_res, is_inflow, is_market, State(in_max, out_max, initial_state, state_max, state_loss), [], [])
    end
end


# --- Topology ---
"""
    struct Topology
        source::String
        sink::String
        capacity::Float64
        VOM_cost::Float64
        ramp_up::Float64
        ramp_down::Float64
        function Topology(source, sink, capacity, VOM_cost, ramp_up, ramp_down)
            return new(source, sink, capacity, VOM_cost, ramp_up, ramp_down)
        end
    end

A struct for a process topology, signifying the connection between flows in a process. 
# Fields
- `source::String`: Name of the source of the topology.
- `sink::String`: Name of the sink of the topology.
- `capacity::Float64`: Upper limit of the flow variable for the topology. 
- `VOM_cost::Float64`: VOM cost of using this connection. 
- `ramp_up::Float64`: Maximum allowed increase of the linked flow variable value between timesteps. 
- `ramp_down::Float64`: Minimum allowed increase of the linked flow variable value between timesteps. 
"""
struct Topology
    source::String
    sink::String
    capacity::Float64
    VOM_cost::Float64
    ramp_up::Float64
    ramp_down::Float64
    cap_ts::Vector{TimeSeries}
    function Topology(source, sink, capacity, VOM_cost, ramp_up, ramp_down)
        return new(source, sink, capacity, VOM_cost, ramp_up, ramp_down, [])
    end
end


# --- Process ---
"""

    struct Process
        name::String
        is_cf::Bool
        is_cf_fix::Bool
        is_online::Bool
        is_res::Bool
        eff::Float64
        conversion::Integer
        load_min::Float64
        load_max::Float64
        start_cost::Float64
        min_online::Int64
        min_offline::Int64
        initial_state::Bool
        topos::Vector{Topology}
        cf::Vector{TimeSeries}
        eff_ts::Vector{TimeSeries}
        eff_ops::Vector{Any}
        eff_fun::Vector{Tuple{Any,Any}}
        function Process(name, is_cf, is_cf_fix, is_online, is_res, eff, conversion, load_min, load_max, start_cost, min_online, min_offline, initial_state)
            return new(name, is_cf, is_cf_fix, is_online, is_res, eff, conversion, load_min, load_max, start_cost, min_online, min_offline, initial_state, [], [], [], [], [])
        end
    end

A struct for a process (unit).
# Fields
- `name::String`: Name of the process.
- `is_cf::Bool`: Flag indicating if the process is a cf (capacity factor) process, aka depends on a TimeSeries.
- `is_cf_fix::Bool`: Flag indicating if the cf TimeSeries is a upper limit (false) or a set value (true).
- `is_online::Bool`: Flag indicating if the process has an binary online variable.
- `is_res::Bool`: Flag indicating if the process can participate in a reserve.
- `eff::Float64`: Process conversion efficiency.
- `conversion::Integer`: 
- `load_min::Float64`: Minimum allowed load over the process, min 0, max 1.
- `load_max::Float64`: Maximum allowed load over the process, min 0, max 1.
- `start_cost::Float64`: Cost to start the process, if the 'is_online' flag is true.
- `min_online::Int64`: Minimum time the process has to be online after start.
- `min_offline::Int64`: Minimum time the process has to be offline after start.
- `initial_state::Bool`: Initial state (on/off) of the process at the start of simulation.
- `topos::Vector{Topology}`: Vector containing the topologies of the process.
- `cf::Vector{TimeSeries}`: Vector containing TimeSeries limiting a cf process.
- `eff_ts::Vector{TimeSeries}`: Vector of TimeSeries containing information on efficiency depending on time.
- `eff_ops::Vector{Any}`: Vector containing operating points for a piecewise efficiency function.
- `eff_fun::Vector{Tuple{Any,Any}}`: Vector containing efficiencies for a piecewise efficiency function.

"""
struct Process
    name::String
    is_cf::Bool
    is_cf_fix::Bool
    is_online::Bool
    is_res::Bool
    eff::Float64
    conversion::Integer
    load_min::Float64
    load_max::Float64
    start_cost::Float64
    min_online::Int64
    min_offline::Int64
    initial_state::Bool
    topos::Vector{Topology}
    cf::Vector{TimeSeries}
    eff_ts::Vector{TimeSeries}
    eff_ops::Vector{Any}
    eff_fun::Vector{Tuple{Any,Any}}
    function Process(name, is_cf, is_cf_fix, is_online, is_res, eff, conversion, load_min, load_max, start_cost, min_online, min_offline, initial_state)
        return new(name, is_cf, is_cf_fix, is_online, is_res, eff, conversion, load_min, load_max, start_cost, min_online, min_offline, initial_state, [], [], [], [], [])
    end
end


# --- Market ---
"""
    struct Market
        name::String
        type::String
        node::Any
        direction::String
        realisation::Float64
        reserve_type::String
        price::Vector{TimeSeries}
        fixed::Vector{Tuple{Any,Any}}
        function Market(name, type, node, direction, realisation, reserve_type)
            return new(name, type, node, direction, realisation, reserve_type, [], [])
        end
    end

A struct for markets.
# Fields
- `name::String`: Name of the market. 
- `type::String`: Type of the market (energy/reserve).
- `node::Any`: Name of the node this market is connected to.
- `direction::String`: Direction of the market (up/down/updown).
- `realisation::Float64`: Realisation probability.
- `reserve_type::String`: Type of the reserve market. 
- `price::Vector{TimeSeries}`: Vector containing TimeSeries of the market price in different scenarios. 
- `fixed::Vector{Tuple{Any,Any}}`: Vector containing information on the market being fixed. 
"""
struct Market
    name::String
    type::String
    node::Any
    direction::String
    realisation::Float64
    reserve_type::String
    price::Vector{TimeSeries}
    fixed::Vector{Tuple{Any,Any}}
    function Market(name, type, node, direction, realisation, reserve_type)
        return new(name, type, node, direction, realisation, reserve_type, [], [])
    end
end


# --- ConFactor ---
"""
    struct ConFactor
        flow::Tuple{Any,Any}
        data::Vector{TimeSeries}
        function ConFactor(flow,data)
            return new(flow,data)
        end
    end

Struct for general constraints factors.
# Fields
- `flow::Tuple{Any,Any}`: ??
- `data::Vector{TimeSeries}`: ??    
"""
struct ConFactor
    flow::Tuple{Any,Any}
    data::Vector{TimeSeries}
    function ConFactor(flow,data)
        return new(flow,data)
    end
end


# --- GenConstraint ---
"""
    struct GenConstraint
        name::String
        type::String
        factors::Vector{ConFactor}
        constant::Vector{TimeSeries}
        function GenConstraint(name,type)
            return new(name,type,[],[])
        end
    end

Struct for general constraints.
# Fields
- `name::String`: Name of the generic constraint. 
- `type::String`: Type of the generic constraint. 
- `factors::Vector{ConFactor}`: Vector of ConFactors. 
- `constant::Vector{TimeSeries}`: TimeSeries?
"""
struct GenConstraint
    name::String
    type::String
    factors::Vector{ConFactor}
    constant::Vector{TimeSeries}
    function GenConstraint(name,type)
        return new(name,type,[],[])
    end
end