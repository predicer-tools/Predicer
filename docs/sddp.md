# Stochastic dual dynamic programming

## Introduction

Predicer models can also be solved with stochastic dual dynamic
programming as implemented in the [SDDP][] Julia package.  For simple
problems this is typically slower than the usual direct solution of
the deterministic equivalent.  However, SDDP is aimed at large
multistage[^multistage] problems; that is also the aim of SDDP support
in Predicer.

Among the current example problems, there is only one suited for SDDP,
namely `input_data_bidcurve.xlsx`.  To facilitate some tests, there
is also a variant, which uses the mean objective (without CVaR)
but is otherwise identical.  We have no multistage test case.  Perhaps
the currently broken hydro model could be developed into one.  As it
is, some parts of the SDDP support have been tested a little and
others not at all.

[SDDP]: https://sddp.dev/stable/

[^multistage]: In stochastic programming parlance, stages are
    separated by random events.  The simplest case is a two-stage
    model, where some random event causes different scenarios.  First
    stage decisions are made before the random event occurs and cannot
    depend on the scenario.  Second stage decisions are made
    afterwards and vary by scenario.  Multistage means more than
    two stages.

## A single Predicer model in SDDP

Using SDDP imposes some restrictions on the Predicer model:

- `common_start_timesteps` and `common_end_timesteps` must not be
  used.  To get the effect of `common_start_timesteps`, a multistage
  model is needed.
- All bids must use `bid_slots`.  This is necessary to enforce
  increasing bid curves.

A model satisfying these restrictions is a two-stage problem, where
the bid curves are decided in the first stage and carried as state
variables to the second stage.  The first stage constrains the curves
to increase.  All other variables, constraints and the scenario
objective of the Predicer model form the second stage.  Risk measures
are implemented by the SDDP framework; the same combined mean and CVaR is
available as in plain Predicer.

SDDP models are represented as so-called policy graphs.  These are
directed graphs with a dummy start node followed by one or more
alternative nodes for each stage.  Randomness can be introduced in two
ways: by branching in the graph with assigned transition probabilities
and by having multiple scenarios inside a node.  In the Julia
framework, the latter requires modifying an existing JuMP model
according to the scenario, which is difficult to implement in
Predicer.  Hence we represent each Predicer scenario as a separate
second stage node.  This does not scale quite as well as node-internal
randomness, but should scale to hundreds of scenarios and allows
Markovian dependencies for multistage (scenario probabilities may
depend on the previous stage scenario).  The second stage nodes are
preceded by a single first stage node for the bidding.  Such a policy
graph can be created from a Predicer `InputData` structure.

## Multistage models

More recent work has aimed at definition of multistage SDDP
models with Predicer.  The idea is to define each stage with its own
`InputData` instance.  These must be compatible with each other so the
stages can be combined: the timespans must fit together, each stage
starting where the previous ends, and the state variables carried
across stages must be the same (even at different stage boundaries).
There is one more stage than there are `InputData` instances; the
first stage only bids according to the first `InputData`, the second
stage contains the rest of the first `InputData` and bids for the
second `InputData`, and so on.

Multistage models require additional data not present in a sequence of
`InputData`.  Plain Predicer models assume that all markets are bid
and cleared before the model period.  More complicated arrangements
are allowed in multistage: markets are assumed to close and clear at
stage boundaries, but not all at every boundary.  The `Staging` data
structure indicates when each market closes and clears.  `Staging`
is designed to be read from a YAML file.

If market clearing is reasonably quick, it can be modelled as
instantaneous, having the market close at the end of one stage and
clear just before the next.  However, there may be a long delay
between the clearing and the start of the auction period.  E.g., the
European day-ahead market closes at noon (CET) and clears shortly
after (usually within an hour), but the bids are for the next day,
from midnight to midnight.  Between noon and midnight, bidders are
still committed to the results of the previous auction.  In addition
to bid curves (`v_bid_volume`), we need state variables for the
cleared market volume (`v_cleared_volume`), and these are for the
length of the auction period plus some overlap.  Market state is
carried as bid curves from closing to clearing and as cleared volume
at other times.

The length of the auction period must be constant for each market.
The market time unit, i.e., the length of bid time slots must also be
constant but can be longer than the model time step (not shorter
though; each bid time slot must consist of whole model time steps).
Markets with different MTUs are thus supported.

Markets are not the only state in Predicer that needs multistage
support.  The node state variable `v_state` is carried between stages
in the SDDP state variable `v_node_state`.  The initial value for the
whole model is obtaned from the first `InputData`.  In subsequent
stages, the `InputData` value is ignored.  No other state is yet
supported.

## Implementation considerations

- Functions and data structures specific to SDDP are in `sddp.jl`.
- For creating scenaro subproblems, `InputData.scenarios` is modified
  to contain a single scenario.  All iteration over scenarios must be
  done using that vector, typically by calling
  `scenarios(input_data)`.  Many components of `InputData` are indexed
  by scenario; these are not modified and must not be used for
  iterating over scenarios.
- We may do something similar to time later.  To anticipate that,
  always iterate over time using `Temporals.t` or `Temporals.times`.
- `StateShape` encapsulates the properties of `InputData` that
  determine the SDDP state variables.  For multistage, each stage
  `InputData` must yield identical `StateShape`.
- `Staging` contains data about the stage structure that is not
  present in the stage `InputData`.  Currently there is just the
  market staging described above.
- Parts of Predicer model assembly need to be aware if they are
  building an SDDP subproblem or a regular Predicer model.  They check
  for `mc["sddp"]`, which contains a `StageParam` for SDDP and is
  absent otherwise.  `StageParam` included `StateShape`, `Staging` and
  the current stage number.
- In `StageParam` and `Staging`, stage numbers start from zero: stage
  0 only bids the markets indicated in `Staging`.  Other stage numbers
  correspond to the `InputData` sequence.

## To do

- Useful test cases, particularly for multistage.  These could be
  long or short term.
    * Hydro is the long term classic.  River systems with multiple
      plants are complicated.
    * Heating control could be a medium term case: the thermal mass of
      buildings provides some flexibility even if the feasible
      temperature range is usually quite narrow.
    * Short term cases would involve short term markets, likely
      combined with day-ahead.  We could also model reserve activation
      better with multistage.  However, the plain Predicer reserve
      model is a mess and should be cleaned up first.
- More multistage state is likely needed, at least for ramping limits
  and delays.
- Little attention has been paid at how the sequence of `InputData`
  for a multistage problem would be constructed.  Having a separete
  Excel workbook for each seems hardly feasible.  Perhaps a single
  `InputData` could be split into parts for building the stages?
- The Excel workbook format is unwieldy even for two-stage if one
  wants to have hundreds of scenarios.  Typically one would then
  generate scenarios by sampling some random process.
