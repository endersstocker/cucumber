defmodule Gherkin.Builder do
  alias Gherkin.{ASTNode, Token}

  @type t :: struct

  @callback build(t, Token.t()) :: t
  @callback end_rule(t, ASTNode.rule_type()) :: t
  @callback get_result(t) :: term
  @callback start_rule(t, ASTNode.rule_type()) :: t
end
