# Example models in detail

## Introduction

This section contains a more detailed description of example models found in Predicer. The idea behind the example models is not to provide a detailed and correct ready-to-use model, but rather to explain concepts and ideas found in Predicer, and how it is implemented in the input data files. These concepts and ideas can then be used to build more complex models replicating real systems. It is recommended that this section is read while having the respective example model input data file for reference.

Every aspect of every model is not discussed in detail, if concepts and ideas are described in previous models.

## Simple building model

The input data file for the model can be found under *"/Predicer/input_data/simple_building_model.xlsx"*. The simple building model is a model of a simplified building with direct electric heating with spot-based electricity pricing. The energy balance of the modelled building consists of three major elements; heat loss from inside the building to the ambient air, and an electric heater to maintain the temperature of the inside air within a comfortable range. In addition an electric powered domestic hot water (DHW) tank is modelled as a storage, with the use of DHW being represented by a timeseries. The aim of the model is to minimize the electricity costs for the electric heater and the DHW heater by using the storage capacities of the building and the DHW tank to time the use of electricity to the cheapest hours. This should be done while maintaining the temperature of the building at a comfortable level and ensuring that the hot water tank doesn't empty at any point during the day.

A real building could of course be modelled more accurately, adding concepts such as heat losses through ventilation, overall electricity use, effect of solar radiation, dividing the building into smaller nodes, etc. 

The model horizon for the simple building model is 9.0 hours with the timesteps being 15 minutes, for a total of 36 timesteps. There are three scenarios in the model (*s1*, *s2* and *s3*), and all of the data used in the model is randomly generated. 

### Nodes and processes
The model consists of five nodes: *interiorair* representing the air (and structures) inside the building, *buildingenvelope* representing the building components separating the inside from the outside, *outsideair* representing the ambient air, *dhw* representing the domestic hot water tank, and *elc* representing the local electricity grid the building is connected to. *npe* represents the electricity market from where electricity can be bought for a hourly varying price.

There are two processes in the model: *electricheater* for converting electricity from the *elc* node to heat in the *interiorair* node, and *dhw_heater* converting electricity from the *elc* node to heat in the *dhw* node. Below is a simple schematic of the topology of the simple building model. 

```mermaid
flowchart RL
buildingenvelope((buildingenvelope))
npe((npe))
outside((outside))
electricitygrid((electricitygrid))
interiorair((interiorair))
dhw((dhw))
dhw_heater[dhw_heater]
electricheater[electricheater]
electricitygrid_npe_trade_process[electricitygrid_npe_trade_process]
electricitygrid --> electricheater
electricheater --> interiorair
electricitygrid --> dhw_heater
dhw_heater --> dhw
electricitygrid --> electricitygrid_npe_trade_process
electricitygrid_npe_trade_process --> npe
npe --> electricitygrid_npe_trade_process
electricitygrid_npe_trade_process --> electricitygrid
interiorair -.-> buildingenvelope
buildingenvelope -.-> outside
```

### Modelling building heat loss

The building heat loss is modelled as transfer of heat through the *buildingenvelope*, driven by the temperature difference between the *interiorair* and the *outsideair* nodes. The heat loss to the ambient air is modelled using the diffusion functionality found in Predicer. A diffusion flow can be defined between two nodes with states, with the states generally being modelled as temperature instead of energy.  The size of the flow between two nodes in a diffusion relation is simply the difference between the states multiplied with a user-defined coefficient ***c***. 

***P<sub>loss</sub> = c * (state<sub>1</sub> - state<sub>2</sub>)***

The unit of the heat transfer coefficient ***c*** in this model case would be *kW/K*. The value of the diffusion coefficient is chosen to be 0.25 *(kW/K)* between the *interiorair* and *buildingenvelope* nodes and 0.2 *(kW/K)* between the *buildingenvelope* and *outside* nodes. The diffusion coefficient is provided as a timeseries, and can vary between the timesteps even if in this example it is constant. One use case for a timeseries-dependent diffusion could be a wind forecast, with higher wind speeds resulting in a higher heat loss.

In the example Excel file, this is done on the *node_diffusion* sheet, where data is defined for each scenario and timestep for both diffusion relations. 

| t	                  | interiorair,buildingenvelope,s1 | buildingenvelope,outside,s1 |
|---------------------|---------------------------------|---------------------------------|
| 2022-01-05T08:00:00 | 0.25                            | 0.2                             |
| 2022-01-05T08:15:00 | 0.25                            | 0.2                             |

