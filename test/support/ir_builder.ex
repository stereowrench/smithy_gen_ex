defmodule SmithyGen.Test.IRBuilder do
  @moduledoc """
  Helper functions to build IR structs for testing.
  """

  alias SmithyGen.IR.{Model, Service, Operation, Shape, Member, HttpBinding}

  def model(opts \\ []) do
    %Model{
      namespace: Keyword.get(opts, :namespace, "test"),
      shapes: Keyword.get(opts, :shapes, %{}),
      service: Keyword.get(opts, :service),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  def shape(name, type, opts \\ []) do
    %Shape{
      name: name,
      type: type,
      members: Keyword.get(opts, :members, %{}),
      target: Keyword.get(opts, :target),
      enum_values: Keyword.get(opts, :enum_values),
      traits: Keyword.get(opts, :traits, %{}),
      documentation: Keyword.get(opts, :documentation)
    }
  end

  def member(name, target, opts \\ []) do
    %Member{
      name: name,
      target: target,
      http_binding: Keyword.get(opts, :http_binding),
      traits: Keyword.get(opts, :traits, %{}),
      documentation: Keyword.get(opts, :documentation)
    }
  end

  def operation(name, opts \\ []) do
    %Operation{
      name: name,
      http: Keyword.get(opts, :http, http_binding("POST", "/")),
      input: Keyword.get(opts, :input),
      output: Keyword.get(opts, :output),
      errors: Keyword.get(opts, :errors, []),
      traits: Keyword.get(opts, :traits, %{}),
      documentation: Keyword.get(opts, :documentation)
    }
  end

  def http_binding(method, uri, opts \\ []) do
    %HttpBinding{
      method: method,
      uri: uri,
      code: Keyword.get(opts, :code, 200),
      path_params: Keyword.get(opts, :path_params, []),
      query_params: Keyword.get(opts, :query_params, []),
      header_params: Keyword.get(opts, :header_params, [])
    }
  end

  def service(name, operations, opts \\ []) do
    %Service{
      name: name,
      version: Keyword.get(opts, :version, "1.0"),
      namespace: Keyword.get(opts, :namespace, "test"),
      operations: operations,
      protocol: Keyword.get(opts, :protocol, :restJson1),
      errors: Keyword.get(opts, :errors, []),
      traits: Keyword.get(opts, :traits, %{}),
      documentation: Keyword.get(opts, :documentation)
    }
  end
end
