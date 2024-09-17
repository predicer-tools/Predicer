# SDDP support

using DocStringExtensions

using DataStructures
using Accessors
using SDDP

"""
$(TYPEDEF)

The time-independent part of `BidSlot`

$(TYPEDFIELDS)
"""
struct BidShape
    """Number of curves (time slots) to bid"""
    n_curves::Integer
    """Names of bid curve points"""
    slots::Vector{String}
    """Lower bound for bid volumes.  Non-positive, possibly -Inf."""
    lower_bound::Float64
end
BidShape(m::Market, bs::BidSlot) = BidShape(
    length(bs.time_steps), bs.slots, bid_lower_bound(m))

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
"""
StateShape(inp::InputData) = StateShape(
    OrderedDict(m => BidShape(inp.markets[m], bs)
                for (m, bs) in inp.bid_slots))

"""
$(TYPEDSIGNATURES)

Add bid curve state variables.  The markets, bid slots and times are obtained
from `shape` and must be identical for all stages, which all must call
this function with `mc["model"]` set to the stage subproblem.  Replaces
`create_v_bid_volume` for SDDP.
"""
function sddp_create_bid_state(mc::OrderedDict, shape::StateShape)
    bss = shape.bid_shapes
    @variable(mc["model"],
              v_bid_volume[m = keys(bss),
                           s = bss[m].slots, t = 1 : bss[m].n_curves]
              ≥ bss[m].lower_bound, SDDP.State, initial_value=0)
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
    @assert all(inp.setup.common_timesteps == 0 for inp in inputs)
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
function sddp_policy_graph(inputs::AbstractVector{InputData}; kws...)
    st_shape = StateShape(inputs[1])
    @assert all((st_shape,) .== StateShape.(inputs[2 : end]))
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
        mc["sddp_shape"] = st_shape
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

sddp_risk_measure(inp::InputData) = (
    inp.setup.contains_risk
    ? SDDP.EAVaR(beta = 1 - inp.risk["alfa"], lambda = 1 - inp.risk["beta"])
    : SDDP.Expectation()
)
