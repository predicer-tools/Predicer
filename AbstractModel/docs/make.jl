using Documenter
using AbstractModel

Documenter.makedocs(source = "src",
    build = "build",
    clean = true,
    doctest = false,
    modules = Module[AbstractModel],
    repo = "",
    highlightsig = true,
    sitename = "AbstractModel documentation",
    expandfirst = [],
    pages = [
            "Index" => "index.md"
            "API reference" => "api.md"
    ]
)
