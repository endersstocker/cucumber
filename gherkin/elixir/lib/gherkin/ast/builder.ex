defmodule Gherkin.AST.Builder do
  alias Gherkin.{AST, Location, TableCell, TableRow, Tag, Token}

  @type comment :: %{location: Location.t(), text: String.t(), type: :Comment}
  @typep rule_type :: atom

  @spec build(Token.t()) :: AST.Node.t() | [comment]
  def build(%Token{} = token) do
    if token.matched_type === :Comment do
      Agent.get_and_update(__MODULE__, fn state ->
        comment = %{
          location: get_location(token),
          text: token.matched_text,
          type: :Comment
        }

        comments = List.insert_at(state.comments, -1, comment)
        {comments, %{state | comments: comments}}
      end)
    else
      Agent.get(__MODULE__, fn %{stack: [current_node | _]} ->
        AST.Node.add_child(current_node, token.matched_type, token)
        current_node
      end)
    end
  end

  @spec end_rule(rule_type) :: :ok
  def end_rule(rule_type) when is_atom(rule_type),
    do:
      Agent.update(__MODULE__, fn state ->
        [old_node | stack] = state.stack
        rule_type = AST.Node.rule_type(old_node)
        child = transform_node(old_node)

        stack
        |> hd()
        |> AST.Node.add_child(rule_type, child)

        AST.Node.stop(old_node)
        %{state | stack: stack}
      end)

  @spec transform_node(AST.Node.t()) ::
          %{required(:type) => atom, optional(atom) => term} | AST.Node.t() | nil
  defp transform_node(ast_node) do
    case AST.Node.rule_type(ast_node) do
      :Background -> transform_background_node(ast_node)
      :DataTable -> transform_data_table_node(ast_node)
      :Description -> transform_description_node(ast_node)
      :DocString -> transform_doc_string_node(ast_node)
      :Examples_Definition -> transform_examples_definition_node(ast_node)
      :Examples_Table -> transform_examples_table_node(ast_node)
      :Feature -> transform_feature_node(ast_node)
      :GherkinDocument -> transform_gherkin_document_node(ast_node)
      :Scenario_Definition -> transform_scenario_definition_node(ast_node)
      :Step -> transform_step_node(ast_node)
      _ -> ast_node
    end
  end

  @spec transform_background_node(AST.Node.t()) :: %{
          optional(:description) => String.t(),
          optional(:keyword) => String.t(),
          optional(:location) => Location.t(),
          optional(:name) => String.t(),
          optional(:steps) => list,
          required(:type) => :Background
        }
  defp transform_background_node(ast_node) do
    token = AST.Node.get_item(ast_node, :BackgroundLine)

    reject_nils(%{
      description: get_description(ast_node),
      keyword: token.matched_keyword,
      location: get_location(token),
      name: token.matched_text,
      steps: get_steps(ast_node),
      type: :Background
    })
  end

  @spec get_steps(AST.Node.t()) :: list
  defp get_steps(ast_node), do: AST.Node.get_children(ast_node, :Step)

  @spec transform_data_table_node(AST.Node.t()) :: %{
          optional(:location) => Location.t(),
          optional(:rows) => [TableRow.t()],
          required(:type) => :DataTable
        }
  defp transform_data_table_node(ast_node) do
    [%{location: location} | _] = rows = get_table_rows(node)
    reject_nils(%{location: location, rows: rows, type: :DataTable})
  end

  @spec get_table_rows(AST.Node.t()) :: [TableRow.t()]
  defp get_table_rows(ast_node) do
    tokens = AST.Node.get_children(ast_node, :TableRow)
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
        raise AST.BuilderError,
          location: row.location,
          message: "inconsistent cell count within the table"
      end
    end)
  end

  @spec transform_description_node(AST.Node.t()) :: String.t()
  defp transform_description_node(ast_node) do
    ast_node
    |> AST.Node.get_children(:Other)
    |> Stream.take_while(&(&1.line.trimmed_line_text !== ""))
    |> Enum.map_join("\n", & &1.matched_text)
  end

  @spec transform_doc_string_node(AST.Node.t()) :: %{
          optional(:content) => String.t(),
          optional(:content_type) => String.t(),
          optional(:location) => Location.t(),
          required(:type) => :DocString
        }
  defp transform_doc_string_node(ast_node) do
    token = AST.Node.get_item(ast_node, :DocStringSeparator)

    content =
      ast_node
      |> AST.Node.get_children(:Other)
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

  @spec transform_examples_definition_node(AST.Node.t()) :: %{
          optional(:description) => String.t(),
          optional(:keyword) => String.t(),
          optional(:location) => Location.t(),
          optional(:name) => String.t(),
          optional(:tableBody) => term,
          optional(:tableHeader) => term,
          optional(:tags) => [Tag.t()],
          required(:type) => :Examples_Definition
        }
  defp transform_examples_definition_node(ast_node) do
    examples_node = AST.Node.get_child(ast_node, :Examples)
    token = AST.Node.get_item(examples_node, :ExampleLine)
    examples_table_node = AST.Node.get_child(examples_node, :Examples_Table)

    reject_nils(%{
      description: get_description(examples_node),
      keyword: token.matched_keyword,
      location: get_location(token),
      name: token.matched_text,
      tableBody: examples_table_node && examples_table_node.tableBody,
      tableHeader: examples_table_node && examples_table_node.tableHeader,
      tags: get_tags(ast_node),
      type: AST.Node.rule_type(examples_node)
    })
  end

  @spec get_tags(AST.Node.t()) :: [Tag.t()]
  defp get_tags(ast_node) do
    if tags_node = AST.Node.get_child(ast_node, :Tags) do
      for token <- AST.Node.get_children(ast_node, :TagLine),
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

  @spec get_description(AST.Node.t()) :: String.t() | nil
  defp get_description(ast_node), do: AST.Node.get_child(ast_node, :Description)

  @spec transform_examples_table_node(AST.Node.t()) :: %{
          optional(:tableBody) => [TableRow.t()],
          optional(:tableHeader) => TableRow.t()
        }
  defp transform_examples_table_node(ast_node) do
    [header | body] = get_table_rows(ast_node)
    reject_nils(%{tableBody: body, tableHeader: header})
  end

  @spec transform_feature_node(AST.Node.t()) ::
          %{
            optional(:children) => list,
            optional(:description) => String.t(),
            optional(:keyword) => String.t(),
            optional(:language) => String.t(),
            optional(:location) => Location.t(),
            optional(:name) => String.t(),
            optional(:tags) => [Tag.t()],
            required(:type) => :Feature
          }
          | nil
  defp transform_feature_node(ast_node) do
    if feature_header_node = AST.Node.get_child(ast_node, :Feature_Header) do
      if token = AST.Node.get_item(feature_header_node, :FeatureLine) do
        scenario = AST.Node.get_children(ast_node, :Scenario_Definition)

        children =
          if background_node = AST.Node.get_child(ast_node, :Background) do
            [background_node | scenario]
          else
            scenario
          end

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

  @spec transform_gherkin_document_node(AST.Node.t()) :: %{
          optional(:comments) => [comment],
          optional(:feature) => AST.Node.t(),
          required(:type) => :GherkinDocument
        }
  defp transform_gherkin_document_node(ast_node),
    do:
      reject_nils(%{
        comments: Agent.get(__MODULE__, & &1.comments),
        feature: AST.Node.get_child(ast_node, :Feature),
        type: :GherkinDocument
      })

  @spec transform_scenario_definition_node(AST.Node.t()) :: %{
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

    if scenario_node = AST.Node.get_child(ast_node, :Scenario) do
      token = AST.Node.get_item(scenario_node, :ScenarioLine)

      reject_nils(%{
        description: get_description(scenario_node),
        keyword: token.matched_keyword,
        location: get_location(token),
        name: token.matched_text,
        steps: get_steps(scenario_node),
        tags: tags,
        type: AST.Node.rule_type(scenario_node)
      })
    else
      scenario_outline_node = AST.Node.get_child(ast_node, :ScenarioOutline)

      if !scenario_outline_node do
        raise "Internal grammar error"
      end

      token = AST.Node.get_item(scenario_outline_node, :ScenarioOutlineLine)
      examples = AST.Node.get_children(scenario_outline_node, :Examples_Definition)

      reject_nils(%{
        description: get_description(scenario_outline_node),
        examples: examples,
        keyword: token.matched_keyword,
        location: get_location(token),
        name: token.matched_text,
        steps: get_steps(scenario_outline_node),
        tags: tags,
        type: AST.Node.rule_type(scenario_outline_node)
      })
    end
  end

  @spec transform_step_node(AST.Node.t()) :: %{
          required(:type) => :Step,
          optional(:argument) => term,
          optional(:keyword) => String.t(),
          optional(:location) => Location.t(),
          optional(:text) => String.t()
        }
  defp transform_step_node(ast_node) do
    argument =
      AST.Node.get_child(ast_node, :DataTable) || AST.Node.get_child(ast_node, :DocString)

    token = AST.Node.get_item(ast_node, :StepLine)

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

  @spec get_result :: AST.Node.t()
  def get_result,
    do:
      Agent.get(__MODULE__, fn %{stack: [current_node | _]} ->
        AST.Node.get_child(current_node, :GherkinDocument)
      end)

  @spec reset :: :ok
  def reset,
    do:
      Agent.update(__MODULE__, fn state ->
        for ast_node <- state.stack, do: AST.Node.stop(ast_node)
        initialize()
      end)

  @spec start_link :: :ok | {:error, :already_started | term}
  def start_link do
    case Agent.start_link(&initialize/0, name: __MODULE__) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> {:error, :already_started}
      {:error, error} -> {:error, error}
    end
  end

  @spec initialize :: %{comments: [comment], stack: [AST.Node.t()]}
  defp initialize do
    {:ok, ast_node} = AST.Node.start_link(:None)
    %{comments: [], stack: [ast_node]}
  end

  @spec start_rule(rule_type) :: :ok
  def start_rule(rule_type) when is_atom(rule_type),
    do:
      Agent.update(__MODULE__, fn state ->
        {:ok, ast_node} = AST.Node.start_link(rule_type)
        %{state | stack: [ast_node | state.stack]}
      end)
end