To be able to model heat loss, the *buildingenvelope*, *interiorair* and *outside* nodes are given states which represent the temperature in the respective nodes. This is done by setting the *is_state* and *is_temp* flags to **True**. 

Most of the flows in Predicer, such as process flows, diffusion flows, etc. are modelled as *energy*, not *temperature*. The conversion between energy and temperature for a state is defined in the *T_E_conversion* parameter. This parameter indicates how much energy is required to increase the temperature of the state by one (the unit depends on the model, in this case one Kelvin *K*). In the simple building model the energy is in the form of *kW/kWh*, and temperature in the form of *K*. The conversion rate is set to 0.5 *(kWh/K)* for the *interiorair* node and 1.0 *(kWh/K)* for the *buildingenvelope* node. If the heat losses were zero, this would mean that operating the electric heater at 1 kW for one hour would increase the temperature of the *interiorair* node by 2 K, which essentially would mean increasing the value of the storage (state) by 2. As the heat losses from the building are not expected to increase the temperature of the ambient air, the *T_E_conversion* parameter is set to 1 000 000 000 for the *outside* node. In the simple building model this means, that a cumulative heat flow of 10<sup>9</sup> kWh into the ambient air node is required to increase its storage state by 1 (*K*).

The initial states of the *interiorair*, *buildingenvelope* and *outside* nodes are set to 292.15 K,
282.0 K and 269.5 K, respectively. The modelled system is approximately in balance on the first timestep when these values are used. 


As the heat loss in this model depends on the temperature difference between the building and the ambient air, it is important to be able to define the ambient air temperature properly. This can be done by setting the *is_inflow* flag of the *outside* node to **True**. This allows the hourly temperature changes of the ambient air to be given as an inflow timeseries to the node. So if the initial ambient temperature would be 263K, and the temperature for three first time steps would be 273K, 268K and 260K, the inflow timeseries to the ambient air node (*outside*) would be [+10, -5, -8] for the first three timesteps.

As one of the objectives of this example model is to maintain a comfortable temperature inside the building, the boundaries of the comfortable temperature range must be defined. This can either be done using hard or soft boundaries. If hard boundaries are used, the temperature of the *interiorair* node is not allowed to go below or above the boundaries. This can be achieved either by setting the node parameters *state_min* and *state_max* to the desired temperature range, or by making user-defined gen_constraints with the *is_setpoint* flag set to false. 

Soft boundaries for the temperature range can be defined by making user-defined gen_constraints with the *is_setpoint* flag set to true. When a suitable cost (*penalty* parameter in the "constraints" sheet in the input data excel file) is set, the model can deviate from the given temperatue range, but this induces a cost for the model and is thus usually avoided. It is also possible to combine several layers of soft boundaries, with the cost of deviation increasing for each passed layer, and hard boundaries with soft boundaries, as long as the hard boundaries are less "strict" than the soft boundaries (e.g. hard boundary lower/upper limits of 15°C/27°C and soft boundery lower/upper limits of 19°C/24°C).

| name               | operator | is_setpoint | penalty |
|--------------------|----------|-------------|---------|
| c_interiorair_up   | st       | 1           | 15      |
| c_interiorair_down | gt       | 1           | 15      |

One set of soft boundaries are used in the example model, defined using the "c_interiorair_up" as upper limit and "c_interiorair_down" as lower limit gen_constraints. The operator for the constraints are "st" (smaller than) and "gt" (greater than), meaning that the value of the limited variable should be smaller than and greater than, respectively, than the value of the constraints. The parameter *is_setpoint* is set to true as this is a setpoint constraint, with the *penalty* parameter being set to 15 *(€/K/h)*. The penalty is not a real cost, but rather a steering cost for getting the model to behave in an intended manner. The other part of the constraints are defined in the "gen_constraint" sheet in the input data excel. The limiting value for *c_interiorair_up* is set to 298.15K (25°C), and the limit for *c_interiorair_down* is 292.15K (19°C). 

| t                   | c_interiorair_up,interiorair,s1 | c_interiorair_down,interiorair,s1 |
|---------------------|---------------------------------|-----------------------------------|
| 2022-01-05T08:00:00 | 298,15                          | 292,15                            |
| 2022-01-05T08:15:00 | 298,15                          | 292,15                            |
| ...                 | ...                             | ...                               |

The *state_min* and *state_max* parameters for the *interiorair*, *buildingenvelope* and *outside* nodes are set to values that are outside the the system is expected to reach. As the inside temperature range is between 292K-298K, a suitable range for the *interiorair* state is 273K to 308K. For the *outside* and *buildingenvelope* nodes a minimum and maximum values for the states are chosen to be 238K and 308K. 

