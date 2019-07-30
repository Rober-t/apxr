# APXR

A platform for the testing and optimisation of trading algorithms.

--------------------
### Related publications

High frequency trading strategies, market fragility and price spikes: an agent based model perspective.
McGroarty, F., Booth, A., Gerding, E. et al. Ann Oper Res (2018). https://doi.org/10.1007/s10479-018-3019-4

Note: This paper fails to provide several parameters, namely: the composition of the Agents, the wealth parameter W in the Momentum trader logic, the volume parameter V minus in the MarketMaker trader logic and the number of standard deviations K in the MeanReversion trader logic.

--------------------
### Table of Contents

* [Requirements](#requirements)
* [Installation](#installation)
* [Quick start](#quick-start)
* [Introduction](#introduction)
* [Architecture](#architecture)
* [Configuration](#configuration)
* [Outputs](#outputs)
* [Validation](#validation)
* [Future work](#future-work)
* [Debugging](#debugging)

--------------------
### Requirements

  - [Erlang](https://github.com/erlang)
  - [Elixir](https://elixir-lang.org/)
  - [Python](https://www.python.org/downloads/)

--------------------
### Installation

The following guide provides instructions on how to install both Erlang and
Elixir: https://elixir-lang.org/install.html

Windows: https://github.com/elixir-lang/elixir/wiki/Windows

1. Run `git clone ....` to clone the APXR GitHub repository
2. Run `cd apxr` to navigate into the main directory

--------------------
### Quick start

1. Run `mix check`
2. Run `bin/run`

--------------------
### Introduction

An agent-based simulation environment with the goal of being realistic and robust enough for the analysis of algorithmic trading strategies. It is centred around a fully functioning limit order book (LOB) and populations of agents that represent common market behaviours and strategies. The agents operate on different timescales and their strategic behaviour depends on other market participants.

ABMs can be thought of as models in which a number of heterogeneous agents interact with each other and their environment in a particular way. One of the key advantages of ABMs, compared to the other modelling methods, is their ability to model the heterogeneity of agents. Moreover, ABMs can provide insight into not just the behaviour of individual agents but also the aggregate effects that emerge from the interactions of all agents. This type of modelling lends itself perfectly to capturing the complex phenomena often found in financial systems.

The main objective of the program is to identify the emerging patterns due to the complex interactions within the market. We consider five categories of traders (simplest explanation of the market ecology) which enables us to credibly mimic (including extreme price changes) price patterns in the market. The model is stated in pseudo-continuous time. That is, a simulated day is divided into T = 300,000 periods (approximately the number of 10ths of a second in an 8.5 h trading day) and during each period there is a possibility for each agent to act. Lower action probabilities correspond to slower trading speeds.

The model comprises of 5 agent types: Market Makers, Liquidity Consumers, Mean Reversion Traders, Momentum Traders and Noise Traders. Importantly, when chosen, agents are not required to act. This facet allows agents to vary their activity through time and in response the market, as with real-world market participants.

Upon being chosen to act, if an agent wishes to submit an order, it will communicate an order type, volume and price determined by that agent’s internal logic. The order is then submitted to the LOB where it is matched using price-time priority. If no match occurs then the order is stored in the book until it is later filled or canceled by the originating trader.

--------------------
### Architecture

The platform favours correctness, developer agility, and stability. Throughput, latency, and execution speed are not overlooked, but viewed as secondary. The idea is to build a system that is simple/correct and then optimise for performance.

The system is composed of the following Elixir GenServer processes:
- Market: A coordinating process that summons the traders to act on each iteration.
- Exchange: A fully functioning limit order book and matching engine. Provides Level 1 and Level 2 market data. Notifies traders when their trades have executed.
- Traders: Various Trader types that make up the market ecology.
- Reporting service: A service that dispatches public market data to interested parties and writes the varies output series to file.

Separating the runtime for each of these processes provides us with isolation guarantees that allow us to grow functionality irrespective of dependencies one component may have on another, not to mention the desired behaviour that system failures will not bring down non-dependent parts of the application. Basically, a Trader process failing shouldn't bring down the Exchange. We can think of our system as a collection of small, independent threads of logic that communicate with other processes through an agreed upon interface.

![img](https://github.com/Rober-t/apxr/blob/master/img.png)

**Summary of messages used in the main interactions**

| Input to venue          | Description                                                          | Received from             |
|------------------------ |--------------------------------------------------------------------- |-------------------------- |
| New Order               | A new order is received                                              | Trader                    |
| Cancel Order            | An order cancel request is received                                  | Trader                    |

| Output from venue       | Description                                                          | Sent to                   |
|------------------------ |--------------------------------------------------------------------- |-------------------------  |
| Order Execution Report  | An execution report is sent after an order is completed or canceled  | Trader                    |
| Orderbook Event         | A report is sent when certain orderbook events occur                 | Reporting Service         |
| Market Data             | Level 1 and Level 2 market data                                      | Trader                    |

| Input to trader         | Description                                                          | Received from             |
|------------------------ |--------------------------------------------------------------------- |-------------------------  |
| Order Execution Report  | An execution report is received after an order is completed/canceled | Trading Venue             |
| Orderbook Event         | If subscribed, a report is sent after certain events occur           | Reporting Service         |
| Market Data             | Level 1 and Level 2 market data                                      | Trading Venue             |

--------------------
### Configuration

Configuration is placed as close as possible to where it is used and not via the application environment. See the module attributes that can be found at the top of most files.

--------------------
### Outputs

The program outputs four CSV files:
- `apxr_mid_prices`
- `apxr_trades`
- `apxr_order_sides`
- `apxr_price_impacts`

--------------------
### Validation

The data can be validated with the attached Juypter notebook `validate.ipynb`. It requires Python 3 to be installed. The notebook is configured to import the data from the above files. The model is validated against a number of stylised market properties including: clustered volatility, autocorrelation of returns, long memory in order flow, price impact and the presence of extreme price events.

Run

```
jupyter notebook
```

Navigate to 'http://localhost:8888/notebooks/validate.ipynb'

--------------------
### Future work

The program is designed for extension. For example, additional tickers, venues, circuit breakers, etc., can all be added. To implement your own trader see the `MyTrader` module. This can be modified to implement your trading strategy. Multiple different strategies can be added. If you would prefer to work in Python that too can easily be implemented. What you build on top is up to you!

--------------------
### Debugging

At the top of your module, add the following line:

```
require IEx
```

Next, inside of your function, add the following line:

```
IEx.pry
```

To log something to IO:

```
IO.puts("string")
```

or

```
IO.inspect(SomethingToInspect)
```

--------------------

Copyright (C) 2019 ApproximateReality - approximatereality@gmail.com
