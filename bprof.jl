using BenchmarkTools
using PProf
using Pkg

Pkg.activate(".")

using Predicer

const inp = Predicer.get_data(
    "input_data/input_data_bidcurve.xlsx") |> Predicer.tweak_input!

bm = @bprofile Predicer.generate_model(inp)
pprof()
bm
