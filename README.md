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

        (IDH) pkg> activate .

- Press backspace to exit the package manager
- Type `using IDH` to use the package.

        julia> using IDH

- `IDH.init_model()` builds the model based on the defined input data in `.\\input_data\\input_data.xlsx`, and returns a dictionary containing the model and the model structure. 
        
        julia> mc = IDH.init_model();


- `IDH.solve_model(mc)` solves the model `mc`, and shows the output of the solver.

        julia> IDH.solve_model(mc)

- `IDH.export_model_contents(mc, results=false)` can be used to export structure and indices of the model to an excel file located in `.\\results\\`. If the parameter `results` is true and the model has been solved, two files will be generated. One file (model_contents_yyy_mm_dd_hh_mm_ss.xlsx) contains the structure and indices of the model, and the other (model_contents_results_yyy_mm_dd_hh_mm_ss.xlsx) contains the model structure and the values for these. 

        julia> IDH.export_model_contents(mc)

        julia> IDH.export_model_contents(mc, true)