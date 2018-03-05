defmodule Gherkin.Tag do
  alias Gherkin.Location

  @type t :: %__MODULE__{location: Location.t(), name: String.t(), type: :Tag}

  @enforce_keys [:location, :name]
  defstruct @enforce_keys ++ [type: :Tag]
end
