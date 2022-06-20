using Documenter
using Predicer

Documenter.makedocs(build = "build",
    clean = true,
    doctest = false,
    modules = Module[Predicer],
    repo = "",
    highlightsig = true,
    sitename = "Predicer documentation",
    expandfirst = [],
    pages = [
            "Index" => "index.md"
            "API reference" => "api.md"
    ]
)
