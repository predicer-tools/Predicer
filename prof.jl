using Profile
using PProf
using CPUTime
using Pkg

Pkg.activate(".")

using Predicer

Profile.init(n=10^7, delay=0.01)

inp = Predicer.get_data(
    "input_data/input_data_bidcurve_medium.xlsx") |> Predicer.tweak_input!

@time @CPUtime @pprof mc = Predicer.generate_model(inp)
