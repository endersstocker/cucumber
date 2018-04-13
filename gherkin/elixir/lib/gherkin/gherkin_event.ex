defmodule Gherkin.GherkinEvent do
  alias Gherkin.{
    GherkinDocument,
    Parser,
    Pickle,
    PickleCompiler,
    Location,
    SourceEvent,
    TokenMatcher
  }

  @type t :: %{
          required(:type) => String.t(),
          optional(:data) => String.t(),
          optional(:document) => GherkinDocument.t(),
          optional(:media) => %{encoding: String.t(), type: String.t()},
          optional(:pickle) => Pickle.t(),
          optional(:source) => %{start: Location.t(), uri: Path.t()},
          optional(:uri) => Path.t()
        }

  @spec stream(SourceEvent.t(), keyword, String.t()) :: Enumerable.t()
  def stream(source_event, options, language \\ "en") do
    case Parser.parse(source_event.data, TokenMatcher.new(language)) do
      {:ok, gherkin_document} ->
        [:print_source, :print_ast, :print_pickles]
        |> Stream.filter(&Keyword.get(&1))
        |> Stream.flat_map(&events(&1, source_event, gherkin_document))

      {:error, errors} ->
        Stream.map(errors, &error_event(&1, source_event.uri))
    end
  end

  @spec events(atom, SourceEvent.t(), GherkinDocument.t()) :: Enumerable.t()
  defp events(:print_ast, source_event, gherkin_document),
    do: [%{document: gherkin_document, type: "gherkin-document", uri: source_event.uri}]

  defp events(:print_pickles, source_event, gherkin_document),
    do:
      gherkin_document
      |> PickleCompiler.compile()
      |> Stream.map(&%{pickle: &1, type: "pickle", uri: source_event.uri})

  defp events(:print_source, source_event, _gherkin_document), do: [source_event]

  defp error_event(error, uri),
    do: %{
      data: error.message,
      media: %{encoding: "utf-8", type: "text/x.cucumber.stacktrace+plain"},
      source: %{start: error.location, uri: uri},
      type: "attachment"
    }
end