### Modelling the domestic hot water system

The idea behind modelling the DHW system is to use the DHW tank as a storage, to time the use of electricity to prepare the hot water to the time when the price of electricity is the lowest. This has to be done, while ensuring that the DHW never runs out. The storage is allowed to be empty momentarily, as long as there is enough to cover the demand at all times. 

The DHW system is modelled using a node *dhw* with a state (storage) and inflow (hot water use timeseries). The unit in *dhw* is thought to be *kWh*, to make it easier to model in this case. This means that the "water" in the DHW tank is represented by the amount of energy it would require to heat it from cold water, and the limits of the storage, as well as the inflow (use) of DHW uses this same unit. The storage losses of the DHW tank are not accounted for, as it is assumed that the heat is dissipated into the building, thus reducing the need to operate the electric space heater. The *state_loss-proportional* parameter is thus set to 0. 

The inflow data for the DHW system is randomly generated, with a small baseload and one or more larger spikes, representing 5-15 minute showers. The DHW demand can either be covered directly using the *dhw* heater, or by taking water from the hot water tank. The DHW demand is between 15 - 22 kWh over the modelled 9 hours, with the largest peak being 9.17 kWh over an timestep. This means that the *dhw_heater* (3 kW) is not enough to cover the demand at all timesteps. 

As Predicer doesn't consider what happens before or after the modelled time horizon, it is likely that the DHW tank would be empty after the last timestep, since any water left in the tank would be "wasted" from the perspective of the model. To amend this, a value for the water remaining in the tank can be defined. This value estimate is set to be the average hourly electricity price of the simple building model. This parameter is defined using the *state_residual_value* field in the input_data file on the *nodes* sheet.

## Simple district heating system model

The input data file for the model can be found under *"/Predicer/input_data/simple_dh_model.xlsx"*. The simple district heating model is a model of a simple district heating system, operated by a single actor. The idea behind the system is to minimize the costs (or maximize the profits) while covering an hourly heat demand, and operating on an electricity spot market. The heat demand is defined as a time series, and the system has to cover the demand at all times. Several different heat generation units in combination with a heat day storage provides flexibility, which can be utilized to minimize the costs of covering the demand. The price of the provided heat is not defined (also 0), as is usual for local DH system modelling. The costs of the modelled system thus consist of fuel and operational costs for generating the required heat, and profits come from electricity sold to the spot market.

The model only considers heat balances on a system production level, and building-specific balances are not considered. DH pressures, temperatures, losses, etc. are also not considered in the model. The modelled system is fictional, and the data used in the model is either fictional and/or randomly generated.

### Nodes and processes

The modelled system consists of five nodes: *ng* representing a natural gas grid from where natural gas can be bought for a fixed price, *elc* representing a local electricity grid, *heat* representing a district heating grid, *hp_source* representing a natural heat source, such as seawater, and *npe* representing an electricity spot market where electticity can be bopught and sold for an hourly price. Additionally the node *heat_storage* represents a thermal energy storage connected to the district heating system. 

There are several process for generating heat in the system; *elc_boiler* converting electricity directly to heat, *heat_pump_1* converting electricity and low-temperature heat from the *hp_source* node to heat in the *heat* node with a variable capacity, *heat_pump_2* converting electricity to heat in the *heat* node with a variable efficiency, *solar_collector* producing heat based on a capacity factor time series, and *ngchp* representing a combined heat and power plant converting natural gas from the *ng* node to electricity and heat at a fixed ratio. Additionally, there is a process *heat_sto_charge* for transferring heat from the *heat* node to the *heat_storage* and *heat_sto_discharge* for transferring heat from the *heat_storage* to the *heat* node. The process *elc_npe_trade_process* is used to buy and sell electricity from the electricity spot market *npe*. 

Below is a simple flowchart of the modelled system, showing the connections between the nodes and processes in the modelled system. 

```mermaid
flowchart TD
npe((npe))
heat((heat))
ng((ng))
hp_source((hp_source))
heat_storage((heat_storage))
elc((elc))
elc_boiler[elc_boiler]
solar_collector[solar_collector]
elc_npe_trade_process[elc_npe_trade_process]
ngchp[ngchp]
heat_sto_charge[heat_sto_charge]
heat_pump_1[heat_pump_1]
heat_pump_2[heat_pump_2]
heat_sto_discharge[heat_sto_discharge]
ng --> ngchp
ngchp --> elc
ngchp --> heat
hp_source --> heat_pump_1
elc --> heat_pump_1
heat_pump_1 --> heat
elc --> heat_pump_2
heat_pump_2 --> heat
heat --> heat_sto_charge
heat_sto_charge --> heat_storage
heat_storage --> heat_sto_discharge
heat_sto_discharge --> heat
elc --> elc_boiler
elc_boiler --> heat
solar_collector --> heat
elc --> elc_npe_trade_process
elc_npe_trade_process --> npe
npe --> elc_npe_trade_process
elc_npe_trade_process --> elc
```

