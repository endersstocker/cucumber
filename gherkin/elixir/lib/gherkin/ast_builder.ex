defmodule Gherkin.ASTBuilder do
  alias Gherkin.{ASTNode, Builder, Location, TableCell, TableRow, Tag, Token}

  @behaviour Builder

  @type t :: %__MODULE__{comments: [comment], stack: [ASTNode.t(), ...]}

  @typep comment :: %{location: Location.t(), text: String.t(), type: :Comment}

  defstruct comments: [], stack: [%ASTNode{rule_type: :None}]

  @impl Builder
  def build(%__MODULE__{} = builder, %Token{} = token) do
    if token.matched_type === :Comment do
      comment = %{location: get_location(token), text: token.matched_text, type: :Comment}
      %{builder | comments: [comment | builder.comments]}
    else
      [current_node | stack] = builder.stack
      new_node = ASTNode.add_child(current_node, token.matched_type, token)
      %{builder | stack: [new_node | stack]}
    end
  end

  @impl Builder
  def end_rule(%__MODULE__{} = builder, rule_type) when is_atom(rule_type) do
    [node1, node2 | stack] = builder.stack
    comments = :lists.reverse(builder.comments)
    new_node = ASTNode.add_child(node2, node1.rule_type, transform_node(node1, comments))
    %{builder | stack: [new_node | stack]}
  end

  @spec transform_node(ASTNode.t(), [comment]) ::
          %{required(:type) => atom, optional(atom) => term} | ASTNode.t() | nil
  defp transform_node(ast_node, comments) do
    case ast_node.rule_type do
      :Background -> transform_background_node(ast_node)
      :DataTable -> transform_data_table_node(ast_node)
      :Description -> transform_description_node(ast_node)
      :DocString -> transform_doc_string_node(ast_node)
      :Examples_Definition -> transform_examples_definition_node(ast_node)
      :Examples_Table -> transform_examples_table_node(ast_node)
      :Feature -> transform_feature_node(ast_node)
      :GherkinDocument -> transform_gherkin_document_node(ast_node, comments)
      :Scenario_Definition -> transform_scenario_definition_node(ast_node)
      :Step -> transform_step_node(ast_node)
      _ -> ast_node
    end
  end

  @spec transform_background_node(ASTNode.t()) :: %{
          required(:type) => :Background,
          optional(:description) => String.t(),
          optional(:keyword) => String.t(),
          optional(:location) => Location.t(),
          optional(:name) => String.t(),
          optional(:steps) => list
        }
  defp transform_background_node(ast_node) do
    token = ASTNode.get_item(ast_node, :BackgroundLine)

    reject_nils(%{
      description: get_description(ast_node),
      keyword: token.matched_keyword,
      location: get_location(token),
      name: token.matched_text,
      steps: get_steps(ast_node),
      type: :Background
    })
  end

  @spec get_steps(ASTNode.t()) :: list
  defp get_steps(ast_node), do: ASTNode.get_children(ast_node, :Step)

  @spec transform_data_table_node(ASTNode.t()) :: %{
          required(:type) => :DataTable,
          optional(:location) => Location.t(),
          optional(:rows) => [TableRow.t()]
        }
  defp transform_data_table_node(ast_node) do
    [%{location: location} | _] = rows = get_table_rows(node)
    reject_nils(%{location: location, rows: rows, type: :DataTable})
  end

  @spec get_table_rows(ASTNode.t()) :: [TableRow.t()]
  defp get_table_rows(ast_node) do
    tokens = ASTNode.get_children(ast_node, :TableRow)
    rows = for t <- tokens, do: %{cells: get_cells(t), location: get_location(t), type: :TableRow}
    ensure_cell_count(rows)
    rows
  end

  @spec get_cells(Token.t()) :: [TableCell.t()]
  defp get_cells(token) do
    for item <- token.matched_items,
        do: %{
          location: get_location(token, item.column),
          type: :TableCell,
          value: item.text
        }
  end

  @spec ensure_cell_count([TableRow.t()]) :: :ok | no_return
  defp ensure_cell_count([]), do: :ok

  defp ensure_cell_count([%{cells: cells} | rows]) do
    cell_count = length(cells)

    Enum.each(rows, fn row ->
      if length(row.cells) !== cell_count do
        raise ASTBuilderError,
          location: row.location,
          message: "inconsistent cell count within the table"
      end
    end)
  end

  @spec transform_description_node(ASTNode.t()) :: String.t()
  defp transform_description_node(ast_node) do
    ast_node
    |> ASTNode.get_children(:Other)
    |> Stream.take_while(&(&1.line.trimmed_line_text !== ""))
    |> Enum.map_join("\n", & &1.matched_text)
  end

  @spec transform_doc_string_node(ASTNode.t()) :: %{
          required(:type) => :DocString,
          optional(:content) => String.t(),
          optional(:content_type) => String.t(),
          optional(:location) => Location.t()
        }
  defp transform_doc_string_node(ast_node) do
    token = ASTNode.get_item(ast_node, :DocStringSeparator)

    content =
      ast_node
      |> ASTNode.get_children(:Other)
      |> Enum.map_join("\n", & &1.matched_text)

    reject_nils(%{
      content: content,
      content_type: scrub(token.matched_text),
      location: get_location(token),
      type: :DocString
    })
  end

  @spec scrub(String.t()) :: String.t() | nil
  defp scrub(""), do: nil
  defp scrub(string) when is_binary(string), do: string

  @spec transform_examples_definition_node(ASTNode.t()) :: %{
          required(:type) => :Examples_Definition,
          optional(:description) => String.t(),
          optional(:keyword) => String.t(),
          optional(:location) => Location.t(),
          optional(:name) => String.t(),
          optional(:tableBody) => term,
          optional(:tableHeader) => term,
          optional(:tags) => [Tag.t()]
        }
  defp transform_examples_definition_node(ast_node) do
    examples_node = ASTNode.get_child(ast_node, :Examples)
    token = ASTNode.get_item(examples_node, :ExampleLine)
    examples_table_node = ASTNode.get_child(examples_node, :Examples_Table)

    reject_nils(%{
      description: get_description(examples_node),
      keyword: token.matched_keyword,
      location: get_location(token),
      name: token.matched_text,
      tableBody: examples_table_node && examples_table_node.tableBody,
      tableHeader: examples_table_node && examples_table_node.tableHeader,
      tags: get_tags(ast_node),
      type: examples_node.rule_type
    })
  end

  @spec get_tags(ASTNode.t()) :: [Tag.t()]
  defp get_tags(ast_node) do
    if tags_node = ASTNode.get_child(ast_node, :Tags) do
      for token <- ASTNode.get_children(ast_node, :TagLine),
          tag_item <- token.matched_items,
          do: %{
            location: get_location(token, tag_item.column),
            name: tag_item.text,
            type: :Tag
          }
    else
      []
    end
  end

  @spec get_description(ASTNode.t()) :: String.t() | nil
  defp get_description(ast_node), do: ASTNode.get_child(ast_node, :Description)

  @spec transform_examples_table_node(ASTNode.t()) :: %{
          optional(:tableBody) => [TableRow.t()],
          optional(:tableHeader) => TableRow.t()
        }
  defp transform_examples_table_node(ast_node) do
    [header | body] = get_table_rows(ast_node)
    reject_nils(%{tableBody: body, tableHeader: header})
  end

  @spec transform_feature_node(ASTNode.t()) ::
          %{
            required(:type) => :Feature,
            optional(:children) => list,
            optional(:description) => String.t(),
            optional(:keyword) => String.t(),
            optional(:language) => String.t(),
            optional(:location) => Location.t(),
            optional(:name) => String.t(),
            optional(:tags) => [Tag.t()]
          }
          | nil
  defp transform_feature_node(ast_node) do
    if feature_header_node = ASTNode.get_child(ast_node, :Feature_Header) do
      if token = ASTNode.get_item(feature_header_node, :FeatureLine) do
        scenario = ASTNode.get_children(ast_node, :Scenario_Definition)

        children =
          if background_node = ASTNode.get_child(ast_node, :Background),
            do: [background_node | scenario],
            else: scenario

        reject_nils(%{
          children: children,
          description: get_description(feature_header_node),
          keyword: token.matched_keyword,
          language: token.matched_gherkin_dialect,
          location: get_location(token),
          name: token.matched_text,
          tags: get_tags(feature_header_node),
          type: :Feature
        })
      end
    end
  end

  @spec transform_gherkin_document_node(ASTNode.t(), [comment]) :: %{
          required(:type) => :GherkinDocument,
          optional(:comments) => [comment],
          optional(:feature) => ASTNode.t()
        }
  defp transform_gherkin_document_node(ast_node, comments),
    do:
      reject_nils(%{
        comments: comments,
        feature: ASTNode.get_child(ast_node, :Feature),
        type: :GherkinDocument
      })

  @spec transform_scenario_definition_node(ASTNode.t()) :: %{
          required(:type) => atom,
          optional(:description) => String.t(),
          optional(:examples) => list,
          optional(:keyword) => String.t(),
          optional(:location) => Location.t(),
          optional(:name) => String.t(),
          optional(:steps) => list,
          optional(:tags) => [Tag.t()]
        }
  defp transform_scenario_definition_node(ast_node) do
    tags = get_tags(ast_node)

    if scenario_node = ASTNode.get_child(ast_node, :Scenario) do
      token = ASTNode.get_item(scenario_node, :ScenarioLine)

      reject_nils(%{
        description: get_description(scenario_node),
        keyword: token.matched_keyword,
        location: get_location(token),
        name: token.matched_text,
        steps: get_steps(scenario_node),
        tags: tags,
        type: scenario_node.rule_type
      })
    else
      scenario_outline_node = ASTNode.get_child(ast_node, :ScenarioOutline)

      if !scenario_outline_node do
        raise "Internal grammar error"
      end

      token = ASTNode.get_item(scenario_outline_node, :ScenarioOutlineLine)
      examples = ASTNode.get_children(scenario_outline_node, :Examples_Definition)

      reject_nils(%{
        description: get_description(scenario_outline_node),
        examples: examples,
        keyword: token.matched_keyword,
        location: get_location(token),
        name: token.matched_text,
        steps: get_steps(scenario_outline_node),
        tags: tags,
        type: scenario_outline_node.rule_type
      })
    end
  end

  @spec transform_step_node(ASTNode.t()) :: %{
          required(:type) => :Step,
          optional(:argument) => term,
          optional(:keyword) => String.t(),
          optional(:location) => Location.t(),
          optional(:text) => String.t()
        }
  defp transform_step_node(ast_node) do
    argument = ASTNode.get_child(ast_node, :DataTable) || ASTNode.get_child(ast_node, :DocString)

    token = ASTNode.get_item(ast_node, :StepLine)

    reject_nils(%{
      argument: argument,
      keyword: token.matched_keyword,
      location: get_location(token),
      text: token.matched_text,
      type: :Step
    })
  end

  @spec get_location(Token.t(), non_neg_integer) :: Location.t()
  defp get_location(token, column \\ 0)
  defp get_location(%{location: location}, 0), do: location
  defp get_location(%{location: location}, column), do: %{location | column: column}

  @spec reject_nils(map) :: map
  defp reject_nils(map) do
    for {k, v} <- map, v !== nil, into: %{}, do: {k, v}
  end

  @impl Builder
  def get_result(%__MODULE__{stack: [current_node | _]}),
    do: ASTNode.get_child(current_node, :GherkinDocument)

  @impl Builder
  def start_rule(%__MODULE__{} = builder, rule_type) when is_atom(rule_type),
    do: %{builder | stack: [%ASTNode{rule_type: rule_type} | builder.stack]}
end
