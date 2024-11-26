# SDDP support

using DocStringExtensions
using Dates
using DataStructures
using Accessors
using SDDP

"""
$(TYPEDEF)

The time-independent part of `BidSlot`.

$(TYPEDFIELDS)
"""
struct BidShape
    """Number of curves (time slots) to bid"""
    n_curves::Integer
    """Market time unit: duration of each time slot (must be constant)"""
    mtu::Period
    """Time of previous market period remaining when the next period is
    cleared, in MTUs, rounded up."""
    overlap::Integer
    """Names of bid curve points"""
    slots::Vector{String}
    """Lower bound for bid volumes.  Non-positive, typically 0 or -Inf."""
    lower_bound::Float64
end
"""
$(TYPEDSIGNATURES)

`n_curves` and `mtu` are obtained from `inp.bid_slots[market].time_steps`
(uniform time slots are asserted).  If `overlap` is not given (negative),
it is computed from the first bidding time slot and the modelling period
start.
"""
function BidShape(market::String, inp::InputData, overlap::Integer = -1)
    bs = inp.bid_slots[market]
    dts = diff(bs.time_steps)
    mtu = dts[1]
    @assert all(mtu .== dts[2 : end])
    if overlap < 0
        overlap = ceil(
            (bs.time_steps[1] - first(values(inp.temporals.times))) / mtu)
    end
    return BidShape(length(bs.time_steps), dts[1], overlap, bs.slots,
                    bid_lower_bound(inp.markets[market]))
end

"""
$(TYPEDEF)

Defines the indices of SDDP state variables connecting stages.

$(TYPEDFIELDS)
"""
struct StateShape
    """Bid shapes by market"""
    bid_shapes::OrderedDict{String, BidShape}
end

"""
$(TYPEDSIGNATURES)

`overlap(m)` defines `BidShape.overlap` for the market named m.
"""
StateShape(overlap, inp::InputData) = StateShape(
    OrderedDict(m => BidShape(m, inp, overlap(m))
                for m in keys(inp.bid_slots)))

"""$(TYPEDSIGNATURES)"""
StateShape(inp::InputData) = StateShape(_ -> -1, inp)

"""
$(TYPEDEF)

Defines when markets act in a possibly multistage Predicer model.  Indices
refer to the vector of `InputData` that the model is built from.  `bid` may
also contain 0, which refers to the first SDDP stage, which only bids such
markets.  For a single Predicer model `bid`={0} and `clear={1}`, but single
models are usually faster to solve directly than with SDDP.

$(TYPEDFIELDS)
"""
@kwdef struct MarketStaging
    """Stages that bid in the market (bidding closes at end of stage)"""
    bid::BitSet
    """Stages where the market is cleared (in the beginning of the stage)"""
    clear::BitSet

    MarketStaging(bid, clear) = new(BitSet(bid), BitSet(clear))
end
MarketStaging(dict::AbstractDict) = MarketStaging(
    ; (Symbol(k) => v for (k, v) in dict)...)
"""
$(TYPEDSIGNATURES)

Create a simple staging where all but the last stage bid and
all but stage 0 clear.
"""
MarketStaging(n::Integer) = MarketStaging(0 : n - 1, 1 : n)

"""
$(TYPEDEF)

Data about the role of model stages that is not present in `InputData`.

$(FIELDS)
"""
@kwdef struct Staging
    markets::OrderedDict{String, MarketStaging}

    Staging(markets::AbstractDict) = new(
        OrderedDict(String(k) => MarketStaging(v) for (k, v) in markets))
end
"""
$(TYPEDSIGNATURES)

Create a simple staging for all markets.  Basically guesswork.
"""
Staging(inputs::AbstractVector{InputData}) = Staging(OrderedDict(
    m => length(inputs) for m in keys(inputs[1].bid_slots)))

"""
$(TYPEDEF)

Overall model data passed to node subproblem construction.

$(FIELDS)
"""
mutable struct StageParam
    shape::StateShape
    staging::Staging
    """Stage number as used in `Staging`"""
    stage::Int
end

shall_bid(m::String, sp::StageParam) = sp.stage in sp.staging.markets[m].bid
shall_clear(m::String, sp::StageParam) =
    sp.stage in sp.staging.markets[m].clear