In the model there are various costs linked to power and heat generation which should be taken into consideration. These costs include fuel costs (natural gas, electricity), electricity transmission costs, carbon emission permits, as well as emission taxes for carbon and electricity. The fuel cost of natural gas is defined as a timeseries on the *price* sheet in the input data, with a value of 25.0 (*€/MWh*) for every hour. The cost of electricity, both when buying and selling is defined as a timeseries in the *market_prices* sheet in the input data. The prices are randomly generated, and vary between 2.13-85.38 (*€/MWh*), with an average price of 42.92 (*€/MWh*). 

The sum of the carbon emission permits and carbon tax amount to 22.0 (*€*) per MWh of natural gas used. As these costs depend on the use of natural gas from the *ng* node, the VOM (variable operation and maintenance) cost of the natural gas flow for the *ngchp* process in the *process_topologies* sheet is set to 22.0. This causes a cost of 22.0 for each unit (*MWh*) of *ng* that is used by the *ngchp* process. In this example model case these costs could also have been directly added to the price of natural gas, as the *ngchp* process is the sole consumer of natural gas. Another way to implement carbon permits or taxes (*€/ton*) would be to add a "emissions" flow to relevant processes and to add the costs to the VOM of this flow. To ensure this works properly, a *gen_constraint* has to be created to fix the size of the emission flow proportional to the size of the natural gas flow into the process. Additionally, the efficiency of the process has to be adjusted to include the emissions. A third way would be to create a commodity node *carbon_permits_and_taxes*, from where there would be a flow to a process using natural gas. In this case a *gen_constraint* fixing the ratio between natural gas and "emissions" would be needed as well. The emission costs can be set as the price of the commodity node. 

The sum of electricity tax and distribution costs is assumed to be 15.0 (*€/MWh*), and is added to each topology where electricity is consumed, except when buying from the market node. In this model this means the *elc* flows of the heat pumps and the *elc* flow of the *elc_boiler*. A summary of the relevant production costs for processes and flows is visualized in the table below. 

| Process flow                     | Fuel costs   | Taxes + Carbon permits |
|----------------------------------|--------------|------------------------|
| ngchp, ng                        | 25.0         | 22.0                   |
| ngchp, elc                       | 0.0          | 0.0                    |
| ngchp, heat                      | 0.0          | 0.0                    |
| heat_pump_1, elc                 | 2.13 - 85.38 | 15.0                   |
| heat_pump_1, hp_source           | 0.0          | 0.0                    |
| heat_pump_1, heat                | 0.0          | 0.0                    |
| heat_pump_2, elc                 | 2.13 - 85.38 | 15.0                   |
| heat_pump_2, heat                | 0.0          | 0.0                    |
| heat_sto_charge, heat            | 0.0          | 0.0                    |
| heat_sto_charge, heat_storage    | 0.0          | 0.0                    |
| heat_sto_discharge, heat_storage | 0.0          | 0.0                    |
| heat_sto_discharge, heat         | 0.0          | 0.0                    |
| solar_collector, heat            | 0.0          | 0.0                    |
| elc_boiler, elc                  | 2.13 - 85.38 | 15.0                   |
| elc_boiler, heat                 | 0.0          | 0.0                    |

### Scenario and market definition

Scenarios in Predicer are user-defined possible futures the system and environment around the system can take, with different values for forecasted values, such as prices, weather, supply and demand, etc., but different scenarios can have identical values in one or several timesteps as well. These scenarios are separate from each other, with for example the weather forecast (solar/wind production, heat demand, etc.) ideally correlating with market price forecasts within the same scenario. In this model there are three scenarios: *s1*, *s2* and *s3*. The scenarios are defined on the *scenarios* sheet in the input data file. The probability of these scenarios is 0.3, 0.4 and 0.3, respectively, and is used for weighting the scenario properly in the optimization. 

| scenario | probability |
|----------|-------------|
| s1       | 0.3         |
| s2       | 0.4         |
| s3       | 0.3         |

