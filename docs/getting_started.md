# Getting Started
## How to install

- Clone the project to your computer using git.
- Make sure that the main branch is activated.
- Open a julia REPL. It is recommended to use a IDE such as VSCode or Atom, as the results from the model are currently not saved in a separate file.
- Navigate to *.\Predicer* using the `cd` command.

        julia> cd("./Predicer)

- type `]` to open the package manager in julia, and type `activate .` to activate the local Julia environment.

        (Predicer) pkg> activate .

- Press backspace to exit the package manager
- Type `using Pkg` followed by `Pkg.instantiate()` to install the required packages. This can take a while.

        julia> using Pkg
        julia> Pkg.instantiate()

- Finally type `using Predicer` to use the package.

## How to use

- Navigate to the local folder containing the Predicer package.
- type `]` to open the package manager in julia, and type `activate .` to activate the local Julia environment.

        (Predicer) pkg> activate .

- Press backspace to exit the package manager
- Type `using Predicer` to use the package.

        julia> using Predicer

- To generate a model based on a input data file (in the example an Excel file located under `Predicer/input_data/`) use the `Predicer.generate_model(fpath)` function, where the parameter 'fpath' is the path to the input data file. The 'generate_model()' function imports the input data from the defined location, and build a model around it. The function returns two values, a "model contents" (mc) dictionary containing the built optimization model, as well as used expressions, indices and constraints for debugging. The other return value is the input data on which the optimization model is built on. 
        
        julia> mc, input_data = Predicer.generate_model(fpath)

- Or if using the example input data file `Predicer/input_data/input_data.xlsx`

        julia> mc, input_data = Predicer.generate_model("input_data/input_data.xlsx")


- `Predicer.solve_model(mc)` optimizes the model, and shows the solver output.

        julia> Predicer.solve_model(mc)

- After the model has been successfully optimized, the results of the variables in the model can be obtained using the `Predicer.get_result_dataframe()` or `Predicer.get_all_result_dataframes()` functions. Predicer.get_all_result_dataframes returns a dictionary with the variable names as keys, and Dataframes containing the results for those keys as values. 

        julia> result_dataframes = Predicer.get_all_result_dataframes(mc, input_data)
        julia> Predicer.get_all_result_dataframes(mc, input_data)
                Dict{Any, Any} with 21 entries:
                "vq_state_dw"      => 24×13 DataFrame…
                "v_set_up"         => 24×1 DataFrame… 
                "v_flow_bal"       => 24×7 DataFrame… 
                "v_bid"            => 24×4 DataFrame… 
                "v_node_delay"     => 24×1 DataFrame… 
                "v_block"          => 0×0 DataFrame   
                "v_res_final"      => 24×10 DataFrame…
                "v_set_down"       => 24×1 DataFrame… 
                "vq_ramp_dw"       => 24×22 DataFrame…
                "v_start"          => 24×4 DataFrame… 
                "vq_state_up"      => 24×13 DataFrame…
                "vq_ramp_up"       => 24×22 DataFrame…
                "v_setpoint"       => 24×1 DataFrame… 
                "v_node_diffusion" => 24×1 DataFrame… 
                "v_online"         => 24×4 DataFrame… 
                "v_stop"           => 24×4 DataFrame… 
                "v_reserve"        => 24×37 DataFrame…
                "v_flow"           => 24×37 DataFrame…
                "v_load"           => 24×10 DataFrame…
                "v_reserve_online" => 24×7 DataFrame… 
                "v_state"          => 24×7 DataFrame… 

- For more specific analysis, `Predicer.get_result_dataframe()` returns a DataFrame for a specific variable type, with the option to specify the node or process as well as the scenario. Below an example where the values for the `v_flow` variable for the `hp1` process is obtained. The column names show which flow the value is for, with the notation being `processname _ from node _ to node _ scenario`; `hp1_elc_hp1_s1` is for the electricity consumption of the heat pump process, and `hp1_hp1_dh_s1` is for the heat production to the district heating node (dh). The types of the available variables can be found in the function documentation or in the example above. 

        julia> Predicer.get_result_dataframe(mc, input_data, "v_flow", "hp1",  "s1")
                24×3 DataFrame
                Row │ t                          hp1_elc_hp1_s1  hp1_hp1_dh_s1 
                │ String                     Float64         Float64       
                ─────┼──────────────────────────────────────────────────────────
                1 │ 2022-04-20T00:00:00+00:00       0.5              1.5
                2 │ 2022-04-20T01:00:00+00:00       0.0              0.0
                3 │ 2022-04-20T02:00:00+00:00       0.0              0.0
                ⋮  │             ⋮                    ⋮               ⋮
                22 │ 2022-04-20T21:00:00+00:00       0.970055         3.39519
                23 │ 2022-04-20T22:00:00+00:00       1.42857          5.0
                24 │ 2022-04-20T23:00:00+00:00       1.71429          6.0

- The modelled costs can be retrieved using the `get_costs_dataframe()` function. This includes realised costs, controlling costs and dummy costs. The realised costs include costs of used fuels and commodities, operational costs, market costs/profits, etc. The controlling costs include the value of the storage at the end of the optimization horizon, deviation from setpoints, etc. Dummy costs include costs for dummy or slack variables, which are used to ensure feasibility during optimization. 

        julia> costs_df = Predicer.get_costs_dataframe(mc, input_data)

- The DataFrames obtained from the results can be exported to an xlsx-file using the `dfs_to_xlsx()` function. The Dataframes can be passed to the function either in a dictionary with the name of the dataframe as the keys, or as a single DataFrame. The other parameters passed to the function are `output_path`, which is the path to where the file is to be saved, and `fname` is the name of the exported file. An suffix with the date is automatically added to the end of the filename. 

        julia> Predicer.dfs_to_xlsx(df, output_path, fname)


- The resulting bid matrix can be exported to a .xlsx file under `Predicer/results` by using the `Predicer.write_bid_matrix()` function

        julia> Predicer.write_bid_matrix(mc, input_data)


## Example model

A simple example model simple, imaginary energy system is documented here. The input data file of the example model can be found under */input_data/example_model.xlsx*. The system contains natural gas, electricity and heat, and electricity and electricity reserve products are sold on an external market *m*. The example model contains two possible scenarios for input data, *s1* and *s2*, with equal probabilities of occurring (0.5). The data used for prices, heat demand, capacity factors, etc. is randomly generated. 

#### Nodes

The modelled system consists of three main nodes: ***ng***, symbolizing a node containing natural gas, ***elc*** symbolizing a node containing electricity, and ***heat***, a node containing heat, such as a district heating system. The *ng* node is a *commodity node*, from which natural gas can be bought at a price defined in the *price* sheet. The *heat* node has a negative *inflow* added to it, which can be seen as a heat demand in the system. The *elc* node is connected to a market node ***m***, *npe*, from which electricity can be bought or sold. 

#### Processes 

Processes are used to convert or transfer energy between nodes in the modelled system. The process ***windturb*** symbolizes a wind turbine producing electricity to the *elc* node. The production of *windturb* is limited by a capacity factor time series, defined in the *cf* sheet. The process ***ngchp*** converts natural gas from the *ng* node into electricity to the *elc* node and heat to the *heat* node at a fixed ratio, which is defined in the *constraint* and *gen_constraint* sheets. The ***heatpump*** unit convert electricity from the *elc* node into heat in the *heat* node. When the market *m* is defined, a process for trading between *elc* and *m* is automatically generated. 

The constraint to define the operation of the *ngchp* process is setup in the *constraints* and *gen_constraint* sheets. The flat efficiency of the *ngchp* process is set to 0.9, including both heat and power. The maximum capacity of the natural gas input is set to 10, the heat is 6, and the electricity is 3. *ngchp* should produce electricity and heat at a 1:2 ratio. To achieve this, constraint called *ngchp_c1* is defined in the sheet *constraints*.

The reserve products ***res_up*** and ***res_down*** are sold in the *elc* node. The processes *ngchp* and *heatpump* are used to offer reserve capacity. 

![alt_text](https://github.com/vttresearch/Predicer/blob/f2e78346ae3802d16d84ccb5ca4ef076871ed43f/docs/images/example_model.PNG)
Basic structure of the example model.

| name     | operator | is_setpoint | penalty |
|----------|----------|-------------|---------|
| ngchp_c1 | eq       | 0           | 0       |

Further, the factors for the constraint are defined in the *gen_constraint* sheet. The operator of the created constraint is *eq*, meaning equal.  The sum of the factors (the process branches *elc* and *heat* multiplied by given constants) and a given constant should equal 0. With a 1:2 ratio of electricity and heat production, the constants given to the process flows should be -2 and 1, or 2 and -1, for electricity and heat respectively. This can be seen in the table below, where the factors and constraints are defined for *s1*. The factors have to be defined again for *s2*.

| t  | ngchp_c1,ngchp,elc,s1 | ngchp_c1,ngchp,heat,s1 | ngchp_c1,s1|
|----|-----------------------|------------------------|------------|
| t1 | -2                    | 1                      | 0          |
| t2 | -2                    | 1                      | 0          |
| tn | -2                    | 1                      | 0          |


