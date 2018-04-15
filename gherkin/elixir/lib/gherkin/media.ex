defmodule Gherkin.Media do
  @type t :: %__MODULE__{encoding: String.t(), type: String.t()}

  @enforce_keys [:encoding, :type]
  defstruct @enforce_keys
end
