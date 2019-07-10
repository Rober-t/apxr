defmodule APXR.OrderbookEvent do
  @moduledoc """
  Represents an orderbook event in the system.
  """

  @enforce_keys [
    :run_index,
    :uid,
    :type,
    :order_id,
    :trader_id,
    :volume,
    :direction,
    :transaction
  ]

  defstruct run_index: nil,
            uid: nil,
            type: nil,
            order_id: nil,
            trader_id: nil,
            volume: nil,
            price: nil,
            direction: nil,
            transaction: nil

  @type t() :: %__MODULE__{
          run_index: pos_integer(),
          uid: integer(),
          type: atom(),
          order_id: pos_integer(),
          trader_id: tuple(),
          volume: pos_integer(),
          price: float() | nil,
          direction: integer(),
          transaction: boolean()
        }
end
