defmodule Gherkin.TableRow do
  alias Gherkin.{Location, TableCell}

  @type t :: %__MODULE__{cells: [TableCell.t()], location: Location.t(), type: :TableRow}

  @enforce_keys [:cells, :location]
  defstruct @enforce_keys ++ [type: :TableRow]
end
