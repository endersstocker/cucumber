defmodule Gherkin.Token do
  alias Gherkin.{GherkinLine, Location, TableCell.t(), Tag.t()}

  @type t :: %__MODULE__{
          line: GherkinLine.t(),
          location: Location.t(),
          matched_gherkin_dialect: String.t() | nil,
          matched_indent: non_neg_integer,
          matched_items: [TableCell.t()] | [Tag.t()],
          matched_keyword: String.t() | nil,
          matched_text: String.t() | nil,
          matched_type:
            :BackgroundLine
            | :Comment
            | :DocStringSeparator
            | :Empty
            | :EOF
            | :ExamplesLine
            | :FeatureLine
            | :Language
            | :Other
            | :ScenarioLine
            | :ScenarioOutlineLine
            | :StepLine
            | :TableRow
            | :TagLine
        }

  @enforce_keys [
    :line,
    :location,
    :matched_gherkin_dialect,
    :matched_indent,
    :matched_items,
    :matched_keyword,
    :matched_text,
    :matched_type
  ]
  defstruct @enforce_keys

  @spec eof?(t) :: boolean
  def eof?(%__MODULE__{line: line}), do: line === nil

  @spec token_value(t) :: String.t()
  def token_value(%__MODULE__{} = token) do
    if eof?(token), do: "EOF", else: GherkinLine.get_line_text(token.line, -1)
  end
end