This example model has one defined market, *npe* which represents an electricity spot market where electricity can be bought and sold for prices and volumes that are determined the day before. Running Predicer produces a bidding curve for each defined market. This bidding curve consists of a group of price-volume pairs, and essentially indicates how much should be bought or sold from a market, if the price were x. The market prices for different scenarios for each timestep is used as a basis for the bidding curves. This means, that the price points for a specific hour on the bidding curve are defined using the market prices in the different scenarios. As a result, the number of price points on the bidding curves depends on the number of scenarios, and if the scenarios have unique values or not.

The market *npe* is defined on the *markets* sheet in the input data file. The *type* parameter is defined to "energy" (as oppposed to "reserve" for reserve markets), and the linked node is *elc*. The parameters *processgroup*, *direction*, *realisation* and *reserve_type* are only used for reserve markets, and have been given filler values in this example. The market *npe* has a bidding functionality, but is not limited. The parameter *is_bid* is thus set to true, while the parameters *is_limited*, *min_bid* and *max_bid* are set to zero. There is no fee for bidding, so *fee* is also set to zero. 


| market | type   | node | processgroup | direction | realisation | reserve_type | is_bid | is_limited | min_bid | max_bid | fee |
|--------|--------|------|--------------|-----------|-------------|--------------|--------|------------|---------|---------|-----|
| npe    | energy | elc  | p1           | none      | 0           | none         | 1      | 0          | 0       | 0       | 0   |

The price forecasts for the markets in the model are defined on the *market_prices* sheet in the input data file. These are in the form of timeseries, defined for every scenario, for every market. A part of the *market_prices* table is visualized below. When an energy market is defined, the balance markets *npe_up* and *npe_down* are automatically created. The model can buy (*up*) or sell (*down*) from these markets to adjust the system energy balance if needed. 

| t              | npe,s1 | npe,s2 | npe,s3 |
|----------------|--------|--------|--------|
| 16.4.2024 0:00 | 16,43  | 24,25  | 17,77  |
| 16.4.2024 1:00 | 7,65   | 22,58  | 19,13  |
| 16.4.2024 2:00 | 2,13   | 24,53  | 20,42  |
| ...            | ...    | ...    | ...    |

The prices for the balance markets are defined in the *balance_prices* sheet in the input data file. As the user-defined market *npe* and the balance markets *npe_up* and *npe_down* are connected to the same node (*elc*), the model can buy from one market and sell to the other. This causes the model to be unbounded unless buying from one market and selling to another is disadvantageous. In this example this is done by setting the price of *npe_up* to 0.01 more than the price for *npe, and *npe_down* to 0.01 less than the corresponding price given for *npe*. Parts of the table defined in the *balance_prices* sheet is visualized below. 

| t              | npe,up,s1 | npe,up,s2 | npe,up,s3 | npe,dw,s1 | npe,dw,s2 | npe,dw,s3 |
|----------------|-----------|-----------|-----------|-----------|-----------|-----------|
| 16.4.2024 0:00 | 16,44     | 24,26     | 17,78     | 16,42     | 24,24     | 17,76     |
| 16.4.2024 1:00 | 7,66      | 22,59     | 19,14     | 7,64      | 22,57     | 19,12     |
| 16.4.2024 2:00 | 2,14      | 24,54     | 20,43     | 2,12      | 24,52     | 20,41     |
| ...            | ...       | ...       | ...       | ...       | ...       | ...       |

### Modelling the CHP unit

The combined heat and power process *ngchp* converts natural gas from the *ng* node to electricity to the *elc* node and heat to the *heat* node. In reality a natural gas-based CHP plant would consist of a steam boiler, steam turbine, turbine bypass, etc. In this case the whole plant is modelled as a single process with fuel in to the process and electricity and heat out of the process. The heat rate of the process is set to be constant at all loads, with the amount of generated heat being 3 times the amount of generated electricity. The process *ngchp* is modelled with the *ng* flow in and with the *elc* and *heat* flows out. So called user constraints, or in Predicer terms *gen_constraints*, are used to define the heat rate. Without user constraints Predicer would be able to adjust the electric and heat flows freely, as long as efficiency, online and capacity boundaries are fulfilled. 

The user constraints are defined in the *constraint* and *gen_constraint* sheets in the input data file. The name, type and operator of the constraint is defined on the *constraint* sheet. The user constraint *ngchp_c1* has the operator *eq*, meaning "equal", and it is not a setpoint constraint. How the constraint *ngchp_c1* is defined on the *constraint* sheet is shown in the table below. 

| name     | operator | is_setpoint | penalty |
|----------|----------|-------------|---------|
| ngchp_c1 | eq       | 0           | 0       |

