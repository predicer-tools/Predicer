#= In the project root directory:
    ]activate .
    ]test
=#

using Predicer
using Test
using JuMP
using DataStructures
using SDDP

## All optimisation tests should use Optimizer, e.g., Model(Optimizer).
## Uncomment the one you want.
using HiGHS: Optimizer
# using Cbc: Optimizer
# using CPLEX: Optimizer

"""Turn off all solver logging"""
silent = false

"""
Model definition files and objective values.  obj = NaN to disable
comparison.
"""
cases = OrderedDict(
    "input_data_complete.xlsx" => -5809.146293930541,
    "input_data.xlsx" => -10985.20345389959,
    "input_data_bidcurve.xlsx" => -4371.579033779262,
    "input_data_bidcurve_e.xlsx" => -4501.509824681449,
    "demo_model.xlsx" => -1095.5118308122817,
    "example_model.xlsx" => -11014.1278942231,
    "input_data_common_start.xlsx" => -1589.80385514,
    "input_data_delays.xlsx" => 62.22222222222222,
    "input_data_temps.xlsx" => 65388.35282275837,
    "simple_building_model.xlsx" => 563.7841038762567,
    "simple_dh_model.xlsx" => 7195.372539092246,
    #"simple_hydropower_river_system.xlsx" => NaN,
    "two_stage_dh_model.xlsx" => 9508.652488524222,
)

"""
SDDP test cases with lower bounds.
I think these have to be for the best scenario, at least for multicut.
A bound for the expected cost may do for single cut.
"""
sddp_cases = OrderedDict(
    "input_data_bidcurve.xlsx" => -12000,
    "input_data_bidcurve_e.xlsx" => -12000,
)

inputs = Dict{String, Predicer.InputData}()

"""
All tests should use this to read `InputData` from files.  `bn` is the
basename (without directory but with suffix) of the input file.  The inputs
are cached; each is only read once.
"""
get_input(bn) = get!(inputs, bn) do
    inp = Predicer.get_data(joinpath("..", "input_data", bn))
    Predicer.tweak_input!(inp)
end

"""
Workaround for some solvers throwing on JuMP.relative_gap.
Return Inf instead, as some other solvers do.
"""
relative_gap(m) = try
    JuMP.relative_gap(m)
catch
    Inf
end

"""
Relative tolerance for comparing objective values.
"""
function obj_rtol(m)
    rgap = relative_gap(m)
    if rgap < 1e-8 || !isfinite(rgap)
        return 1e-8
    else
        return rgap
    end
end

## Test sets.  Comment away to skip.
include("make-graph.jl")
include("predicer.jl")
include("roll.jl")
include("scenarios.jl")
include("sddp.jl")
