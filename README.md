# APXR

An agent-based simulation environment that is realistic and robust enough for the analysis of algorithmic trading strategies. It is centered around a fully functioning limit order book (LOB) and populations of agents that represent common market behaviors and strategies. The agents operate on different timescales and their strategic behaviors depend on other market participants.

ABMs can be thought of as models in which a number of heterogeneous agents interact with each other and their environment in a particular way. One of the key advantages of ABMs, compared to the other modeling methods, is their ability to model the heterogeneity of agents. Moreover, ABMs can provide insight into not just the behavior of individual agents but also the aggregate effects that emerge from the interactions of all agents. This type of modeling lends itself perfectly to capturing the complex phenomena often found in financial systems.

The main objective of the program is to identify the emerging patterns due to the complex interactions within the market. We consider five categories of traders (simplest explanation of the market ecology) which enables us to credibly mimic (including extreme price changes) price patterns in the market. The model is stated in pseudo-continuous time. That is, a simulated day is divided into T = 300,000 periods (approximately the number of 10ths of a second in an 8.5 h trading day) and during each period there is a possibility for each agent to act. Lower action probabilities correspond to slower trading speeds.

The model comprises of 5 agent types: Market makers, liquidity consumers, mean reversion traders, momentum traders and noise traders. Importantly, when chosen, agents are not required to act. This facet allows agents to vary their activity through time and in response the market, as with real-world market participants.

Upon being chosen to act, if an agent wishes to submit an order, it will communicate an order type, volume and price determined by that agent’s internal logic. The order is then submitted to the LOB where it is matched using price-time priority. If no match occurs then the order is stored in the book until it is later filled or canceled by the originating trader.

--------------------
### Table of Contents

* [Requirements](#requirements)
* [Installation](#installation)
* [Quick start](#quick-start)
* [Erlang VM](#erlang-vm)
* [Introduction](#introduction)
* [Configuration](#configuration)
* [Outputs](#outputs)
* [Validation](#validation)
* [Development](#development)
* [Debugging](#debugging)

--------------------
### Requirements

  - [Erlang/OTP 21](https://github.com/erlang)
  - [Elixir](https://elixir-lang.org/)

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
2. Run `mix run -e APXR.Market.open --no-halt`

--------------------
### Erlang VM

The Erlang VM runs as one operating system process, and by default runs one OS thread per core. Elixir programs use all CPU cores.

Erlang processes have no connection to OS processes or threads. Erlang processes are lightweight (grow and shrink dynamically) with small memory footprint, fast to create and terminate, and the scheduling overhead is low. An Erlang system running over one million (Erlang) processes may run one operating system process. Erlang processes share no state with each other, and communicate through asynchronous messages. This makes it the first popular actor-based concurrency implementation.

If process is waiting for a message (stuck in receive operator) it will never be queued for execution until a message is found. This is why millions of mostly idle processes are able to run on a single machine without reaching high CPU usage.

Erlang’s garbage collector works under certain assumptions that help its efficiency. Every variable is immutable, so once a variable is created, the value it points to never changes. Values are copied between processes, so memory referenced in a process is (almost always) isolated. And the garbage collector runs per process, which are relatively small. See section 4 of Programming the Parallel World for a detailed overview of Erlang processes and garbage collection.

--------------------
### Introduction

The platform favors correctness, developer agility, and stability. Throughput, latency, and execution speed are not overlooked, but viewed as secondary. The idea is to build a system that is simple/correct and then optimize for performance.

The system is composed of the following Elixir GenServer processes all of which fall under the same supervision tree:
- Market: A coordinating process that summons the traders to act on each iteration.
- Exchange: A fully functioning limit order book and matching engine. Provides Level 1 and Level 2 market data on demand. Notifies traders when their trades have executed.
- Traders: Various different Trader types that form the market ecology.
- Reporting service: A service that dispatches public market data to interested parties and writes the varies output series to file.

Separating the runtime for each of these processes provides us with isolation guarantees that allow us to grow functionality irrespective to dependencies one component may have on another, not to mention the extremely desired behavior that system failures will not bring down non-dependent parts of the application. Basically, a trader process failing shouldn't bring down the Exchange. We can think of our system as a collection of small, independent threads of logic that communicate with other processes through an agreed upon interface.

![img_1](https://github.com/Rober-t/apxr/blob/master/img.png)

**Summary of messages used in the main interactions**

| Input to venue          | Description                                                          | Received from             |
|------------------------ |--------------------------------------------------------------------- |-------------------------- |
| New Order               | A new order is received                                              | Trader                    |
| Cancel Order            | An order cancel request is received                                  | Trader                    |

| Output from venue       | Description                                                          | Sent to                   |
|------------------------ |--------------------------------------------------------------------- |-------------------------  |
| Order Execution Report  | An execution report is sent after an order is completed or canceled  | Trader                    |
| Orderbook Event         | A report is sent after when certain orderbook events occur           | Reporting Service         |
| Market Data             | Level 1 and Level 2 market data                                      | Trader                    |

| Input to trader         | Description                                                          | Received from             |
|------------------------ |--------------------------------------------------------------------- |-------------------------  |
| Order Execution Report  | An execution report is received after an order is completed          | Trading Venue             |
| Orderbook Event         | If subscribed, a report is sent after when certain events occur      | Reporting Service         |
| Market Data             | Level 1 and Level 2 market data                                      | Trading Venue             |

--------------------
### Configuration

Configuration is placed as close as possible to where it is used and not via the application environment. See the module attributes that can be found at the top of most files.

--------------------
### Outputs

The program outputs three CSV files:
- `apxr_mid_prices`
  - The mid-price for each iteration.
- `apxr_price_impact`
  - For each market order that is matched it outputs the order_id, before_price, after_price and volume.
- `apxr_event_log`
  - A time ordered log of orderbook and matching engine events. The default is not to output everything.

--------------------
### Validation

The data can be validated with the attached Juypter notebook. It is configured to import the data from the above files. The model is able to reproduce a number of stylized market properties including: clustered volatility, autocorrelation of returns, long memory in order flow, concave price impact and the presence of extreme price events.

--------------------
### Development

The program is designed for extension. For example, additional tickers, venues, circuit breakers, etc., can all be added. To implement your own trader see the `MyTrader` module. This can be modified to implement your trading strategy. Multiple different strategies can be added. If you would prefer to work in Python that too can easily be implemented. Furthermore, the random number seed can be held constant across runs to get more deterministic behavior. What you build on top is up to you and your needs.

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
Copyright (C) 2019 ApproximateReality - hello@approximatereality.com