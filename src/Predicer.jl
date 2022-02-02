module Predicer
    import AbstractModel

    export get_data
    export test_AM2
    export export_model_contents_dict

    function run_AbstractModel(d)
        return AbstractModel.run_AM(d)
    end

    function get_data()
        return include(".\\src\\import_input_data.jl")()
    end

    function export_model_contents_dict(mc)
        return AbstractModel.export_model_contents(mc)
    end

    function init_model()
    # Import data using descriptive layer translating the input data to an abstract format
        imported_data = include(".\\src\\import_input_data.jl")()
        model_contents = AbstractModel.Initialize(imported_data)
        return model_contents
    end
    
end # module