User constraints consist of a sum of variables multiplied with coefficients, being set equal to a constant. The names, types and coefficients of the variables limited by the user constraints are defined on on the *gen_constraint* sheet. In this example case the heat flow variable should be set to be three times larger than the electricity flow variable, which can be written as:

*v_flow[heat] = 3 * v_flow[elc]*

Which can be written as

*v_flow[heat] - 3 * v_flow[elc] = 0*

The coefficients for the heat and electricity flow variables should thus be 1 and -2, respecitvely, and the constant should be zero. Below is a part of the *gen_constraints* sheet table, where the variables, coefficients and constant are defined. The types of the variables depends on the column names, and in the case of flow variables is of the form *constraint_name,process,flow,scenario*. As such the column names are *"ngchp_c1,ngchp,elc,s1"* and *"ngchp_c1,ngchp,heat,s1"*. Additionally, the constant value of the constraint is required, and is defined with a column namenotation of *constraint_name,scenario*. As the heat rate is constant, and same in all scenarios, the values must be defined for every timestep in all scenarios. 

| t              | ngchp_c1,ngchp,elc,s1 | ngchp_c1,ngchp,heat,s1 | ngchp_c1,s1 |
|----------------|-----------------------|------------------------|-------------|
| 16.4.2024 0:00 | -2                    | 1                      | 0           |
| 16.4.2024 1:00 | -2                    | 1                      | 0           |
| ...            | ...                   | ...                    | ...         |



In this model the heat rate is set to a constant value, but it would be possible to have a varying heat rate. This could be done by making two user constraints, one defining the lower bound of the electricity-heat ratio, and one defining the upper bound of the ratio. Assuming the heat output should be between 2.5 and 3.5 times the electrical output, the constraint could be formulated as: 

*v_flow[heat] >= 1.5 * v_flow[elc]*

*v_flow[heat] <= 2.5 * v_flow[elc]*

Which can be written as

*v_flow[heat] - 1.5 * v_flow[elc] >= 0*

*v_flow[heat] - 2.5 * v_flow[elc] <= 0*

### Modelling the heat pumps

There are two heat pump processes, *heat_pump_1* and *heat_pump_2*, in this example model. Both of these processes convert electricity from the *elc* node to heat in the *heat* node. Additionally *heat_pump_1* is connected to the commodity node *hp_source*, from where lower-grade heat can be obtained from free, but at a limited availability. The coefficient of power (COP) of a heat pump depends on many factors, one of which is the temperature of the used heat source. As the temperature (and thus COP) and availability of some natural heat sources typically fluctuate between seasons or even days, the operational limits of heat pump can be defined using timeseries. In this example there are two heat pumps with similar parameters (capacity, cost, etc). The operation of the heat pumps is affected by the price of electricity, the efficiency, and the amount of heat available from the node *hp_source*. The heat production of *heat_pump_1* is limited by the availability of heat from the *hp_source* node, while the production for the process *heat_pump_2* depends on a timeseries-dependent efficiency.

The amount of heat from the *hp_source* available to the *heat_pump_1* process is limited with a timeseries, setting an upper limit for the flow between the *hp_source* node and the *heat_pump_1* process. This timeseries is defined on the *cap_ts* sheet in the example input data. Below is a part of the table found in the *cap_ts* sheet in the input data file. It is assumed, that the efficiency of *heat_pump_1* is constant at 2.0, meaning 1/2 of the generated heat comes from the electricity, and 1/2 comes from the heat source. A value of 1,57 (MW) for available heat would mean, that the amount of electricity is equal (1.57 MW) and the total heat output would be 3.14 MW. 

| t              | heat_pump,hp_source,s1 | heat_pump,hp_source,s2 | heat_pump,hp_source,s3 |
|----------------|------------------------|------------------------|------------------------|
| 16.4.2024 0:00 | 1,57                   | 2,35                   | 2,50                   |
| 16.4.2024 1:00 | 1,62                   | 2,45                   | 2,55                   |
| 16.4.2024 2:00 | 1,62                   | 2,55                   | 2,45                   |
| ...            | ...                    | ...                    | ...                    |

Like the *ngchp* process, the ratio of the incoming flows should be fixed. This ratio is fixed using the user constraints, like the *ngchp* process. The coefficients for the variables should be -1.0 and 1.0, with the constant being 0.0. 

