defmodule Pickle do
  @type argument :: %{content: String.t(), location: Location.t()} | %{rows: [TableRow.t()]}
  @type step :: %{arguments: [argument], locations: [Location.t()], text: String.t()}
  @type t :: %__MODULE__{
          language: String.t(),
          locations: [Location.t()],
          name: String.t(),
          steps: [step],
          tags: [Tag.t()]
        }

  @enforce_keys [:language, :locations, :name, :steps, :tags]
  defstruct @enforce_keys
end
