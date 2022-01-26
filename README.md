# Predicer
‘Predictive decider’ for actors making decisions over multiple stages

## How to use

- Clone the project to your computer using git.
- Make sure that the main branch  is activated.
- Open a julia REPL. It is recommended to use a IDE such as VSCode or Atom, as the results from the model are currently not saved in a separate file.
- Navigate to *.\Predicer* using the `cd` command.

        julia> cd("./Predicer)

- type `]` to open the package manager in julia, and type `activate .` to activate the local Julia environment.

        (Predicer) pkg> activate .

- Press backspace to exit the package manager
- Type `using Pkg` followed by `Pkg.instantiate()` to install the required packages. This can take a while.
- In case of errors, type `Pkg.instantiate()` again. This usually works for some reason. 

        julia> using Pkg
        julia> Pkg.instantiate()

- Finally type `using Predicer` to use the package.

        julia> using Predicer

- Use `Predicer.get_data()` to import the local data defined in the input data file. Use `Predicer.run_AbstractModel()` to run the current version of the model base don the defined input data. 
        
        julia> d = Predicer.get_data();
        julia> Predicer.run_AbstractModel(d);

- The output of the model is not refined at the current state, and can be enabled by setting the "export_to_excel"-flag to 1 in '\Predicer\AbstractModel\src\AM.jl'.
