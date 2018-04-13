defmodule Gherkin.PickleCompiler do
  alias Gherkin.{Location, Pickle, TableCell, TableRow, Tag}

  @type child :: %{
          required(:steps) => [step],
          required(:type) => atom,
          optional(:examples) => [example],
          optional(:location) => Location.t(),
          optional(:name) => String.t(),
          optional(:tags) => [Tag.t()]
        }
  @type example :: %{
          tableBody: [TableRow.t()],
          tableHeader: TableRow.t(),
          tags: [Tag.t()]
        }
  @type feature :: %{children: [child], language: String.t(), tags: [Tag.t()]}
  @type gherkin_document :: %{feature: feature | nil, type: :GherkinDocument}
  @type step :: %{argument: %{type: atom}, text: String.t()}

  @typep compile :: %{background_steps: [Pickle.step()], pickles: [Pickle.t()]}

  @spec compile(gherkin_document) :: [Pickle.t()]
  def compile(%{feature: nil, type: :GherkinDocument}), do: []

  def compile(%{
        feature: %{children: children, language: language, tags: tags},
        type: :GherkinDocument
      }) do
    %{pickles: pickles} =
      Enum.reduce(children, %{background_steps: [], pickles: []}, fn
        %{type: :Background} = child, compile -> put_background(compile, child)
        %{type: :Scenario} = child, compile -> put_scenario(compile, child, language, tags)
        child, compile -> put_scenario_outline(compile, child, language, tags)
      end)

    :lists.reverse(pickles)
  end

  @spec put_background(compile, child) :: compile
  defp put_background(compile, child),
    do: %{compile | background_steps: Enum.map(child.steps, &pickle_step/1)}

  @spec put_scenario(compile, child, String.t(), [Tag.t()]) :: compile
  defp put_scenario(compile, child, language, feature_tags) do
    pickle_steps =
      if Enum.any?(child.steps),
        do: compile.background_steps ++ Enum.map(child.steps, &pickle_step/1),
        else: []

    pickle = %Pickle{
      language: language,
      locations: [child.location],
      name: child.name,
      steps: pickle_steps,
      tags: feature_tags ++ child.tags
    }

    Map.update(compile, :pickles, &[pickle | compile])
  end

  @spec pickle_step(step) :: Pickle.step()
  defp pickle_step(step),
    do: %{
      arguments: create_pickle_arguments(step.argument, [], []),
      locations: [pickle_step_location(step)],
      text: step.text
    }

  @spec put_scenario_outline(compile, child, String.t(), [Tag.t()]) :: compile
  defp put_scenario_outline(compile, child, language, feature_tags),
    do:
      child
      |> Map.fetch!(:examples)
      |> Stream.filter(& &1.tableHeader)
      |> Enum.reduce(
        compile,
        &put_scenario_outline(&2, child, language, feature_tags, &1)
      )

  @spec put_scenario_outline(compile, child, String.t(), [Tag.t()], example) :: compile
  defp put_scenario_outline(compile, child, language, feature_tags, example),
    do:
      Enum.reduce(
        example.tableBody,
        compile,
        &put_scenario_outline(&2, child, language, feature_tags, example, &1)
      )

  @spec put_scenario_outline(compile, child, String.t(), [Tag.t()], example, TableRow.t()) ::
          compile
  defp put_scenario_outline(compile, child, language, feature_tags, example, row) do
    pickle_steps =
      if Enum.any?(child.steps),
        do:
          compile.background_steps ++
            Enum.map(
              child.steps,
              &pickle_step(&1, row.location, example.tableHeader.cells, row.cells)
            ),
        else: []

    pickle = %Pickle{
      language: language,
      locations: [row.location, child.location],
      name: interpolate(child.name, example.tableHeader.cells, row.cells),
      steps: pickle_steps,
      tags: feature_tags ++ child.tags ++ example.tags
    }

    Map.update(compile, :pickles, &[pickle | compile])
  end

  @spec pickle_step(step, Location.t(), [TableCell.t()], [TableCell.t()]) :: Pickle.step()
  defp pickle_step(step, location, variable_cells, value_cells),
    do: %{
      arguments: create_pickle_arguments(step.argument, variable_cells, value_cells),
      locations: [location, pickle_step_location(step)],
      text: interpolate(step.text, variable_cells, value_cells)
    }

  @spec pickle_step_location(step) :: Location.t()
  defp pickle_step_location(step) do
    offset = if step.keyword, do: byte_size(step.keyword), else: 0
    %Location{column: step.location + offset, line: step.location.line}
  end

  @spec create_pickle_arguments(%{type: atom} | nil, [TableCell.t()], [
          TableCell.t()
        ]) :: [Pickle.argument()] | no_return
  defp create_pickle_arguments(nil, _variable_cells, _value_cells), do: []

  defp create_pickle_arguments(%{type: :DataTable}, variable_cells, value_cells),
    do: [%{rows: Enum.map(argument.rows, &interpolate(&1, variable_cells, value_cells))}]

  defp create_pickle_arguments(%{type: :DocString}, variable_cells, value_cells),
    do: [
      %{
        content: interpolate(argument.content, variable_cells, value_cells),
        location: argument.location
      }
    ]

  defp create_pickle_arguments(_argument, _variable_cells, _value_cells) do
    raise "Internal error"
  end

  @spec interpolate(TableRow.t(), [TableCell.t()], [TableCell.t()]) :: TableRow.t()
  @spec interpolate(TableCell.t(), [TableCell.t()], [TableCell.t()]) :: TableCell.t()
  @spec interpolate(String.t(), [TableCell.t()], [TableCell.t()]) :: String.t()
  defp interpolate(%{type: :TableRow} = row, variable_cells, value_cells),
    do: %{row | cells: Enum.map(row.cells, &interpolate(&1, variable_cells, value_cells))}

  defp interpolate(%{type: :TableCell} = cell, variable_cells, value_cells),
    do: %{cell | value: interpolate(cell.value, variable_cells, value_cells)}

  defp interpolate(name, variable_cells, value_cells) when is_binary(name),
    do:
      variable_cells
      |> Stream.zip(value_cells)
      |> Enum.reduce(name, fn {variable_cell, value_cell}, acc ->
        String.replace(acc, "<#{variable_cell.value}>", value_cell.value)
      end)
end
