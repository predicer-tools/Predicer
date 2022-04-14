abstract type AbstractNode end
abstract type AbstractProcess end

#= struct AbstractModel
    model::Union{JuMP.model, Nothing}
    is_built::Bool
    contents::OrderedDict
    
end =#

"""
    struct State
        in_max::Float64
        out_max::Float64
        state_loss::Float64
        state_max::Float64
        state_min::Float64
        initial_state::Float64
        function State(in_max, out_max, state_loss, state_max, state_min=0, initial_state=0)
            return new(in_max, out_max, state_loss, state_max, state_min, initial_state)
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
    state_loss::Float64
    state_max::Float64
    state_min::Float64
    initial_state::Float64
    function State(in_max, out_max, state_loss, state_max, state_min=0, initial_state=0)
        return new(in_max, out_max, state_loss, state_max, state_min, initial_state)
    end
end


# --- TimeSeries ---
"""
    struct TimeSeries
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
struct TimeSeries
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
    mutable struct Node <: AbstractNode
        name::String
        is_commodity::Bool
        is_market::Bool
        is_state::Bool
        is_res::Bool
        is_inflow::Bool
        state::Union{State, Nothing}
        cost::Vector{TimeSeries}
        inflow::Vector{TimeSeries}
    end

A struct for nodes.
# Fields
- `name::String`: Name of the node. 
- `is_commodity::Bool`: Flag indicating of the node is a commodity.
- `is_market::Bool`: Flag indicating of the node is a market node.
- `is_state::Bool`:  Flag indicating of the node has a state (storage).
- `is_res::Bool`: Flag indicating of the node participates as a reserve.
- `is_inflow::Bool`: Flag indicating of the node has a inflow. 
- `state::Union{State, Nothing}`: The state of the node. 
- `cost::Vector{TimeSeries}`: Vector containing TimeSeries with the costs for each scenario. 
- `inflow::Vector{TimeSeries}`: Vector contining TimeSeries with the inflows for each scenario. 
"""
mutable struct Node <: AbstractNode
    name::String
    is_commodity::Bool
    is_market::Bool
    is_state::Bool
    is_res::Bool
    is_inflow::Bool
    state::Union{State, Nothing}
    cost::Vector{TimeSeries}
    inflow::Vector{TimeSeries}
end


"""
    function Node(name::String, is_commodity::Bool, is_market::Bool)

Constructor for the Node struct.

# Examples
```julia-repl
julia> n = Node("testNode")
Node("testNode", false, false, false, false, false, nothing, TimeSeries[], TimeSeries[])
```

```julia-repl
julia> n = Node("CommodityNode", true)
Node("CommodityNode", true, false, false, false, false, nothing, TimeSeries[], TimeSeries[])
```

```julia-repl
julia> n = Node("MarketNode", false, true)
Node("MarketNode", false, true, false, false, false, nothing, TimeSeries[], TimeSeries[])
```
"""
function Node(name::String, is_commodity::Bool=false, is_market::Bool=false)
    if is_commodity == true && is_market == true
        error("A Node cannot be a commodity and a market at the same time!")
    else
        return Node(name, is_commodity, is_market, false, false, false, nothing, [], [])
    end
end


"""
    function add_inflow(n::Node, ts::TimeSeries)

Add a inflow timeseries to the Node. A positive inflow adds to the Node, while a negative inflow removes from the Node, and can thus seen as a demand.
"""
function add_inflow(n::Node, ts::TimeSeries)
    if n.is_commodity == true 
        error("A commodity Node cannot have an inflow.")
    elseif n.is_market == true
        error("A market Node cannot have an inflow.")
    else
        n.is_inflow = true
        push!(n.inflow, ts)
    end
end


"""
    function add_state(n::Node, s::State)

Adds a State (storage) to the Node. 
"""
function add_state(n::Node, s::State)
    if n.is_commodity == true 
        error("A commodity Node cannot have a state.")
    elseif n.is_market == true
        error("A market Node cannot have a state.")
    else
        n.is_state = true
        n.state = s
    end
end


"""
    function add_to_reserve(n::Node)

Sets a flag which shows that the Node is a reserve node. 
"""
function add_node_to_reserve(n::Node)
    if n.is_commodity == true 
        error("A commodity Node cannot have a reserve.")
    elseif n.is_market == true
        error("A market Node cannot have a reserve.")
    else
        n.is_res = true
    end
end


"""
    function convert_to_commodity(n::Node)

Makes a Node into a commodity Node. 
"""
function convert_to_commodity(n::Node)
    if n.is_res
        error("Cannot convert a Node with reserves into a commodity Node.")
    elseif n.is_state
        error("Cannot convert a Node with a state into a commodity Node.")
    elseif n.is_inflow
        error("Cannot convert a Node with an inflow into a commodity Node.")
    elseif !n.is_market
        n.is_commodity = true
    else
        error("Cannot change a market Node into a commodity Node.")
    end
end


"""
    function convert_to_market(n::Node)

Makes a Node into a market Node. 
"""
function convert_to_market(n::Node)
    if n.is_res
        error("Cannot convert a Node with reserves into a market Node.")
    elseif n.is_state
        error("Cannot convert a Node with a state into a market Node.")
    elseif n.is_inflow
        error("Cannot convert a Node with an inflow into a market Node.")
    elseif !n.is_commodity
        n.is_market = true
    else
        error("Cannot change a commodity Node into a market Node.")
    end
end


"""
    add_cost(n::Node, ts::TimeSeries)

