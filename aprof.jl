using Profile
using PProf
using CPUTime
using Pkg

Pkg.activate(".")

using Predicer

inp = Predicer.get_data(
    "input_data/input_data_bidcurve_medium.xlsx") |> Predicer.tweak_input!

@time @CPUtime Profile.Allocs.@profile(
    sample_rate=0.001, mc = Predicer.generate_model(inp))
PProf.Allocs.pprof()
