defmodule Gherkin.TokenFormatterBuilder do
  alias Gherkin.{Builder, Token}

  @behaviour Builder

  @type t :: %__MODULE__{tokens_text: iolist}

  defstruct tokens_text: []

  @impl Builder
  def build(%__MODULE__{} = builder, %Token{} = token),
    do: Map.update!(builder, :tokens_text, &[&1, format_token(token), ?\n])

  @spec format_token(Token.t()) :: iodata
  defp format_token(token) do
    if Token.eof?(token),
      do: "EOF",
      else: [
        ?(,
        token.location.line,
        ?:,
        token.location.column,
        ?),
        token.matched_type,
        ?:,
        token.matched_keyword,
        ?/,
        token.matched_text,
        ?/,
        format_items(token.matched_items)
      ]
  end

  @spec format_items([TableCell.t()] | [Tag.t()]) :: iolist
  defp format_items(items),
    do:
      items
      |> Stream.map(&[&1.column, ?:, &1.text])
      |> Enum.intersperse(?,)

  @impl Builder
  def end_rule(%__MODULE__{} = builder, rule_type) when is_atom(rule_type), do: builder

  @impl Builder
  def get_result(%__MODULE__{tokens_text: tokens_text}), do: IO.iodata_to_binary(tokens_text)

  @impl Builder
  def start_rule(%__MODULE__{} = builder, rule_type) when is_atom(rule_type), do: builder
end
