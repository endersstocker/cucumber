defmodule Gherkin.TableCell do
  alias Gherkin.Location

  @type t :: %__MODULE__{location: Location.t(), type: :TableCell, value: String.t()}

  @enforce_keys [:location, :value]
  defstruct @enforce_keys ++ [type: :TableCell]
end