| t |            | hp1_c1,heat_pump_1,elc,s1 | hp1_c1,heat_pump_1,hp_source,s1 | hp1_c1,s1 |
|-|--------------|---------------------------|---------------------------------|-----------|
| 16.4.2024 0:00 | -1                        | 1                               | 0         |
| 16.4.2024 1:00 | -1                        | 1                               | 0         |
| 16.4.2024 2:00 | -1                        | 1                               | 0         |
| ...            | ...                       | ...                             | ...       |

The efficiency timeseries for the *heat_pump_2* process is defined on the *eff_ts* sheet in the input data. The given timeseries limits the total efficiency of the process for every timestep, meaning *flows_in* * *eff* = *flows_out*. The heatpump has one flow in (*elc*) and one flow out (*heat*). Below is a part of the defined data in the *eff_ts* sheet in the input data file. An efficiency of 1.95 would in the case of the *heat_pump_2* process mean that the amount of heat provided to the *heat* node at time ***t*** is 1.95 times the electric power of the heat pump at time ***t***, meaning 1.0 MW of electricity and 0.95 MW of heat (not modelled for *heat_pump_2*) would be required for a heat output of 1.95 MW. Because there is only one flow in and one flow out, there is no need to create gen_constraints for *heat_pump_2*.

| t              | heat_pump_2,s1 | heat_pump_2,s2 | heat_pump_2,s3 |
|----------------|----------------|----------------|----------------|
| 16.4.2024 0:00 | 1,95           | 2,1            | 1,75           |
| 16.4.2024 1:00 | 1,83           | 2,04           | 1,64           |
| 16.4.2024 2:00 | 1,93           | 2,14           | 1,57           |
| ...            | ...            | ...            | ...            |

### Modelling the solar collector

The solar collector process *solar_collector* in this model is modelled as a *capacity factor* (*cf*) process. In contrast to other process types, *cf* processes do not have a source node going into the process. Instead, the process is modelled using a capacity factor timeseries. This means that the process has a maximum output, and a hourly *capacity factor* (***cf***) timeseries defining what percentage of this output can be used. This *cf* timeseries is defined on the *cg* sheet in the input data file.

| t              | solar_collector,s1 | solar_collector,s2 | solar_collector,s3 |
|----------------|--------------------|--------------------|--------------------|
| 16.4.2024 0:00 | 1                  | 0,63               | 0,02               |
| 16.4.2024 1:00 | 0,96               | 0,56               | 0,0                |
| 16.4.2024 2:00 | 0,97               | 0,55               | 0,09               |
| ...            | ...                | ...                | ...                |

The maximum capacity of the solar collector is set to 3.0 (*MW*). The *is_fixed* flag in the *processes* sheet is set to false, meaning that the *cf* timeseries sets an upper limit for the production of the *cf* process. If *is_fixed* would be set to true, then the output of the process would be fixed by the capacity factor timeseries. 

In this example this means, that if the value capacity factor timeseries value for a certain hour would be 1, then the output of the *solar_collector* process would be between 0.0 (*MW*) and 3.0 (*MW*). If the *cf* value would be 0.3, the output would be 0-0.9 (*MW*). 

### Modelling the heat storage

The simple district heating model contains a daily heat storage, which can be used to balance the system and offer flexibility between hours. The storage is defined in the node *heat_storage*, and it is connected to the *heat* node via the processes *heat_sto_charge* and *heat_sto_discharge*. The capacity of the storage is set to 10.0 (*MWh*), with the maximum flows in and out of the storage each being 3.0 (*MW*). As the system heat demand varies between 7-15 (*MW*), the storage alone cannot be used to generate heat into the system. The storage losses are 0.001 of the storage value per hour, and the starting value of the storage is set to 0.0. 

Optimization models commonly empty storages by the end of the model horizon, as any storage content is "wasted" from the model perspective. To prevent this, a value for heat remaining in the storage at the end of the model horizon is defined. The chosen value should represent the expected costs of heat production in the "next" horizon.

## Two stage model

The two stage dh model is an extension of the simple district heating model described above. The model is defined in the "two_stage_dh_model.xlsx" input data file. The extension consists of a simple two stage modelling implementation, with a first stage where the price of the market *npe* and all other timeseries parameters are known and identical for all scenarios (*s1*, *s2*, *s3*). After the common start, the scenarios branch out into separate forecasts in the second stage. The lengths of the first and second stages are 12 timesteps (12 hours) each. The two stage approach is defined in the *setup* sheet, with setting the *common_timesteps* parameter to 12, and the *common_scenario_name* parameter to "ALL". This leads to all variable indices to have the scenario name *ALL* for the first 12 timesteps, instead of the standard scenario names. 

