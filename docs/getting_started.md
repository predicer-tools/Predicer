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

- To generate a model based on a input data file (in the example an Excel file located under `Predicer\\input_data\\`) use the `Predicer.generate_model(fpath)` function, where the parameter 'fpath' is the path to the input data file. The 'generate_model()' function imports the input data from the defined location, and build a model around it. The function returns two values, a "model contents" (mc) dictionary containing the built optimization model, as well as used expressions, indices and constraints for debugging. The other return value is the input data on which the optimization model is built on. 
        

      julia> mc, input_data = Predicer.generate_model(fpath)

- Or if using the example input data file `Predicer\\input_data\\input_data.xlsx`

      julia> mc, input_data = Predicer.generate_model(joinpath(pwd(), "input_data\\input_data.xlsx"))


- `Predicer.solve_model(mc)` solves the model `mc`, and shows the solver output.

      julia> Predicer.solve_model(mc)


- The resulting bid matrix can be exported to a .xlsx file under `Predicer\\results` by using the `Predicer.write_bid_matrix()` function

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
| -------- | -------- | ----------- | ------- |
| ngchp_c1 | eq       | 0           | 0       |

Further, the factors for the constraint are defined in the *gen_constraint* sheet. The operator of the created constraint is *eq*, meaning equal.  The sum of the factors (the process branches *elc* and *heat* multiplied by given constants) and a given constant should equal 0. With a 1:2 ratio of electricity and heat production, the constants given to the process flows should be -2 and 1, or 2 and -1, for electricity and heat respectively. This can be seen in the table below, where the factors and constraints are defined for *s1*. The factors have to be defined again for *s2*.

| t    | ngchp_c1,ngchp,elc,s1 | ngchp_c1,ngchp,heat,s1 | ngchp_c1,s1 |
| ---- | --------------------- | ---------------------- | ----------- |
| t1   | -2                    | 1                      | 0           |
| t2   | -2                    | 1                      | 0           |
| tn   | -2                    | 1                      | 0           |

