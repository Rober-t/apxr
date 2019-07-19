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
            outstanding_orders: nil

  @type t() :: %__MODULE__{
          trader_id: tuple(),
          type: atom(),
          cash: non_neg_integer() | nil,
          outstanding_orders: list() | nil
        }

  @callback actuate(id :: integer()) :: :ok
  @callback execution_report(id :: integer(), order :: %Order{}, msg :: atom()) :: :ok
end
