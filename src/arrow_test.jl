using Pkg
Pkg.activate(".")  # Activates the environment in the current directory
Pkg.add("Arrow")
Pkg.add("Base64")
Pkg.add("DataFrames")
using Arrow, Base64, DataFrames

function process_arrow_data()
    println("Waiting for data or 'exit' command...")
    data = readline()  # Wait for data on stdin
    if startswith(data, "data:")
        println("Data received, processing...")
        # Extract the base64-encoded Arrow data
        encoded_data = data[6:end]
        # Decode the base64 data to binary
        arrow_data = base64decode(encoded_data)
        # Load the Arrow data as a Table, then convert to DataFrame
        arrow_table = Arrow.Table(IOBuffer(arrow_data))
        df = DataFrame(arrow_table)
        # Process the DataFrame as needed
        println(df)
    elseif data == "exit"
        println("Exit command received, terminating...")
    else
        println("Unrecognized input received.")
    end
    exit(0)  # Exit after processing data or receiving 'exit'
end

process_arrow_data()
