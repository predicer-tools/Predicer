module IDH # InputDataHandler
    import Predicer

    export get_data
    export export_model_contents_dict
    export init_model
    export solve_model

    include(joinpath(@__DIR__, ".\\import_input_data.jl"))

    function get_data()
        return import_input_data()
    end

    function export_model_contents_dict(mc, results=false)
        Predicer.export_model_contents(mc, false)
        if results
            Predicer.export_model_contents(mc, results)
        end
    end

    function init_model()
    # Import data using descriptive layer translating the input data to an abstract format
        imported_data = import_input_data()
        model_contents = Predicer.Initialize(imported_data)
        return model_contents
    end

    function solve_model(model_contents)
        return Predicer.solve_model(model_contents)
    end
    
    function get_result_df(mc,type="",process="",node="",scenario="")
        return Predicer.get_result_dataframe(mc,type,process,node,scenario)
    end
    
    function export_bid_matrix(mc)
        input_data = get_data()
        Predicer.write_bid_matrix(mc,input_data)
    end

    # Add function used to define the path of the input data?
    
end # module