"""
$(TYPEDSIGNATURES)

Add bid curve state variables.  The markets, bid slots and times are obtained
from `shape` and must be identical for all stages, which all must call
this function with `mc["model"]` set to the stage subproblem.  Replaces
`create_v_bid_volume` for SDDP.
"""
function sddp_create_bid_state(mc::OrderedDict, shape::StateShape)
    bss = shape.bid_shapes
    @variables mc["model"] begin
        v_bid_volume[
            m = keys(bss), s = bss[m].slots, t = 1 : bss[m].n_curves
        ] ≥ bss[m].lower_bound, (SDDP.State, initial_value=0)

        #TODO means for giving the initial value
        v_cleared_volume[
            m = keys(bss), t = 1 : bss[m].n_curves + bss[m].overlap
        ] ≥ bss[m].lower_bound, (SDDP.State, initial_value=0)
    end
end



"""
$(TYPEDSIGNATURES)

Return transition matrices suitable `for SDDP.Markovian[Policy]Graph`.
`inputs[i]` defines the scenarios for stage `i + 1`.  The root node of the
graph is a dummy and defines no subproblem.  It transitions with probability 1
to a single first stage node, then branches by the first set of scenarios to
the second stage.  Typically the first stage bids on markets, which are
cleared at the start of the second stage.  The node indices correspond to the
ordering of `InputData.scenarios`

If you want a multistage (> 2) graph where the transition probabilities also
depend on the scenario transitioned from, build the matrices by other means.
`InputData` cannot represent that.
"""
function sddp_markov_mats(
        inputs::AbstractVector{InputData}) :: Vector{Matrix{Float64}}
    #^ SDDP currently requires a vector of Matrix; AbstractMatrix will not do.
    @assert all(inp.setup.common_start_timesteps == 0
                && inp.setup.common_end_timesteps == 0
                for inp in inputs)
    p(i) = [values(inputs[i].scenarios)...]'
    [[1.]', (repeat(p(i), i == 1 ? 1 : length(inputs[i - 1].scenarios))
             for i in 1 : length(inputs))...]
end

"""
$(TYPEDSIGNATURES)

Return `InputData` for the scenario `scen` subproblem.  `inp` is not modified;
a shallow copy with modified `scenarios` is returned.
"""
function scen_subproblem(inp::InputData, scen::String)
    @set inp.scenarios = OrderedDict(scen => 1.)
end

"""
$(TYPEDSIGNATURES)

Create an SDDP policy graph by combining Predicer models created
from `inputs`.  `kws` is passed to `SDDP.PolicyGraph`.

All `inputs` must define an equal `StateShape`.  The policy graph has
one more stage than there are `inputs`: the first PG stage just decides
the first bids and the n + 1st PG stage contains the Predicer model
of the nth input.
"""
function sddp_policy_graph(
        inputs::AbstractVector{InputData},
        staging::Staging; kws...)
    st_shape = StateShape(inputs[1])
    @assert all((st_shape,) .== StateShape.(
        m -> st_shape.bid_shapes[m].overlap, inputs[2 : end]))
    SDDP.MarkovianPolicyGraph(
        transition_matrices=sddp_markov_mats(inputs); kws...
    ) do sp, node
        st, sc = node
        if st == 1
            inp = inputs[1]
            scen = ""
            @reset inp.scenarios = OrderedDict()
        else
            inp = inputs[st - 1]
            scen = [keys(inp.scenarios)...][sc]
            inp = scen_subproblem(inp, scen)
        end
        mc = build_model_contents_dict(inp)
        mc["model"] = sp
        mc["sddp"] = StageParam(st_shape, staging, st - 1)
        sddp_create_bid_state(mc, st_shape)
        if st == 1
            setup_bidding_volume_constraints(mc, inp)
        else
            create_variables(mc, inp)
            create_constraints(mc, inp)
            @stageobjective(sp, mc["expression"]["total_costs"][scen])
        end
    end
end

sddp_policy_graph(inputs; kws...) = sddp_policy_graph(
    inputs, Staging(inputs); kws...)

sddp_risk_measure(inp::InputData) = (
    inp.setup.contains_risk
    ? SDDP.EAVaR(beta = 1 - inp.risk["alfa"], lambda = 1 - inp.risk["beta"])
    : SDDP.Expectation()
)
