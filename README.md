# Predicer
‘Predictive decider’ for actors making decisions over multiple stages

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

- To generate a model based on a input data file (in the example an Excel file located under `Predicer\\input_data\\`) use the `Predicer.generate_model(fpath)` function, where the parameter 'fpath' is the path to the input data file. The 'generate_model()' function imports the input data from the defined location, and build a model around it. The function returns two values, a "model contents" (mc) dictionary containing the built optimization model, as well as used expressions, indices and constraints for debugging. The other return value is the input data on which the optimization model is built on. 
        
        julia> mc, input_data = Predicer.generate_model(fpath)

- Or if using the example input data file `Predicer\\input_data\\input_data.xlsx`

        julia> mc, input_data = Predicer.generate_model(joinpath(pwd(), "input_data\\input_data.xlsx"))


- `Predicer.solve_model(mc)` solves the model `mc`, and shows the solver output.

        julia> Predicer.solve_model(mc)


- The resulting bid matrix can be exported to a .xlsx file under `Predicer\\results` by using the `Predicer.write_bid_matrix()` function

        julia> Predicer.write_bid_matrix(mc, input_data)


## Input data parameters


| Parameter               | Type   | Description                                                |
|-------------------------|--------|------------------------------------------------------------|
| node                    | String | Name of the node                                           |
| is_commodity            | Bool   | Indicates if the node is a commodity node                  |
| is_state                | Bool   | Indicates if the node has a state (storage)                |
| is_res                  | Bool   | Indicates if the node is involved in reserve markets       |
| is_market               | Bool   | Indicates if the node is a market node                     |
| is_inflow               | Bool   | Indicates if the node has an inflow                        |
| state_max               | Float  | Storage state capacity (if node has a state)               |
| in_max                  | Float  | Storage state charge capacity                              |
| out_max                 | Float  | Storage state discharge capacity                           |
| initial_state           | Float  | Initial state of the storage                               |
| state_loss_proportional | Float  | Hourly storage loss relative to the state of the storage   |
| residual_value          | Float  | Value of the storage contents at the end of the time range |