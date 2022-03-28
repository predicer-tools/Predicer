module Predicer
    import AbstractModel

    export get_data
    export test_AM2
    export export_model_contents_dict
    export init_model
    export solve_model

    function run_AbstractModel(d)
        return AbstractModel.run_AM(d)
    end

    function get_data()
        return include(".\\src\\import_input_data.jl")()
    end

    function export_model_contents_dict(mc, results=false)
        AbstractModel.export_model_contents(mc, false)
        if results
            AbstractModel.export_model_contents(mc, results)
        end
    end

    function init_model()
    # Import data using descriptive layer translating the input data to an abstract format
        imported_data = include(".\\src\\import_input_data.jl")()
        model_contents = AbstractModel.Initialize(imported_data)
        return model_contents
    end

    function solve_model(model_contents)
        return AbstractModel.solve_model(model_contents)
    end
    
    function get_result_df(mc,type="",process="",node="",scenario="")
        return AbstractModel.get_result_dataframe(mc,type,process,node,scenario)
    end
    
    function export_bid_matrix(mc)
        input_data = get_data()
        AbstractModel.write_bid_matrix(mc,input_data)
    end

end # module
