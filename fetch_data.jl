using SpineInterface

path = "sqlite:///$(@__DIR__)/input_data/input_data.sqlite"

using_spinedb(path)
# now we have a direct handle access entities of the sqlite db from the path

# the following callable subfield terms are from: ? node
node.name
node.objects
node.parameter_values

# some useful tips
first(node.parameter_values)

# objects
Code_Country()
Code_Country()[1]
Code_Country()[1:3]
countries = Code_Country()[1:3]
Code_Country(:DE)
Code_Country(Symbol("DE"))
setdiff(Code_Country(), Code_Country(:DE))

# relationships
# ? Construction_Massive
# object_class_names to distinguish between names from same objective type, e.g. unit__node__node
Construction_Massive()

Construction_U()
Construction_U() == Construction_U.relationships
Construction_U.object_class_names
first(Construction_U.relationships)
first(Construction_U.relationships).Code_Construction

# objective class as a filter
cc = first(Code_Construction())
Construction_U(Code_Construction = cc)

cc = Code_Construction()[1:10]
Construction_U(Code_Construction = cc)
first(Construction_U(Code_Construction = cc))
first(Construction_U(Code_Construction = cc; _compact = false))

Construction_U.parameter_values
Construction_U.parameter_defaults
# a pair
first(Construction_U.parameter_values)
# the key
first(Construction_U.parameter_values)[1]
# the values
first(Construction_U.parameter_values)[2]

Construction_U.parameter_defaults
# we can see U as a parameter value

# access parameter_values
U.classes
# fields need provide from the above
Construction_U.object_class_names
# basically, U(Code_Construction = object, Code_Country = , ...)
# objects are the input parameters, see above for how to obtain objectives

# array of objects
[Code_Country(name) for name in [:CY, :DE, :GB]]

con_u = first(Construction_U.relationships)
U(;con_u...)

# use filter function, refer to: ? filter
filter(x -> x.name in [:CY, :DE, :GB], Code_Country())
filter(x -> !in(x.name, [:CY, :DE, :GB]), Code_Country())

# write data into a spinedb
# generic, import_data, see ?import_data
# about data structure, see types.jl
oc = ObjectClass(:a, [])

