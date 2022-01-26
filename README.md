# Predicer
‘Predictive decider’ for actors making decisions over multiple stages

## How to use

- Clone the project to your computer using git.
- Make sure that the branch "adding_example_model" is activated.
- Open a julia REPL. It is recommended to use a IDE such as VSCode or Atom, as the results from the model are currently not saved in a separate file. 
- Navigate to *Predicer/model* using the `cd` command.

        julia> cd("./Predicer/model/")

- type `]` to open the package manager in julia, and type `activate .` to activate the local Julia environment.

        (AbstractModel) pkg> activate .

- Press backspace to exit the package manager
- Type `using Pkg` followed by `Pkg.instantiate()` to install the required packages. This can take a while.
- In case of errors, type `Pkg.instantiate()` again. This usually works for some reason. 

        julia> using Pkg
        julia> Pkg.instantiate()

- Finally type `using AbstractModel` to use the package.

        julia> using AbstractModel
        julia> run_model()
