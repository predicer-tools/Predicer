using ArgParse
using XLSX
using CSV

function detab(fname :: String) :: Nothing
    odir = replace(fname, r"[.][^.]*$" => "")
    mkpath(odir)
    XLSX.openxlsx(fname) do xl
        for sn in XLSX.sheetnames(xl)
            ofn = joinpath(odir, sn * ".csv")
            xl[sn] |> XLSX.gettable |> CSV.write(ofn)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    aps = ArgParseSettings(
        description="Save each Excel workbook tab as a CSV file")
    @add_arg_table aps begin
        "file"
        help = "input files (xlsx)"
        nargs = '+'
        # bug: nargs does not make it required
        required = true
    end
    args = parse_args(aps; as_symbols=true)
    for f in args[:file]
        detab(f)
    end
end
