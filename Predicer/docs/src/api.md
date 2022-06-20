# API Reference
`AbstractModel.jl` API reference.

## `model.jl`
### Model
```@docs
Initialize
solve_model
export_model_contents
get_result_dataframe
write_bid_matrix
```

## `structures.jl`
### Structures
```@docs
Node
Process
TimeSeries
State
Market
Topology
ConFactor
GenConstraint
```

## `constraints.jl`
### Constraints
```@docs
create_constraints
setup_node_balance
setup_process_online_balance
setup_process_balance
setup_processes_limits
setup_reserve_balances
setup_ramp_constraints
setup_fixed_values
setup_bidding_constraints
setup_generic_constraints
setup_cost_calculations
setup_objective_function
```

## `variables.jl`
### Variables
```@docs
create_variables
create_v_flow
create_v_online
create_v_reserve
create_v_state
create_v_flow_op
```

## `tuples.jl`
### Tuples
Indexing of constraints, expressions and variables in this model is done using tuples. The tuples contain strings, such as ("dh", "s1", "t1"). 

n = node

p = process

s = scenario

t = timestep

so = process source

si = process sink

res = reserve market

rd = reserve direction (up, down, or up/down)

rt = reserve type

```@docs
create_tuples
create_res_nodes_tuple
create_res_tuple
create_process_tuple
create_res_potential_tuple
create_proc_online_tuple
create_res_pot_prod_tuple
create_res_pot_cons_tuple
create_node_state_tuple
create_node_balance_tuple
create_proc_potential_tuple
create_proc_balance_tuple
create_proc_op_balance_tuple
create_proc_op_tuple
create_cf_balance_tuple
create_lim_tuple
create_trans_tuple
create_res_eq_tuple
create_res_eq_updn_tuple
create_res_final_tuple
create_fixed_value_tuple
create_ramp_tuple
```