Adds a cost TimeSeries to a Node with is_commodity==true. Returns an error if is_commodity==false
"""
function add_cost(n::Node, ts::TimeSeries)
    if n.is_commodity
        push!(n.cost, ts)
    else
        error("Can only add a cost TimeSeries to a commodity Node!")
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
- `ramp_up::Float64`: Maximum allowed increase of the linked flow variable value between timesteps. Min 0.0 max 1.0. 
- `ramp_down::Float64`: Minimum allowed increase of the linked flow variable value between timesteps. Min 0.0 max 1.0. 
"""
struct Topology
    source::String
    sink::String
    capacity::Float64
    VOM_cost::Float64
    ramp_up::Float64
    ramp_down::Float64
    cap_ts::Vector{TimeSeries}
    function Topology(source::String, sink::String, capacity::Float64, VOM_cost::Float64, ramp_up::Float64, ramp_down::Float64)
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
mutable struct Process <: AbstractProcess
    name::String
    conversion::Integer # change to string-based: unit_based, market_based, transfer_based
    is_cf::Bool
    is_cf_fix::Bool
    is_online::Bool
    is_res::Bool
    eff::Float64
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
end


"""
    function Process(name::String, conversion::Int=1)

The constructor for the Process struct. 

# Arguments:
- `name::String`: The name of the process.
- `conversion::Int`: Used to differentiate between types of process. 1 = unit based, 2 = transfer process, 3 = market process.
"""
function Process(name::String, conversion::Int=1)
    return Process(name, conversion, false, false, false, false, -1.0, 0.0, 1.0, 0.0, 0, 0, true, [], [], [], [], [])
end


"""
    function MarketProcess(name::String)

Returns a market based process. 
"""
function MarketProcess(name::String)
    return Process(name, 3)
end


"""
    function TransferProcess(name::String)

Returns a transfer process. 
"""
function TransferProcess(name::String)
    return Process(name, 2)
end


"""
    function add_fixed_eff(p::Process, ts::TimeSeries)

Adds a time-dependent value for the efficiency of the process. 
"""
function add_fixed_eff(p::Process, ts::TimeSeries)
    push!(p.eff_ts, ts)
end


"""
    function add_piecewise_eff(p::Process, ops::Vector{Float64}, effs::Vector{Tuple{Float64, Float64}})

Add piecewise efficiency functionality to the process.
"""
function add_piecewise_eff(p::Process, ops::Vector{Float64}, effs::Vector{Tuple{Float64, Float64}})
    if length(ops) == length(effs)
        p.eff_ops = ops
        p.eff_fun = effs
    else
        return error("The length of the operating points vector and efficiency vector must be the same.")
    end
end


"""
    function add_online(p::Process, start_cost::Float64=0, min_online::Float64=0, min_offline::Float64=0, initial_state::Bool=true)

Add binary online functionality to the process.
"""
function add_online(p::Process, start_cost::Float64=0.0, min_online::Float64=0.0, min_offline::Float64=0.0, initial_state::Bool=true)
    if !p.is_cf
        p.is_online = true
        p.min_online = min_online >= 0 ? min_online : error("Minimum time online cannot be less than 0.")
        p.min_offline = min_offline >= 0 ? min_offline : error("Minimum time offline cannot be less than 0.")
        p.start_cost = start_cost
        p.initial_state = initial_state
    else
        return error("A cf process cannot have online functionality.")
    end
end


"""
    function add_eff(p::Process, eff::Float64)

Add an efficiency to the process. 
"""
function add_eff(p::Process, eff::Float64)
    if eff >= 0.0
        p.eff = eff
    else 
        return error("The given efficiency must be larger than 0.0.")
    end
end

"""
    function add_cf(p::Process, ts::TimeSeries, is_cf_fix::Bool=false)

Adds a capacity factor functionality to a process. Can be called for each scenario to add the TimeSeries. 

# Arguments
- `p::Process`: Process struct.
- `is_cf_fix`: Boolean indicating whether the value of the process is bound (true) to the values given in the TimeSeries, or if the TimeSeries values act as an upper limit (false)
- `ts`: TimeSeries containing the values limiting the process. 
"""
function add_cf(p::Process, ts::TimeSeries, is_fixed::Bool=false)
    if !p.is_online
        p.is_cf = true
        p.is_cf_fix = is_fixed
        push!(p.cf, ts)
    else
        return error("Cannot add cf functionality to a process with online functionality.")
    end
end


"""
    function add_to_reserve(p::Process)

Add reserve functionality to a process. 
"""
function add_process_to_reserve(p::Process)
    if !p.is_cf
        p.is_res = true
    else
        return error("A process with cf functionality cannot be a part of a reserve market.")
    end
end


"""
    function add_topology(p::Process, topo::Topology)

Add a new topology (connection) to the process.
"""
function add_topology(p::Process, topo::Topology)
    push!(p.topos, topo)
end


"""
    function add_load_limits(p::Process, min_load::Float64, max_load::Float64)

Add min and max load limitss to a process.
"""
function add_load_limits(p::Process, min_load::Float64, max_load::Float64)
    if min_load >= 0.0 && min_load <= 1.0
        if max_load >= 0.0 && max_load <= 1.0
            if max_load >= min_load
                p.load_min = min_load
                p.load_max = max_load
            else
                return error("The maximum load must be equal to or higher than the min load.")
            end
        else
            return error("The given max load must be between 0.0 and 1.0.")
        end
    else
        return error("The given min load must be between 0.0 and 1.0")
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