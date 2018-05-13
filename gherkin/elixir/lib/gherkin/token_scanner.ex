defmodule Gherkin.TokenScanner do
  @moduledoc """
  The scanner reads a gherkin doc (typically read from a `.feature` file) and creates a token for
  line. The tokens are passed to the parser, which outputs an AST (Abstract Syntax Tree).

  If the scanner sees a `# language` header, it will reconfigure itself dynamically to look for
  Gherkin keywords for the associated language. The keywords are defined in
  `gherkin-languages.json`.
  """

  alias Gherkin.{GherkinLine, Location, Token}

  @type t :: %__MODULE__{device: IO.device(), line_number: non_neg_integer}

  @enforce_keys [:device]
  defstruct @enforce_keys ++ [line_number: 0]

  @spec new(String.t() | IO.device()) :: t
  def new(string_or_device)

  def new(string) when is_binary(string),
    do: %__MODULE__{device: string |> StringIO.open() |> elem(1)}

  def new(device) when is_atom(device) or is_pid(device), do: %__MODULE__{device: device}

  @spec read(t) :: {Token.t(), t}
  def read(%__MODULE__{} = scanner) do
    line_number = scanner.line_number + 1
    result = IO.read(scanner.device, :line)
    line = if is_binary(result), do: GherkinLine.new(result, line_number)

    {
      %Token{line: line, location: %Location{column: 0, line_number: line_number}},
      %{scanner | line_number: line_number}
    }
  end
end
