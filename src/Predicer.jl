module Predicer
    import AbstractModel

    export get_data
    export test_AM2

    function test_AM2(d)
        return AbstractModel.test_AM(d)
    end

    function get_data()
        return include(".\\src\\import_input_data.jl")()
    end

    #= function init_model()
    # Import data using descriptive layer translating the input data to an abstract format
        imported_data = include(".\\src\\import_input_data.jl")()
        model = AbstractModel.Initialize_model(imported_data)
        return 0
    end  =#
    
end # module
