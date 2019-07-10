defmodule APXR.Order do
  @moduledoc """
  Represents an order in the system.
  """

  @enforce_keys [
    :ticker,
    :venue,
    :order_id,
    :trader_id,
    :side,
    :volume
  ]

  defstruct ticker: nil,
            venue: nil,
            order_id: nil,
            trader_id: nil,
            side: nil,
            volume: nil,
            price: nil,
            acknowledged_at: nil

  @type t() :: %__MODULE__{
          ticker: atom(),
          venue: atom(),
          order_id: pos_integer(),
          trader_id: tuple(),
          side: non_neg_integer(),
          volume: pos_integer(),
          price: float() | nil,
          acknowledged_at: integer() | nil
        }
end
