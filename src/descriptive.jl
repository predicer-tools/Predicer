#using AbstractModel

# Import data using descriptive layer translating the input data to an abstract format
imported_data = include(".\\import_input_data.jl")()
temporals = imported_data[1]
nodes = imported_data[2]
processes = imported_data[3]
markets = imported_data[4]




#model = AbstractModel.Initialize_model(imported_data)



