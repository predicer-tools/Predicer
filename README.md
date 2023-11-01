documentation available
<iframe 
  width="660"
  height="375"
  src="https://img.shields.io/badge/docs-main-green?logo=github&link=https%3A%2F%2Fvttresearch.github.io%2FPredicer%2F"
  frameborder="0"
  allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture"
  allowfullscreen>
</iframe>

# Predicer
‘Predictive decider’ for actors making decisions over multiple stages

If you use Predicer in a public work, please cite [the following document](https://doi.org/10.1007/s11081-023-09824-w)

Pursiheimo, E., Sundell, D., Kiviluoma, J., & Hankimaa, H. (2023). Predicer: abstract stochastic optimisation model framework for multi-market operation. Optimization and Engineering, 1-30.

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
|----------|----------|-------------|---------|
| ngchp_c1 | eq       | 0           | 0       |

Further, the factors for the constraint are defined in the *gen_constraint* sheet. The operator of the created constraint is *eq*, meaning equal.  The sum of the factors (the process branches *elc* and *heat* multiplied by given constants) and a given constant should equal 0. With a 1:2 ratio of electricity and heat production, the constants given to the process flows should be -2 and 1, or 2 and -1, for electricity and heat respectively. This can be seen in the table below, where the factors and constraints are defined for *s1*. The factors have to be defined again for *s2*.

| t  | ngchp_c1,ngchp,elc,s1 | ngchp_c1,ngchp,heat,s1 | ngchp_c1,s1|
|----|-----------------------|------------------------|------------|
| t1 | -2                    | 1                      | 0          |
| t2 | -2                    | 1                      | 0          |
| tn | -2                    | 1                      | 0          |



## Input data description

The basic parameters and usage of the excel-format input data are described here. The input data has to be given to Predicer in a specific form, and the excel-format input data files are not a requirement. Excel has been used during development, since they were considered more convenient than databases or other forms of data structures.

### Node

Nodes are fundamental building blocks in Predicer, along with Processes.

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



### Processes

Processes are fundamental building blocks in Predicer, along with Nodes. They are used to convert or transfer electricity or heat, or etc. between nodes in the modelled system.

| Parameter     | Type    | Description                                                                                         |
|---------------|---------|-----------------------------------------------------------------------------------------------------|
| process       | String  | Name of the process                                                                                 |
| is_cf         | Bool    | Indicates if the process is limited by a capacity factor time series                                |
| is_cf_fix     | Bool    | Indicates if the process has to match the capacity factor time series                               |
| is_online     | Bool    | Indicates if the process is an online/offline unit                                                  |
| is_res        | Bool    | Indicates if the process participates in reserve markets                                            |
| conversion    | Integer | Indicates the type of the process. 1 = unit based process, 2 = transfer process, 3 = market process |
| eff           | Float   | Process efficiency (total output / total input)                                                     |
| load_min      | Float   | Minimum load of the process as a fraction of total capacity. Only for online processes              |
| load_max      | Float   | Maximum load of the process as a fraction of total capacity. Only for online processes              |
| start_cost    | Float   | Cost of starting the unit, only for online processes.                                               |
| min_online    | Float   | Minimum time the process has to be online after start up                                            |
| min_offline   | Float   | Minimum time the process has to be offline during shut down                                         |
| max_online    | Float   | Maximum time the process can be online                                                              |
| max_offline   | Float   | Maximum time the process can be offline                                                             |
| initial_state | Bool    | Initial state of the online unit (0 = offline, 1 = online)                                          |



### Process topology

Process topologies are used to define the process flows and capacities in the modelled system. Flows are connections between nodes and processes, and are used to balance the modelled system.

| Parameter   | Type   | Description                                                                       |
|-------------|--------|-----------------------------------------------------------------------------------|
| process     | String | Name of the process                                                               |
| source_sink | String | Determines whether the connection node is a source or a sink for the process      |
| node        | String | Name of the connection node                                                       |
| capacity    | Float  | Capacity of the connection                                                        |
| VOM_cost    | Float  | Variable operational and maintenance cost of using the corresponding process flow |
| ramp_up     | Float  | Determines the hourly upward ramp rate of the corresponding process flow          |
| ramp_down   | Float  | Determines the hourly downward ramp rate of the corresponding process flow        |



### Efficiencies
Unit-based processes can have a flat efficiency, as defined in the *processes* sheet, or an efficiency which depends on the load of the process. Load-based efficiency can be defined in the sheet *efficiencies*. Defining an efficiency in the *efficiencies* sheet overrides the value given in the *processes* sheet. The efficiency of a process is  defined on two rows; one row for the *operating point*, *op*, and one row for the corresponding *efficiency*, *eff*.  In the example table below, the efficiency of an imaginary gas turbine *gas_turb* has been defined for four load intervals. The number of given operating points and corresponding efficiencies is chosen by the user, simply by adding or removing columns The operating points are defined on a row, where the first column has the value ***process,op***, and the efficiencies are defined on a row where the value of the first column is ***process,eff***. 


| process      | 1    | 2    | 3    | 4    |
|--------------|------|------|------|------|
| gas_turb,op  | 0.4  | 0.6  | 0.8  | 1.0  |
| gas_turb,eff | 0.27 | 0.31 | 0.33 | 0.34 |



### Reserve type

The sheet *reserve_type* is used to define the types of reserve used in the model, mainly differing based on reserve activation speed. 

| Parameter | Type | Description |
|-------------|--------|-------------------------------------------------------------------------------------------------------------------------------------------|
| type        | String | Name of the reserve type                                                                                                                  |
| ramp_factor | Float  | Ramp rate factor of reserve activation speed. (If reserve has to activate in 1 hour, ramp_factor is 1.0. In 15 minutes, ramp_factor is 4) |



### Market

Markets are a type of node, with which the modelled system can be balanced by buying or selling of a product such as electricity. Markets can either be of the *energy* type, or of the *reserve* type. 

| Parameter    | Type   | Description                                                                      |
|--------------|--------|----------------------------------------------------------------------------------|
| market       | String | Name of the market                                                               |
| type         | String | type of the market (energy or reserve)                                           |
| node         | String | Node the market is connected to                                                  |
| direction    | String | Direction of the market, only for reserve markets                                |
| realisation  | Float  | Determines the fraction of offered reserve product that activates each time step |
| reserve_type | String | Determines the type of the reserve                                               |
| is_bid       | Bool   | Determines if bids can be offered to the market                                  |
| is_limited   | Bool   | Determines if reserve markets are limited                                        |
| min_bid      | Float  | Minimum reserve offer if limited                                                 |
| max_bid      | Float  | Maximum reserve offer if limited                                                 |
| fee          | Float  | Reserve participation fee (per time period) if limited                           |



### Time series data

Time series are used in Predicer to represent parameters that are time-dependent. The notation to define time series data in the excel input files depend on the time series data in question. 

The sheet *timeseries* contains the timesteps used in the model. This sheet contains only one column *t*, with the given time steps.

#### Time series notation in the excel-format input data

The first column, *t*, should contain the time steps for the time series data. The following columns (2-n) should contain the values corresponding to the given time steps. The name of the other columns should start with the name of the linked entity, usually followed by which scenario the value is for. The values can be defined for each scenario in separate columns, or a single column can be used for several scenarios, separated by commas. The notation used for the different time series is given in the table below.

As an example the inflow for the node *nn* can be given as ***nn,s1*** if the values are given for scenario *s1*, and ***nn,s1,s2*** if the given values should be for both *s1* and *s2*. If all scenarios should have the same values, they can be defined as ***nn,ALL***. 

| Sheet          | Description                                                                 | Notation                          |
|----------------|-----------------------------------------------------------------------------|-----------------------------------|
| cf             | Capacity factor time series for processes with cf functionality             | process, scenario(s)              |
| inflow         | Inflow time series for nodes (inflow positive value, demand negative value) | node, scenario(s)                 |
| price          | Price time series for the cost of using commodity nodes                     | node, scenario(s)                 |
| market_prices  | Price time series for the defined markets                                   | market, scenario(s)               |
| balance_prices | Price time series for balance markets                                       | market, direction, scenario(s)    |
| fixed_ts       | Value time series for setting market volumes to a fixed value               | market                            |
| eff_ts         | Value time series of the efficiency of processes                            | process, scenariox(s)             |
| cap_ts         | Value time series limiting a flow of a process                              | Process, connected node, scenario |



### Scenario

The scenarios in Predicer are separate versions of the future, with potentially differing parameter values. Predicer optimizes the optimal course of action, based on the probability of the defined scenarios.

| Parameter   | Type   | Description                                                  |
|-------------|--------|--------------------------------------------------------------|
| name        | String | Name of the scenario                                         |
| probability | Float  | Probability of the scenario. The sum of all rows should be 1 |



### Risk

The *risk* sheet in the excel-format input data contains information about the CVaR (conditional value at risk). For details, see [[1]](#1) and [[2]](#2)


| Risk parameter | Description                         |
|----------------|-------------------------------------|
| alfa           | Risk quantile                       |
| beta           | Share of CVaR in objective function |


### Inflow blocks

*Inflow blocks*, or simply *blocks*, are potential flexibility which can be modelled with *Predicer*. A block has generally been thought of as "if a demand response action is taken on time *t* by reducing/increasing *inflow* to *node* *n* by amount x, how must the system compensate on times- t-1, t-2.. or t+1, t+2...", or "if the heating for a building is turned off on time t, what has to be done in the following hours to compensate?". The blocks can thus be seen as a potential for flexibility, and how the system has to be compensated as a consequence of using the potential.

Each *block* consists of a binary variable, consequent timesteps, and a constant value for each timestep. Each block is linked to a specific node, as well as a specific scenario. Despite being called "Inflow blocks", they can be linked to nodes without any inflow as well. Node inflow is modelled for each timestep and scenario as the given value in the *inflow* sheet. The product of the block binary variable value and the given constant is added to the inflow for relevant combinations of node, scenario and timestep. Two active blocks cannot overlap in the same node, time and scenario. The user can define any number of blocks for the same time, but only one can be active for a specific node, scenario and timestep. 

Inflow blocks are defined in the ***inflow_blocks*** sheet. The first column of the sheet is named *t*, and is not used in the model itself. Each block is defined using two columns for each scenario; one column with the timesteps and one column with the corresponding constant values. The first row of the first column is of the form ***blockname, nodename, scenario***, and the second column is ***blockname, scenario***. It is important, that these columns have an equal amount of rows. The columns for different blocks or different scenarios can have different amount of rows. 

As an example, assume there are two blocks, ***b1*** and ***b2***. The blocks should be defined to the *inflow_blocks* sheet as following:

| t | b1, n1, s1     | b1, s1 | b1, n1, s2     | b1, s2 | b2, n2, s1     | b2, s1 |
|---|----------------|--------|----------------|--------|----------------|--------|
| 1 | 20.4.2022 1:00 | 6      | 20.4.2022 3:00 | 4      | 20.4.2022 6:00 | -3     |
| 2 | 20.4.2022 2:00 | -3     | 20.4.2022 4:00 | -2     | 20.4.2022 7:00 | 2      |
| 3 | 20.4.2022 3:00 | -2     | 20.4.2022 5:00 | -2     | 20.4.2022 8:00 | 1      |
| 4 | 20.4.2022 4:00 | -1     |                |        | 20.4.2022 9:00 | 1      |


As with the generic constraints described below, the validity of the user input is not checked. The user should thus ensure, that the node linked to the block can handle the change in inflow, especially in nodes with either only consumers or producer. If a block causes a change in the sign of the inflow (- to +, or + to -), the results may be unpredictable. As an example, using a block causing a positive flow of heat into a district heating node without any way to remove the heat would result in high penalty costs, and the model would thus not use the block.


### General constraints

General constraints in Predicer can be used to limit or fix process flow variables, online variables, or storage state variables in relation to other variables or a given value. The name and type of the constraint is defined in the sheet *constraints*, and the factors are defined in the sheet *gen_constraint*. 

#### constraint

| Parameter   | Type   | Description                                                                              |
|-------------|--------|------------------------------------------------------------------------------------------|
| name        | String | Name of the general constraint                                                           |
| operator    | String | The operator used in the general constraint. *eq* for *=*, *gt* for *>* and *lt* for *<* |
| is_setpoint | Bool   | Indicates whether the constraint is fixed, or if the model can deviate from the value.   |
| penalty     | Float  | A user-defined penalty for deviating from the givenn value, if constraint is a setpoint. |



#### gen_constraint

The user can define additional constraints to the Predicer model, making it more flexible. Genral constraints are a powerful tool for customizing the model, but can also cause problems that are difficult to detect and solve. The user can either add "rigid" constraints, essentially defining a value or a range of values from which a variable or a sum of variables cannot deviate. Normal general constraints are applicable for flow, state and online variables. 

The user can also define so-called "setpoint" constraints, in which the optimizer can deviate from the values defined by the user. Deviation from the values defined in the setpoint constraints adds and additional cost to the model. The setpoint constraints are only applicable for state and flow variables, not online variables. 

The time series data in the sheet *gen_constraint* has a special notation. As with other time series data, the first column *t* in the sheet *gen_constraint* contains the time steps for the constraint. The rest of the columns (2-n) contain information corresponding to specific constraints, defined in the sheet *constraint*. 

"rigid" general constraints contain factors, which add up to a constant. The notation for the first row of columns (2-n) depends on the type of variable the factor refers to. For process flow variables, **v_flow**, the notation is *constraint name, process, process flow, scenario*. For process online variables, **v_online**, the notation is *constraint name, process, scenario*. For storage state variables, **v_state**, the notation is *constraint name, node, scenario*. Each constraint can also have a constant value added, with the notation *constraint name, scenario* for the column. For "setpoint" constraints, only one column of factors can be defined, as per the previously mentioned notation. 

As an example of a normal general constraint, assume a CHP gas turbine *gt* with a input flow of natural gas *ng*, as well as outputs of electricity *elc* and heat in the form of exhaust gases *heat*. Assume, that the ratio of heat and power should be 3:1, meaning an electrical efficiency of 25%, and the remaining 75% being heat. To ensure this ratio, a general constraint named *gt_c1* is defined in the sheet *constraint*, with the operator set to *eq*. 

| name  | operator | is_setpoint | penalty |
|-------|----------|-------------|---------|
| gt_c1 | eq       | 0           | 0       |

In the sheet *gen_constraint*, the names of the columns referencing to the factors should be *gt_c1,gt,heat,s1* and *gt_c1,gt,elc,s1*. This refers to the constraint *gt_c1*, the process *gt*, and the process flows *heat* and *elc*. The name of the column referencing to the constant should be *gt_c1,s1*. As the sum of the factors equal the constant, the value of the factors should be *3* or *-3* for the factor representing the electricity flow, and *-1* or *1*, respectively, for the factor representing the heat flow. The value of the constant should be *0*. As the sum of the factors equal the constant, it would lead to *3 \* elc - 1 \* heat = 0* or alternatively *-3 \* elc + 1 \* heat = 0*.

| t  | gt_c1,gt,elc,s1 | gt_c1,gt,heat,s1 | gt_c1,s1|
|----|-----------------|------------------|---------|
| t1 | 3               | -1               | 0       |
| t2 | 3               | -1               | 0       | 
| tn | 3               | -1               | 0       |


As another example, assume that the operation of two online processes, **proc_1** and **proc_2**, should be limited in regard to eachother.  Assume, that the constraint *c_online* is used to limit the online variables **v_online** of these processes so, that the processes are not operating at the same time, but that one of the two is always active. The variable *v_online* is a binary variable with values of 0 or 1. The sum of the online variables of *proc_1* and *proc_2* should be set to 1, in order to one, but not two, of the processes to be active. As the general constraint is set equal to 0, the addiotional constant should be set to *-1*. This ensures, that **proc_1* + *proc_2* - 1 == 0*. 

| t  | c_online,proc_1,s1 | c_online,proc_1,s1 | c_online,s1|
|----|--------------------|--------------------|------------|
| t1 | 1                  | 1                  | -1         |
| t2 | 1                  | 1                  | -1         | 
| tn | 1                  | 1                  | -1         |

If both the processes should be either online or offline at the same time, the coefficients for one process should be *1*, and the other should be *-1*, weith the constant set to 0. This would result in the constraint **proc_1* - *proc_2* + 0 == 0*. 


As an example of a setpoint general constraint, assume the value of the electricity, **elc**, production of the process **gas_turb** has to be between 3 and 8. To do this, two setpoint constraints are defined, **c_up** and **c_dw**, for defining an upper and lower boundary for the process flow. As above, the constraints are defined in the *gen_constraint* sheet. The operator for *c_up* should be *st* (= smaller than), and the operator for *c_dw* should be *gt* (=greater than). Both constraints are defined as setpoint constraints, with a deviation penalty of 100. The unit of the penalty is simply per iunit of variable, meaning a variable deviation of 2 would increase the costs in the model with 200.

| name  | operator | is_setpoint | penalty |
|-------|----------|-------------|---------|
| c_up  | st       | 1           | 100     |
| c_dw  | gt       | 1           | 100     |


In the *constraint* sheet, the values for the upper and lower boundaries are defined. The constraints *c_up* is the upper boundary, and a value of 8 is given. For *c_dw*, a value of 3 is defined. With these constraints, the electricity production of *gas_turb* has to be between 3 and 8. Any deviation from this range will result in a penalty of 100 for each unit of production exceeding this range. 

| t  | c_up,gas_turb,elc,s1 | c_dw,gas_turb,elc,s1 |
|----|----------------------|----------------------|
| t1 | 8                    | 3                    |
| t2 | 8                    | 3                    |
| tn | 8                    | 3                    |


## References

<a id="1">[1]</a> 
Krokhmal, P., Uryasev, S., and Palmquist, J., “Portfolio optimization with conditional value-at-risk objective and constraints,” J. Risk, vol. 4, no. 2, pp. 43–68, 2001, doi: 10.21314/jor.2002.057.

<a id="2">[2]</a> 
Fleten, S. E. and Kristoffersen, T. K., “Stochastic programming for optimizing bidding strategies of a Nordic hydropower producer,” Eur. J. Oper. Res., vol. 181, no. 2, pp. 916–928, 2007, doi: 10.1016/j.ejor.2006.08.023.

## Funding

The development of Predicer has been partially funded in the EU Horizon [ELEXIA](https://www.elexia-project.eu/), Business Finland [HOPE](https://hopeproject.fi/) and Academy of Finland [EasyDR](https://cris.vtt.fi/en/projects/enabling-demand-response-through-easy-to-use-open-source-approach) projects.
- European Union [ELEXIA](https://www.elexia-project.eu/): Demonstration of a digitized energy system integration across sectors enhancing flexibility and resilience towards efficient, sustainable, cost-optimised, affordable, secure and stable energy supply
- Business Finland [HOPE](https://hopeproject.fi/): Highly Optimized Energy systems
- Academy of Finland [EasyDR](https://cris.vtt.fi/en/projects/enabling-demand-response-through-easy-to-use-open-source-approach): Enabling demand response through easy to use open source approach

&nbsp;
<hr>
<center>
<table width=500px frame="none">
<tr>
<td valign="middle" width=100px>
<img src=docs/images/eu-emblem-low-res.jpg alt="EU emblem" width=100%></td>
<td valign="middle">This work has been partially supported by the EU project ELEXIA (2022-2026), which has received funding from the European Climate, Energy and Mobility programme under the European Union's HORIZON research and Innovation actions under grant N°101075656.</td> 
</table>
</table>
</center>
