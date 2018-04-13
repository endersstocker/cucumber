defmodule Gherkin.Location do
  @type t :: %__MODULE__{column: non_neg_integer, line: non_neg_integer}

  @enforce_keys [:column, :line]
  defstruct @enforce_keys
end
