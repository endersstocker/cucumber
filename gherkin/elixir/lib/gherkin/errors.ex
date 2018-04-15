defmodule Gherkin.ErrorMessage do
  alias Gherkin.Location

  @spec t :: String.t()

  @spec new(Location.t(), String.t()) :: t
  def new(%Location{} = location, message) when is_binary(message),
    do: "(#{location.line}:#{location.column || 0}): #{message}"
end

defmodule Gherkin.AST.BuilderError do
  alias Gherkin.ErrorMessage

  defexception [:location, :message]

  @impl Exception
  def message(%__MODULE__{} = exception),
    do: ErrorMessage.new(exception.location, exception.message)
end

defmodule Gherkin.CompositeParserError do
  alias Gherkin.ErrorMessage

  defexception [:errors, :location]

  @impl Exception
  def message(%__MODULE__{} = exception) do
    messages = Enum.map_join(exception.errors, "\n", &Exception.message/1)
    ErrorMessage.new(exception.location, "Parser errors:\n#{messages}")
  end
end

defmodule Gherkin.NoSuchLanguageError do
  alias Gherkin.ErrorMessage

  defexception [:language, :location]

  @impl Exception
  def message(%__MODULE__{} = exception),
    do: ErrorMessage.new(exception.location, "Language not supported: #{exception.language}")
end

defmodule Gherkin.UnexpectedEOFError do
  alias Gherkin.ErrorMessage

  defexception [:expected_token_types, :received_token]

  @impl Exception
  def message(%__MODULE__{} = exception) do
    expected =
      exception
      |> Map.fetch!(:expected_token_types)
      |> Enum.join(", ")

    exception
    |> Map.fetch!(:received_token)
    |> Map.fetch!(:location)
    |> ErrorMessage.new("unexpected end of file, expected: #{expected}")
  end
end

defmodule Gherkin.UnexpectedTokenError do
  alias Gherkin.ErrorMessage

  defexception [:expected_token_types, :received_token]

  @impl Exception
  def message(%__MODULE__{} = exception) do
    expected =
      exception
      |> Map.fetch!(:expected_token_types)
      |> Enum.join(", ")

    got =
      exception
      |> Map.fetch!(:received_token)
      |> Token.token_value()
      |> String.trim()

    exception
    |> Map.fetch!(:received_token)
    |> location()
    |> ErrorMessage.new("expected: #{expected}, got '#{got}'")
  end

  @spec location(Token.t()) :: Location.t()
  defp location(%{line: line, location: token_location}) do
    if token_location.column and token_location.column > 0,
      do: token_location,
      else: %{token_location | column: line.indent + 1}
  end
end
