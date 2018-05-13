defmodule Gherkin.TokenMatcher do
  alias Gherkin.{Dialect, GherkinLine, Location, NoSuchLanguageError, Token}

  @type on_match :: {:ok, Token.t(), t} | :error
  @type t :: %__MODULE__{
          active_doc_string_separator: <<_::24>> | nil,
          default_language: String.t(),
          dialect: Dialect.t(),
          indent_to_remove: non_neg_integer,
          language: String.t()
        }

  @language_pattern ~r/^\s*#\s*language\s*:\s*([a-zA-Z\-_]+)\s*$/

  @enforce_keys [:default_language, :dialect, :language]
  defstruct @enforce_keys ++ [active_doc_string_separator: nil, indent_to_remove: 0]

  @spec match_BackgroundLine(t, Token.t()) :: on_match
  def match_BackgroundLine(%__MODULE__{} = matcher, %Token{} = token),
    do: match_title_line(matcher, token, :BackgroundLine, matcher.dialect.background_keywords)

  @spec match_Comment(t, Token.t()) :: on_match
  def match_Comment(%__MODULE__{} = matcher, %Token{line: "#" <> _} = token) do
    text = GherkinLine.get_line_text(token.line, 0)
    {:ok, set_token_matched(token, :Comment, matcher.language, text, nil, 0), matcher}
  end

  def match_Comment(%__MODULE__{}, %Token{}), do: :error

  @spec match_DocStringSeparator(t, Token.t()) :: on_match
  def match_DocStringSeparator(
        %__MODULE__{active_doc_string_separator: nil} = matcher,
        %Token{} = token
      ) do
    with :error <- match_DocStringSeparator(matcher, token, ~s(""")),
         do: match_DocStringSeparator(matcher, token, ~s(```))
  end

  def match_DocStringSeparator(%__MODULE__{} = matcher, %Token{} = token) do
    if String.starts_with?(token.line, matcher.active_doc_string_separator),
      do:
        {:ok, set_token_matched(token, :DocStringSeparator, matcher.language),
         %{matcher | active_doc_string_separator: nil, indent_to_remove: 0}},
      else: :error
  end

  @spec match_DocStringSeparator(t, Token.t(), String.t()) :: on_match
  defp match_DocStringSeparator(matcher, token, <<_::24>> = separator) do
    if String.starts_with?(token.line, separator),
      do:
        {:ok,
         set_token_matched(
           token,
           :DocStringSeparator,
           matcher.language,
           GherkinLine.get_rest_trimmed(token.line, 3)
         ),
         %{matcher | active_doc_string_separator: separator, indent_to_remove: token.line.indent}},
      else: :error
  end

  @spec match_Empty(t, Token.t()) :: on_match
  def match_Empty(%__MODULE__{} = matcher, %Token{line: ""} = token),
    do: {:ok, set_token_matched(token, :Empty, matcher.language, nil, nil, 0), matcher}

  def match_Empty(%__MODULE__{}, %Token{}), do: :error

  @spec match_EOF(t, Token.t()) :: on_match
  def match_EOF(%__MODULE__{} = matcher, %Token{} = token) do
    if Token.eof?(token),
      do: {:ok, set_token_matched(token, :EOF, matcher.language), matcher},
      else: :error
  end

  @spec match_ExamplesLine(t, Token.t()) :: on_match
  def match_ExamplesLine(%__MODULE__{} = matcher, %Token{} = token),
    do: match_title_line(matcher, token, :ExamplesLine, matcher.dialect.examples_keywords)

  @spec match_FeatureLine(t, Token.t()) :: on_match
  def match_FeatureLine(%__MODULE__{} = matcher, %Token{} = token),
    do: match_title_line(matcher, token, :FeatureLine, matcher.dialect.feature_keywords)

  @spec match_Language(t, Token.t()) :: on_match
  def match_Language(%__MODULE__{} = matcher, %Token{} = token) do
    case Regex.run(@language_pattern, token.line.trimmed_line_text) do
      [_, language] ->
        {
          :ok,
          set_token_matched(token, :Language, matcher.language, language),
          change_dialect!(matcher, language, token.location)
        }

      nil ->
        :error
    end
  end

  @spec match_Other(t, Token.t()) :: on_match
  def match_Other(%__MODULE__{} = matcher, %Token{} = token),
    do: {
      :ok,
      set_token_matched(
        token,
        :Other,
        matcher.language,
        other_text(matcher, token.line),
        nil,
        0
      ),
      matcher
    }

  @spec other_text(t, GherkinLine.t()) :: String.t()
  defp other_text(matcher, line) do
    text = GherkinLine.get_line_text(line, matcher.indent_to_remove)

    if matcher.active_doc_string_separator,
      do: String.replace(text, ~S(\"\"\"), ~s(""")),
      else: text
  end

  @spec match_ScenarioLine(t, Token.t()) :: on_match
  def match_ScenarioLine(%__MODULE__{} = matcher, %Token{} = token),
    do: match_title_line(matcher, token, :ScenarioLine, matcher.dialect.scenario_keywords)

  @spec match_ScenarioOutlineLine(t, Token.t()) :: on_match
  def match_ScenarioOutlineLine(%__MODULE__{} = matcher, %Token{} = token),
    do:
      match_title_line(
        matcher,
        token,
        :ScenarioOutlineLine,
        matcher.dialect.scenario_outline_keywords
      )

  @spec match_title_line(
          t,
          Token.t(),
          :BackgroundLine | :ExamplesLine | :FeatureLine | :ScenarioLine | :ScenarioOutlineLine,
          [String.t(), ...]
        ) :: on_match
  defp match_title_line(matcher, token, token_type, keywords) do
    if keyword = Enum.find(keywords, &GherkinLine.start_with_title_keyword?(token.line, &1)) do
      title = GherkinLine.get_rest_trimmed(token.line, byte_size(keyword) + 1)
      {:ok, set_token_matched(token, token_type, matcher.language, title, keyword), matcher}
    else
      :error
    end
  end

  @spec match_StepLine(t, Token.t()) :: on_match
  def match_StepLine(%__MODULE__{} = matcher, %Token{} = token) do
    if keyword = dialect_keyword(token.line, matcher.dialect),
      do: {
        :ok,
        set_token_matched(
          token,
          :StepLine,
          matcher.language,
          GherkinLine.get_rest_trimmed(token.line, byte_size(keyword)),
          keyword
        ),
        matcher
      },
      else: :error
  end

  @spec dialect_keyword(GherkinLine.t(), Dialect.t()) :: String.t() | nil
  defp dialect_keyword(line, dialect) do
    with nil <- keyword(line, dialect.given_keywords),
         nil <- keyword(line, dialect.when_keywords),
         nil <- keyword(line, dialect.then_keywords),
         nil <- keyword(line, dialect.and_keywords),
         nil <- keyword(line, dialect.but_keywords),
         do: nil
  end

  @spec keyword(GherkinLine.t(), Dialect.keywords()) :: String.t() | nil
  defp keyword(line, keywords), do: Enum.find(keywords, &String.starts_with?(line, &1))

  @spec match_TableRow(t, Token.t()) :: on_match
  def match_TableRow(%__MODULE__{} = matcher, %Token{line: "|" <> _} = token),
    do: {
      :ok,
      set_token_matched(
        token,
        :TableRow,
        matcher.language,
        nil,
        nil,
        nil,
        token.line.table_cells
      ),
      matcher
    }

  def match_TableRow(%__MODULE__{}, %Token{}), do: :error

  @spec match_TagLine(t, Token.t()) :: on_match
  def match_TagLine(%__MODULE__{} = matcher, %Token{line: "@" <> _} = token),
    do: {
      :ok,
      set_token_matched(token, :TagLine, matcher.language, nil, nil, nil, token.line.tags),
      matcher
    }

  def match_TagLine(%__MODULE__{}, %Token{}), do: :error

  @spec set_token_matched(
          Token.t(),
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
          | :TagLine,
          String.t(),
          String.t() | nil,
          String.t() | nil,
          non_neg_integer | nil,
          [TableCell.t()] | [Tag.t()]
        ) :: Token.t()
  defp set_token_matched(
         token,
         matched_type,
         language,
         text \\ nil,
         keyword \\ nil,
         indent \\ nil,
         items \\ []
       ) do
    token
    |> Map.put(:matched_gherkin_dialect, language)
    |> Map.put(:matched_indent, indent || (token.line && token.line.indent) || 0)
    |> Map.put(:matched_items, items)
    |> Map.put(:matched_keyword, keyword)
    |> Map.put(:matched_text, text && String.replace(text, ~r/(\r\n|\r|\n)$/, ""))
    |> Map.put(:matched_type, matched_type)
    |> put_in([:location, :column], token.matched_indent + 1)
  end

  @spec new(String.t()) :: t
  def new(language \\ "en") when is_binary(language),
    do: change_dialect!(%__MODULE__{default_language: language}, language)

  @spec change_dialect!(t, String.t(), Location.t() | nil) :: t | no_return
  defp change_dialect!(matcher, language, location \\ nil) do
    if dialect = Dialect.get(language) do
      %{matcher | dialect: dialect, language: language}
    else
      raise NoSuchLanguageError, language: language, location: location
    end
  end
end
