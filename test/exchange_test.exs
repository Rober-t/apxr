defmodule APXR.ExchangeTest do
  use ExUnit.Case, async: false

  doctest APXR.Exchange

  alias APXR.{
    Exchange,
    OrderbookEvent,
    Order
  }

  setup_all do
    :ets.update_counter(:run_index, :iteration, 1, {0, 1})

    Exchange.buy_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, "99.99", 100)
    Exchange.sell_limit_order(:apxr, :apxr, {APXR.NoiseTrader, 1}, "100.01", 100)

    %{venue: :apxr, ticker: :apxr, trader: {APXR.NoiseTrader, 1}}
  end

  test "exchange", %{venue: venue, ticker: ticker, trader: trader} do
    Registry.register(APXR.ReportingServiceRegistry, "orderbook_event", [])

    assert ["99.99"] = Exchange.highest_bid_prices(venue, ticker)
    assert [100] = Exchange.highest_bid_sizes(venue, ticker)
    assert ["100.01"] = Exchange.lowest_ask_prices(venue, ticker)
    assert [100] = Exchange.lowest_ask_sizes(venue, ticker)

    ### Buy market order

    # create a buy market order for 0 volume is rejected
    assert :rejected = Exchange.buy_market_order(venue, ticker, trader, 0)

    # create a buy market when volume equal to matching volume    
    assert %Order{} = Exchange.buy_market_order(venue, ticker, trader, 100)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 0,
                      transaction: true,
                      type: :full_fill_buy_order,
                      volume: 100
                    }}

    # create a buy market order with no matching opposite
    assert %Order{} = Exchange.buy_market_order(venue, ticker, trader, 100)

    refute_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 0,
                      transaction: true,
                      volume: 100
                    }}

    # create a buy market when volume less than matching volume
    Exchange.sell_limit_order(venue, ticker, trader, "100.0", 100)

    assert ["100.0"] = Exchange.lowest_ask_prices(venue, ticker)
    assert [100] = Exchange.lowest_ask_sizes(venue, ticker)

    assert %Order{} = Exchange.buy_market_order(venue, ticker, trader, 10)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 0,
                      transaction: true,
                      type: :full_fill_buy_order,
                      volume: 10
                    }}

    # create a buy market when volume greater than matching volume
    assert %Order{volume: 910} = Exchange.buy_market_order(venue, ticker, trader, 1000)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 0,
                      transaction: true,
                      type: :partial_fill_buy_order,
                      volume: 90
                    }}

    ### Sell market order

    # create a sell market order for 0 volume is rejected
    assert :rejected = Exchange.sell_market_order(venue, ticker, trader, 0)

    # create a sell market when volume equal to matching volume   
    assert %Order{} = Exchange.sell_market_order(venue, ticker, trader, 100)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 1,
                      transaction: true,
                      type: :full_fill_sell_order,
                      volume: 100
                    }}

    # create a sell market order with no matching opposite
    assert %Order{} = Exchange.sell_market_order(venue, ticker, trader, 100)

    refute_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 1,
                      transaction: true,
                      volume: 100
                    }}

    # create a sell market when volume less than matching volume
    Exchange.buy_limit_order(venue, ticker, trader, "100.0", 100)

    assert %Order{} = Exchange.sell_market_order(venue, ticker, trader, 10)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 1,
                      transaction: true,
                      type: :full_fill_sell_order,
                      volume: 10
                    }}

    # create a sell market when volume greater than matching volume
    assert %Order{volume: 910} = Exchange.sell_market_order(venue, ticker, trader, 1000)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 1,
                      transaction: true,
                      type: :partial_fill_sell_order,
                      volume: 90
                    }}

    ### Buy limit order

    # create a buy limit order for 0 volume is rejected
    assert :rejected = Exchange.buy_limit_order(venue, ticker, trader, "100.0", 0)

    # create a buy limit order for 0 price is rejected
    assert :rejected = Exchange.buy_limit_order(venue, ticker, trader, 0.0, 100)

    # create a buy limit when volume equal to matching volume    
    Exchange.sell_limit_order(venue, ticker, trader, "100.0", 100)

    assert %Order{} = Exchange.buy_limit_order(venue, ticker, trader, "100.0", 100)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 0,
                      transaction: true,
                      type: :full_fill_buy_order,
                      volume: 100
                    }}

    # create a buy limit order with no matching opposite
    assert %Order{} = Exchange.buy_limit_order(venue, ticker, trader, "100.0", 100)

    refute_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 0,
                      transaction: true,
                      volume: 100
                    }}

    # create a buy limit when volume less than matching volume
    Exchange.sell_limit_order(venue, ticker, trader, "100.0", 200)

    assert [] = Exchange.highest_bid_prices(venue, ticker)
    assert 0 = Exchange.highest_bid_sizes(venue, ticker)
    assert ["100.0"] = Exchange.lowest_ask_prices(venue, ticker)
    assert [100] = Exchange.lowest_ask_sizes(venue, ticker)

    assert %Order{} = Exchange.buy_limit_order(venue, ticker, trader, "100.0", 10)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 0,
                      transaction: true,
                      type: :full_fill_buy_order,
                      volume: 10
                    }}

    # create a buy limit when volume greater than matching volume
    assert %Order{volume: 910} = Exchange.buy_limit_order(venue, ticker, trader, "100.0", 1000)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 0,
                      transaction: true,
                      type: :partial_fill_buy_order,
                      volume: 90
                    }}

    ### Sell limit order
    Exchange.sell_limit_order(venue, ticker, trader, "100.0", 910)

    assert [] = Exchange.highest_bid_prices(venue, ticker)
    assert 0 = Exchange.highest_bid_sizes(venue, ticker)
    assert [] = Exchange.lowest_ask_prices(venue, ticker)
    assert 0 = Exchange.lowest_ask_sizes(venue, ticker)

    # create a sell limit order for 0 volume is rejected
    assert :rejected = Exchange.sell_limit_order(venue, ticker, trader, "100.0", 0)

    # create a sell limit order for 0 price is rejected
    assert :rejected = Exchange.sell_limit_order(venue, ticker, trader, 0.0, 100)

    # create a sell limit when volume equal to matching volume    
    Exchange.buy_limit_order(venue, ticker, trader, "100.0", 100)

    assert %Order{} = Exchange.sell_limit_order(venue, ticker, trader, "100.0", 100)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 1,
                      transaction: true,
                      type: :full_fill_sell_order,
                      volume: 100
                    }}

    # create a sell limit order with no matching opposite
    assert %Order{} = Exchange.sell_limit_order(venue, ticker, trader, "100.0", 75)

    refute_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 1,
                      transaction: true,
                      volume: 75
                    }}

    # create a sell limit when volume less than matching volume
    Exchange.buy_limit_order(venue, ticker, trader, "100.0", 175)

    assert ["100.0"] = Exchange.highest_bid_prices(venue, ticker)
    assert [100] = Exchange.highest_bid_sizes(venue, ticker)
    assert [] = Exchange.lowest_ask_prices(venue, ticker)
    assert 0 = Exchange.lowest_ask_sizes(venue, ticker)

    assert %Order{} = Exchange.sell_limit_order(venue, ticker, trader, "100.0", 10)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 1,
                      transaction: true,
                      type: :full_fill_sell_order,
                      volume: 10
                    }}

    # create a sell limit when volume greater than matching volume
    assert %Order{volume: 910} = Exchange.sell_limit_order(venue, ticker, trader, "100.0", 1000)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 1,
                      transaction: true,
                      type: :partial_fill_sell_order,
                      volume: 90
                    }}

    ### Cancel order

    Exchange.buy_limit_order(venue, ticker, trader, "100.0", 910)

    assert [] = Exchange.highest_bid_prices(venue, ticker)
    assert 0 = Exchange.highest_bid_sizes(venue, ticker)
    assert [] = Exchange.lowest_ask_prices(venue, ticker)
    assert 0 = Exchange.lowest_ask_sizes(venue, ticker)

    # cancel existing buy order
    assert %Order{} = order = Exchange.buy_limit_order(venue, ticker, trader, "100.0", 50)

    assert ["100.0"] = Exchange.highest_bid_prices(venue, ticker)
    assert [50] = Exchange.highest_bid_sizes(venue, ticker)

    assert :ok = Exchange.cancel_order(venue, ticker, order)

    assert [] = Exchange.highest_bid_prices(venue, ticker)
    assert 0 = Exchange.highest_bid_sizes(venue, ticker)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 0,
                      type: :cancel_limit_order,
                      volume: 50
                    }}

    # cancel existing sell order   
    assert %Order{} = order = Exchange.sell_limit_order(venue, ticker, trader, "100.0", 50)

    assert ["100.0"] = Exchange.lowest_ask_prices(venue, ticker)
    assert [50] = Exchange.lowest_ask_sizes(venue, ticker)

    assert :ok = Exchange.cancel_order(venue, ticker, order)

    assert [] = Exchange.lowest_ask_prices(venue, ticker)
    assert 0 = Exchange.lowest_ask_sizes(venue, ticker)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 1,
                      type: :cancel_limit_order,
                      volume: 50
                    }}

    assert [] = Exchange.highest_bid_prices(venue, ticker)
    assert 0 = Exchange.highest_bid_sizes(venue, ticker)
    assert [] = Exchange.lowest_ask_prices(venue, ticker)
    assert 0 = Exchange.lowest_ask_sizes(venue, ticker)

    # cancel partially matched buy order                    
    assert %Order{} = order = Exchange.buy_limit_order(venue, ticker, trader, "100.0", 50)

    assert %Order{} = Exchange.sell_limit_order(venue, ticker, trader, "100.0", 25)

    assert ["100.0"] = Exchange.highest_bid_prices(venue, ticker)
    assert [25] = Exchange.highest_bid_sizes(venue, ticker)

    assert :ok = Exchange.cancel_order(venue, ticker, order)

    assert [] = Exchange.highest_bid_prices(venue, ticker)
    assert 0 = Exchange.highest_bid_sizes(venue, ticker)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 0,
                      type: :cancel_limit_order,
                      volume: 50
                    }}

    # cancel partially matched sell order    
    assert %Order{} = order = Exchange.sell_limit_order(venue, ticker, trader, "100.0", 50)

    assert %Order{} = Exchange.buy_limit_order(venue, ticker, trader, "100.0", 25)

    assert ["100.0"] = Exchange.lowest_ask_prices(venue, ticker)
    assert [25] = Exchange.lowest_ask_sizes(venue, ticker)

    assert :ok = Exchange.cancel_order(venue, ticker, order)

    assert [] = Exchange.lowest_ask_prices(venue, ticker)
    assert 0 = Exchange.lowest_ask_sizes(venue, ticker)

    assert_receive {:broadcast,
                    %OrderbookEvent{
                      direction: 1,
                      type: :cancel_limit_order,
                      volume: 50
                    }}

    assert [] = Exchange.highest_bid_prices(venue, ticker)
    assert 0 = Exchange.highest_bid_sizes(venue, ticker)
    assert [] = Exchange.lowest_ask_prices(venue, ticker)
    assert 0 = Exchange.lowest_ask_sizes(venue, ticker)

    # cancel buy order that does not exist                    
    assert %Order{} = order = Exchange.buy_limit_order(venue, ticker, trader, "100.0", 50)

    assert %Order{} = other_order = Exchange.buy_limit_order(venue, ticker, trader, "100.0", 50)

    assert ["100.0"] = Exchange.highest_bid_prices(venue, ticker)
    assert [100] = Exchange.highest_bid_sizes(venue, ticker)

    assert :ok = Exchange.cancel_order(venue, ticker, order)

    assert ["100.0"] = Exchange.highest_bid_prices(venue, ticker)
    assert [50] = Exchange.highest_bid_sizes(venue, ticker)

    assert :ok = Exchange.cancel_order(venue, ticker, order)

    assert ["100.0"] = Exchange.highest_bid_prices(venue, ticker)
    assert [50] = Exchange.highest_bid_sizes(venue, ticker)

    assert :ok = Exchange.cancel_order(venue, ticker, other_order)

    assert [] = Exchange.highest_bid_prices(venue, ticker)
    assert 0 = Exchange.highest_bid_sizes(venue, ticker)

    # cancel sell order that does not exist          
    assert %Order{} = order = Exchange.sell_limit_order(venue, ticker, trader, "100.0", 50)

    assert %Order{} = other_order = Exchange.sell_limit_order(venue, ticker, trader, "100.0", 50)

    assert ["100.0"] = Exchange.lowest_ask_prices(venue, ticker)
    assert [100] = Exchange.lowest_ask_sizes(venue, ticker)

    assert :ok = Exchange.cancel_order(venue, ticker, order)

    assert ["100.0"] = Exchange.lowest_ask_prices(venue, ticker)
    assert [50] = Exchange.lowest_ask_sizes(venue, ticker)

    assert :ok = Exchange.cancel_order(venue, ticker, order)

    assert ["100.0"] = Exchange.lowest_ask_prices(venue, ticker)
    assert [50] = Exchange.lowest_ask_sizes(venue, ticker)

    assert :ok = Exchange.cancel_order(venue, ticker, other_order)

    assert [] = Exchange.lowest_ask_prices(venue, ticker)
    assert 0 = Exchange.lowest_ask_sizes(venue, ticker)

    ###
    Exchange.buy_market_order(venue, ticker, trader, 500)
    Exchange.sell_market_order(venue, ticker, trader, 500)

    Exchange.buy_limit_order(venue, ticker, trader, "99.99", 100)
    Exchange.sell_limit_order(venue, ticker, trader, "100.01", 100)

    assert ["99.99"] = Exchange.highest_bid_prices(venue, ticker)
    assert [100] = Exchange.highest_bid_sizes(venue, ticker)
    assert ["100.01"] = Exchange.lowest_ask_prices(venue, ticker)
    assert [100] = Exchange.lowest_ask_sizes(venue, ticker)
    ###

    # Bid price & bid size
    assert "99.99" = APXR.Exchange.bid_price(:apxr, :apxr)
    assert 100 = APXR.Exchange.bid_size(:apxr, :apxr)

    Exchange.sell_market_order(venue, ticker, trader, 100)

    assert "0.0" = APXR.Exchange.bid_price(:apxr, :apxr)
    assert 0 = APXR.Exchange.bid_size(:apxr, :apxr)

    Exchange.buy_limit_order(venue, ticker, trader, "100.0", 100)

    assert "100.0" = APXR.Exchange.bid_price(:apxr, :apxr)
    assert 100 = APXR.Exchange.bid_size(:apxr, :apxr)

    Exchange.buy_limit_order(venue, ticker, trader, 50.0, 100)
    Exchange.buy_limit_order(venue, ticker, trader, 125.0, 100)
    Exchange.buy_limit_order(venue, ticker, trader, "150.0", 100)
    Exchange.buy_limit_order(venue, ticker, trader, "100.0", 100)

    assert "150.0" = APXR.Exchange.bid_price(:apxr, :apxr)
    assert 100 = APXR.Exchange.bid_size(:apxr, :apxr)

    Exchange.buy_limit_order(venue, ticker, trader, 250.0, 100)
    Exchange.buy_limit_order(venue, ticker, trader, 50.0, 100)

    assert "250.0" = APXR.Exchange.bid_price(:apxr, :apxr)
    assert 100 = APXR.Exchange.bid_size(:apxr, :apxr)

    assert ["50.0", "100.0", "150.0", "250.0"] = Exchange.highest_bid_prices(venue, ticker)
    assert [200, 200, 100, 100] = Exchange.highest_bid_sizes(venue, ticker)

    Exchange.sell_market_order(venue, ticker, trader, 1000)

    # Last price & last size 1/2
    assert "50.0" = APXR.Exchange.last_price(:apxr, :apxr)
    assert 100 = APXR.Exchange.last_size(:apxr, :apxr)

    # Ask price & ask size
    assert "0.0" = APXR.Exchange.ask_price(:apxr, :apxr)
    assert 0 = APXR.Exchange.ask_size(:apxr, :apxr)

    Exchange.sell_limit_order(venue, ticker, trader, "100.0", 100)

    assert "100.0" = APXR.Exchange.ask_price(:apxr, :apxr)
    assert 100 = APXR.Exchange.ask_size(:apxr, :apxr)

    Exchange.sell_limit_order(venue, ticker, trader, "150.0", 100)
    Exchange.sell_limit_order(venue, ticker, trader, 50.0, 100)
    Exchange.sell_limit_order(venue, ticker, trader, "100.0", 100)

    assert "50.0" = APXR.Exchange.ask_price(:apxr, :apxr)
    assert 100 = APXR.Exchange.ask_size(:apxr, :apxr)

    Exchange.sell_limit_order(venue, ticker, trader, 50.0, 100)
    Exchange.sell_limit_order(venue, ticker, trader, 250.0, 100)

    assert "50.0" = APXR.Exchange.ask_price(:apxr, :apxr)
    assert 200 = APXR.Exchange.ask_size(:apxr, :apxr)

    assert ["250.0", "150.0", "100.0", "50.0"] = Exchange.lowest_ask_prices(venue, ticker)
    assert [100, 100, 200, 200] = Exchange.lowest_ask_sizes(venue, ticker)

    Exchange.buy_market_order(venue, ticker, trader, 1000)

    # Last price & last size 2/2
    assert "250.0" = APXR.Exchange.last_price(:apxr, :apxr)
    assert 100 = APXR.Exchange.last_size(:apxr, :apxr)

    assert [] = APXR.Exchange.highest_bid_prices(:apxr, :apxr)
    assert 0 = APXR.Exchange.highest_bid_sizes(:apxr, :apxr)

    assert [] = APXR.Exchange.lowest_ask_prices(:apxr, :apxr)
    assert 0 = APXR.Exchange.lowest_ask_sizes(:apxr, :apxr)

    # Highest bid prices & highest bid sizes
    Exchange.buy_limit_order(venue, ticker, trader, 350.0, 100)
    Exchange.buy_limit_order(venue, ticker, trader, 450.0, 100)
    Exchange.buy_limit_order(venue, ticker, trader, 250.0, 100)

    assert ["250.0", "350.0", "450.0"] = APXR.Exchange.highest_bid_prices(:apxr, :apxr)
    assert [100, 100, 100] = APXR.Exchange.highest_bid_sizes(:apxr, :apxr)

    # Lowest ask prices & lowest ask sizes
    Exchange.sell_limit_order(venue, ticker, trader, 50.0, 100)
    Exchange.sell_limit_order(venue, ticker, trader, 75.0, 100)
    Exchange.sell_limit_order(venue, ticker, trader, 25.0, 100)

    assert [] = APXR.Exchange.highest_bid_prices(:apxr, :apxr)
    assert 0 = APXR.Exchange.highest_bid_sizes(:apxr, :apxr)

    Exchange.sell_limit_order(venue, ticker, trader, 50.0, 100)
    Exchange.sell_limit_order(venue, ticker, trader, 75.0, 100)
    Exchange.sell_limit_order(venue, ticker, trader, 25.0, 100)

    assert ["75.0", "50.0", "25.0"] = APXR.Exchange.lowest_ask_prices(:apxr, :apxr)
    assert [100, 100, 100] = APXR.Exchange.lowest_ask_sizes(:apxr, :apxr)

    ###
    Exchange.buy_market_order(venue, ticker, trader, 300)
    Exchange.sell_market_order(venue, ticker, trader, 300)

    Exchange.buy_limit_order(venue, ticker, trader, "99.99", 100)
    Exchange.sell_limit_order(venue, ticker, trader, "100.01", 100)

    assert ["99.99"] = Exchange.highest_bid_prices(venue, ticker)
    assert [100] = Exchange.highest_bid_sizes(venue, ticker)
    assert ["100.01"] = Exchange.lowest_ask_prices(venue, ticker)
    assert [100] = Exchange.lowest_ask_sizes(venue, ticker)
  end
end
