defmodule Gherkin.SourceEvent do
  alias Gherkin.Media

  @type t :: %__MODULE__{
          data: File.io_device(),
          media: Media.t(),
          type: String.t(),
          uri: Path.t()
        }

  @enforce_keys [:data, :media, :type, :uri]
  defstruct @enforce_keys

  @spec stream([Path.t()]) :: Enumerable.t()
  def stream(paths) when is_list(paths), do: Stream.map(paths, &event/1)

  @spec event(Path.t()) :: t
  defp event(path),
    do: %__MODULE__{
      data: File.open!(path, [:read, :utf8]),
      media: %Media{encoding: "utf-8", type: "text/x.cucumber.gherkin+plain"},
      type: "source",
      uri: path
    }
end
