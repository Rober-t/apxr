defmodule APXR.ProgressBar do
  @moduledoc """
  Command-line progress bar
  """

  @progress_bar_size 50
  @complete_character "="
  @incomplete_character "_"

  def print(current, total) do
    percent = percent = (current / total * 100) |> Float.round(1)
    divisor = 100 / @progress_bar_size

    complete_count = round(percent / divisor)
    incomplete_count = @progress_bar_size - complete_count

    complete = String.duplicate(@complete_character, complete_count)
    incomplete = String.duplicate(@incomplete_character, incomplete_count)

    progress_bar = "|#{complete}#{incomplete}|   #{percent}%  #{current}/#{total}"

    IO.write("\r#{progress_bar}")
  end
end
