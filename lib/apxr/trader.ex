defmodule APXR.Trader do
  @moduledoc """
  Represents a trader in the system.
  """

  alias APXR.{
    Order
  }

  @enforce_keys [
    :trader_id,
    :type
  ]

  defstruct trader_id: nil,
            type: nil,
            cash: nil,
            outstanding_orders: nil,
            side: nil,
            lag_price: nil,
            n: nil,
            m: nil,
            s: nil,
            ema_prev: nil,
            vol_to_fill: nil

  @type t() :: %__MODULE__{
          trader_id: tuple(),
          type: atom(),
          cash: non_neg_integer() | nil,
          outstanding_orders: list() | nil,
          side: non_neg_integer() | nil,
          n: float() | nil,
          m: float() | nil,
          s: float() | nil,
          ema_prev: float() | nil,
          vol_to_fill: float() | nil
        }

  @callback actuate(id :: integer()) :: :ok
  @callback execution_report(id :: integer(), order :: %Order{}, msg :: atom()) :: :ok
end
