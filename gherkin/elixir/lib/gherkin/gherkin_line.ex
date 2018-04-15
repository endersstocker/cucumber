defmodule Gherkin.GherkinLine do
  @type t :: %__MODULE__{
          indent: non_neg_integer,
          line_number: pos_integer,
          line_text: String.t(),
          trimmed_line_text: String.t()
        }

  @enforce_keys [:indent, :line_number, :line_text, :trimmed_line_text]
  defstruct @enforce_keys

  @spec empty?(t) :: boolean
  def empty?(%__MODULE__{trimmed_line_text: ""}), do: true
  def empty?(%__MODULE__{}), do: false

  @spec get_line_text(t, integer) :: String.t()
  def get_line_text(
        %__MODULE__{indent: indent, trimmed_line_text: trimmed_line_text},
        indent_to_remove
      )
      when is_integer(indent_to_remove) and (indent_to_remove < 0 or indent_to_remove > indent),
      do: trimmed_line_text

  def get_line_text(%__MODULE__{line_text: line_text}, indent_to_remove)
      when is_integer(indent_to_remove),
      do: binary_part(line_text, indent_to_remove, -1)

  @spec get_rest_trimmed(t, non_neg_integer) :: String.t()
  def get_rest_trimmed(%__MODULE__{trimmed_line_text: trimmed_line_text}, length)
      when is_integer(length) and length >= 0,
      do:
        trimmed_line_text
        |> binary_part(length, -1)
        |> String.trim()

  @spec new(String.t(), pos_integer) :: t
  def new(line_text, line_number)
      when is_binary(line_text) and is_integer(line_number) and line_number > 0 do
    {indent, trimmed_line_text} = trim_indent(line_text)

    %__MODULE__{
      indent: indent,
      line_number: line_number,
      line_text: line_text,
      trimmed_line_text: trimmed_line_text
    }
  end

  @spec start_with?(t, String.t()) :: boolean
  def start_with?(%__MODULE__{trimmed_line_text: trimmed_line_text}, prefix)
      when is_binary(prefix),
      do: String.starts_with?(trimmed_line_text, prefix)

  @spec start_with_title_keyword?(t, String.t()) :: boolean
  def start_with_title_keyword?(%__MODULE__{} = gherkin_line, keyword) when is_binary(keyword),
    do: start_with?(gherkin_line, "#{keyword}:")

  @spec table_cells(t) :: [__MODULE__.Span.t()]
  def table_cells(%__MODULE__{indent: indent, trimmed_line_text: trimmed_line_text}),
    do: table_cells(trimmed_line_text, indent + 1)

  @spec table_cells(String.t(), pos_integer) :: [__MODULE__.Span.t()]
  defp table_cells("", _column), do: []
  defp table_cells("|" <> rest, column), do: table_cells(rest, column + 1, column + 1, "", [])
  defp table_cells(<<_>> <> rest, column), do: table_cells(rest, column + 1)

  @spec table_cells(String.t(), pos_integer, pos_integer, String.t(), [__MODULE__.Span.t()]) :: [
          __MODULE__.Span.t()
        ]
  defp table_cells("", _column, _start_column, _text, acc), do: :lists.reverse(acc)

  defp table_cells("|" <> rest, column, start_column, text, acc) do
    {indent, _} = trim_indent(text)
    cell = %__MODULE__.Span{column: start_column + indent + 1, text: String.trim(text)}
    table_cells(rest, indent, column + 1, column + 1, "", [cell | acc])
  end

  defp table_cells(~S(\n) <> rest, column, start_column, text, acc),
    do: table_cells(rest, column + 2, start_column, text <> "\n", acc)

  defp table_cells(~S(\\) <> rest, column, start_column, text, acc),
    do: table_cells(rest, column + 2, start_column, text <> "\\", acc)

  defp table_cells(<<cp>> <> rest, column, start_column, text, acc),
    do: table_cells(rest, column + 1, start_column, text <> <<cp>>, acc)

  @spec trim_indent(String.t()) :: {non_neg_integer, String.t()}
  defp trim_indent(string) do
    trimmed_string = String.trim_leading(string)
    {byte_size(string) - byte_size(trimmed_string), trimmed_string}
  end

  @spec tags(t) :: [__MODULE__.Span.t()]
  def tags(%__MODULE__{indent: indent, trimmed_line_text: trimmed_line_text}) do
    {_, tags} =
      trimmed_line_text
      |> String.split("@")
      |> tl()
      |> Enum.reduce({indent + 1, []}, fn text, {column, acc} ->
        tag = %__MODULE__.Span{column: column, text: "@#{String.trim(text)}"}
        {column + byte_size(text) + 1, [tag | acc]}
      end)

    :lists.reverse(tags)
  end
end
