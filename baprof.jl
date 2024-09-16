using BenchmarkTools
using Profile
using PProf
using Pkg

Pkg.activate(".")

using Predicer

const inp = Predicer.get_data(
    "input_data/input_data_bidcurve.xlsx") |> Predicer.tweak_input!

bm = Profile.Allocs.@profile(
    sample_rate=0.002, @benchmark Predicer.generate_model(inp))
PProf.Allocs.pprof()
bm
