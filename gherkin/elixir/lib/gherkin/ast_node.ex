defmodule Gherkin.ASTNode do
  @type rule_type ::
          :Background
          | :DataTable
          | :Description
          | :DocString
          | :Examples
          | :Examples_Definition
          | :Examples_Table
          | :Feature
          | :Feature_Header
          | :GherkinDocument
          | :None
          | :Scenario
          | :Scenario_Definitions
          | :ScenarioOutline
          | :Step
          | :Tags
  @type t :: %__MODULE__{children: %{optional(rule_type) => list}, rule_type: rule_type}

  @enforce_keys [:rule_type]
  defstruct @enforce_keys ++ [children: %{}]

  @spec add_child(t, rule_type, term) :: t
  def add_child(%__MODULE__{} = ast_node, rule_type, child) when is_atom(rule_type),
    do:
      Map.update!(ast_node, :children, fn children ->
        Map.update(children, rule_type, [child], &List.insert_at(&1, -1, child))
      end)

  @spec get_children(t, rule_type) :: list
  def get_children(%__MODULE__{} = ast_node, rule_type) when is_atom(rule_type),
    do: Map.get(ast_node.children, rule_type, [])

  @spec get_single(t, rule_type) :: term | nil
  def get_single(%__MODULE__{} = ast_node, rule_type) when is_atom(rule_type) do
    if list = ast_node.children[rule_type], do: hd(list)
  end
end