All of the scenario-dependent timeseries parameters are set to be identical between the scenarios for each timestep for the first 12 timesteps. In this case this means the *inflow*, *cf*, *(price)*, *market_prices*, *balance_prices*, *eff_ts*, *cap_ts*, and *constraint* timeseries. After the model has been optimized, the values for the variables for the first 12 timesteps are the same in all scenarios, after which they start to branch out. 

## Simple hydropower river system

The input data file for the example model can be found under "simple_hydropower_river_system.xlsx". This example model consists of a hydropower river system with five hydropower plants connected by a river. Each hydropower plant contains a reservoir, where water can be stored for optimal use timing. Each reservoir has a inflow of water from smaller rivers or rainfall Each hydropower plant also contains a turbine by-pass, which can be used to release water from the reservoir to the river without producing electricity. The model contains a delay between the hydropower plant, meaning it takes a while for the released water to reach the next plant. 

The goal of the model is to maimize the profits on the linked electricity markets by optimizing the use of the water in the reservoirs as well as possible. The system is constrained by minimum and maximum flow requirements for the river, as well as minimum and maximum water levels in the reservoirs. The model contains three scenarios *"dry"*, *"normal"* and *"wet"*, with differing electricity market prices and inflow to the reservoirs. The scenario *"dry"* contains a lower inflow into the reservoirs and resulting higher electricity prices. The scenario *"wet"* containts a higher inflow into the reservoirs and lower electricity prices, while the scenario *"medium"* lies somewhere in between *"dry"* and *"wet"*in regards to inflow and electricity prices. 

The depicted system is fictional, and all timeseries data (inflows, market prices, etc.) is randomly generated, with some modifications. The time horizon for the model is 30 days, with the first two days being modelled in higher resolution with one hour timesteps, the following two days modelled with 4 hour timesteps, and the rest being modelled with one day timesteps. 

### Nodes and processes

There are five hydropower plants (processes) in the model *hydro1*, *hydro2*, *hydro3*, *hydro4* and *hydro5*, representing hydropower turbines. All of these processes have a linked node; *res1*, *res2*, *res3*, *res4* and *res5*, respectively. Each plant also has a linked spill process *hydro1_spill*, *hydro2_spill*, *hydro3_spill*, *hydro4_spill*, and *hydro5_spill*, which can be used to release water from the linked reservoir without producing electricity. A simple schematic of the river system can be seen in the figure below. The reservoirs linked to the processes *hydro1* and *hydro2* do not have an "upstream" connection, and the processes both connect with the reservoir linked with *hydro3*. The process *hydro3* is upstream of  *hydro4*, which is upstream of *hydro5*. The process *hydro5* doesn't have a downstream node, and it could be thought that this is where the river system flows out to the sea. The modellled system also has an electricity node *elc*, which is linked to electricity energy and reserve markets. Each of the hydropower plants has a connection to the *elc* node. 

```mermaid
flowchart TD


```

The reservoir nodes (both inflows and flows) are modelled as water (*m<sup>3</sup>*). As the flows are large, the unit of one water is assumed to be 1000 m<sup>3</sup> instead of 1 m<sup>3</sup>. This reduces scaling issues in the model as well. The amount of energy available in the water can be calculated using the potential energy of the water, and assuming some losses in the conversion process. The process electrical generation ber unit of water (1000 m<sup>3</sup>), the corresponding process (electrical) efficiency p, as well as reservoir and flow limitations are shown in the table below. All the water-related numbers are per 1000 m<sup>3</sup>.

| Process | Elc per water | Efficiency | Reservoir max | Reservoir min| Min flow | Max flow |
|---------|---------------|------------|---------------|--------------|----------|----------|
| hydro1  | 0.0818 MWh    | 0.073      | 2000          | 800          | 40       | 300      |
| hydro2  | 0.1227 MWh    | 0.110      | 2000          | 800          | 40       | 300      |
| hydro3  | 0.1092 MWh    | 0.098      | 2000          | 800          | 40       | 300      |
| hydro4  | 0.0956 MWh    | 0.086      | 2000          | 800          | 40       | 300      |
| hydro5  | 0.0437 MWh    | 0.039      | 2000          | 800          | 40       | 300      |




- river inflow
- delays
- reservoirs, spill, etc


## Large convenience store

 - Heat pumps
 - Solar panels
 - Cold shelves as storage, building as storage
 - Either DH or local heat source (GSHP?)
 - Solar panels/collectors

## Simple hydropower river system

- Delay between plants?
- Variable time control?

## Electric storage producing reserve

- Solar cells + storage acting on spot + some reserve market. 

## Rolling model

- Rolling model for one year. 




