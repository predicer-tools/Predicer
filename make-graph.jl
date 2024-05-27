#=
   $ julia --project=. make-graph.jl input_data/*.xlsx
   $ dot -Tsvg -O input_data/*.dot
=#

using ArgParse
using Predicer

"""
    write_graph(fname :: String, inp :: Predicer.InputData)

Write `inp` as Graphviz (dot) into file `fname`.  Only shows the basic
structure; no numbers are written.  Assumes that node and process
names are valid identifiers.
"""
function write_graph(fname :: String,
                     inp :: Predicer.InputData) :: Nothing
    open(fname, "w") do f
        println(f, "digraph {")
        for (n, no) in inp.nodes
            println(f, "  $n [class=\"node\", shape=oval]")
        end
        for (p, pr) in inp.processes
            # For pr.conversion == 1, pr.topos go between nodes and
            # the process.  For pr.conversion == 2, 3, they go between
            # nodes, bypassing the process.
            cls = ["process", "transfer", "market"][pr.conversion]
            shape = ["box", "note", "tab"][pr.conversion]
            head = ["normal", "vee", "onormal"][pr.conversion]
            println(f, "\n  $p [class=$cls, shape=$shape]")
            for e in pr.topos
                (s, t) = (e.source, e.sink)
                edges = pr.conversion == 1 ? "$s -> $t" : "$s -> $p -> $t"
                println(f, "  $edges [class=$cls, arrowhead=$head]")
            end
        end
        for (s, t, _...) in inp.node_delay
            println(f, "  $s -> $t [class=delay, style=dashed, arrowhead=vee]")
        end
        for nd in inp.node_diffusion
            (s, t) = (nd.node1, nd.node2)
            println(f, "  $s -> $t [class=diffusion, style=dashed,"
                    * " arrowhead=odot]")
        end
        println(f, "}")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    aps = ArgParseSettings(
        description="Plot graphs (dot) of Predicer input")
    @add_arg_table! aps begin
        "file"
        help = "input files (xlsx)"
        nargs = '+'
        # bug: nargs does not make it required
        required = true
    end
    args = parse_args(aps; as_symbols=true)
    for f in args[:file]
        of = replace(f, r"[.][^.]*$" => "") * ".dot"
        println("$f |-> $of")
        inp = Predicer.get_data(f) |> Predicer.tweak_input!
        write_graph(of, inp)
    end
end
