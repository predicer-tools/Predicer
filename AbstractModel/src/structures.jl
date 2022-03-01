abstract type AbstractNode end
abstract type AbstractProcess end
abstract type AbstractState end
abstract type AbstractExpr end

struct State <: AbstractState
    in_max::Float64
    out_max::Float64
    state_max::Float64
    state_min::Float64
    initial_state::Float64
    function State(in_max, out_max, initial_state, state_max, state_min=0)
        return new(in_max, out_max, initial_state, state_max, state_min)
    end
end

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

struct Node <: AbstractNode
    name::String
    is_commodity::Bool
    is_state::Bool
    is_res::Bool
    is_inflow::Bool
    is_market::Bool
    state::AbstractState
    cost::Vector{TimeSeries}
    inflow::Vector{TimeSeries}
    nodegroup::Vector{AbstractNode}
    function Node(name, is_commodity, is_state, is_res, is_inflow, is_market, state_max, in_max, out_max, initial_state)
        return new(name, is_commodity, is_state, is_res, is_inflow, is_market, State(in_max, out_max, initial_state, state_max), [], [], [])
    end
end

struct NodeGroup <: AbstractNode
    name::String
    is_res::Bool
    is_commodity::Bool
    nodes::Vector{AbstractNode}
    function NodeGroup(name, is_res, is_commodity)
        return new(name, is_res, [])
    end
end



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

# A single process in a unit or a unit
struct Process <: AbstractProcess
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
    group::Vector{AbstractProcess}
    cf::Vector{TimeSeries}
    eff_ts::Vector{TimeSeries}
    eff_ops::Vector{Any}
    eff_fun::Vector{Tuple{Any,Any}}
    function Process(name, is_cf, is_cf_fix, is_online, is_res, eff, conversion, load_min, load_max, start_cost, min_online, min_offline, initial_state)
        return new(name, is_cf, is_cf_fix, is_online, is_res, eff, conversion, load_min, load_max, start_cost, min_online, min_offline, initial_state, [], [], [], [], [], [])
    end
end

# The "unit", balance could be checked over this process. 
struct ProcessGroup <: AbstractProcess
    name::String
    processes::Vector{AbstractProcess} # Should this be a string, which can be accessed through the dictionary?
    function ProcessGroup(name)
        return new(name)
    end
end

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

struct ConFactor
    flow::Tuple{Any,Any}
    data::Vector{TimeSeries}
    function ConFactor(flow,data)
        return new(flow,data)
    end
end

struct GenConstraint
    name::String
    type::String
    factors::Vector{ConFactor}
    constant::Vector{TimeSeries}
    function GenConstraint(name,type)
        return new(name,type,[],[])
    end
end

#= #Define acceptable data types. Will be extended in the future. 
gcu = Union{Process, TimeSeries, Real, AbstractExpr}

struct GenExpr <: AbstractExpr
    e_type::DataType
    entity::gcu
    c_type::DataType
    coeff::Union{Real, AbstractExpr}
    time_specific::Bool
    time_lag::Int
    stochastic::Any
    timestep::Any
    function GenExpr(entity, coeff, time_specific, time_lag=0, stochastic = "", timestep = "")
        return new(typeof(entity), entity, typeof(coeff), coeff, time_specific, time_lag, stochastic, timestep)
    end
end

struct GenericConstraint
    symbol::String
    left_f::Vector{GenExpr}
    left_op::Vector{String}
    right_f::Vector{GenExpr}
    right_op::Vector{String}
    name::String
    function GenericConstraint(symbol, left_f, left_op, right_f, right_op, name = "")
        return new(symbol, left_f, left_op, right_f, right_op, name)
    end
end


struct ReserveType
    name::String
    ramp_factor::Float64
    function ReserveType(name, ramp_factor)
        return new(name, ramp_factor)
    end
end


struct Reserve
    name::String
    node::Node
    type::ReserveType
    direction::String
    realisation::Float64
end =#