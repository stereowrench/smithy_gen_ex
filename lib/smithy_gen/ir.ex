defmodule SmithyGen.IR do
  @moduledoc """
  Intermediate Representation for Smithy models.

  This module defines the core data structures that represent a parsed Smithy model.
  The IR is the normalized form that all generators consume.
  """

  alias SmithyGen.IR.{Service, Operation, Shape, Member, HttpBinding, Trait}

  defmodule Model do
    @moduledoc """
    Represents a complete Smithy model.
    """

    @enforce_keys [:namespace, :shapes, :service]
    @type t :: %__MODULE__{
            namespace: String.t(),
            shapes: %{String.t() => Shape.t()},
            service: Service.t() | nil,
            metadata: map()
          }

    defstruct [:namespace, :shapes, :service, metadata: %{}]
  end

  defmodule Service do
    @moduledoc """
    Represents a Smithy service definition.
    """

    @enforce_keys [:name, :version, :operations]
    @type t :: %__MODULE__{
            name: String.t(),
            version: String.t(),
            namespace: String.t(),
            operations: [Operation.t()],
            protocol: atom(),
            errors: [String.t()],
            traits: %{String.t() => term()},
            documentation: String.t() | nil,
            metadata: map()
          }

    defstruct [
      :name,
      :version,
      :namespace,
      :operations,
      :protocol,
      :documentation,
      errors: [],
      traits: %{},
      metadata: %{}
    ]
  end

  defmodule Operation do
    @moduledoc """
    Represents a Smithy operation (API endpoint).
    """

    @enforce_keys [:name, :http]
    @type t :: %__MODULE__{
            name: String.t(),
            input: Shape.t() | nil,
            output: Shape.t() | nil,
            errors: [Shape.t()],
            http: HttpBinding.t(),
            auth: map() | nil,
            pagination: map() | nil,
            documentation: String.t() | nil,
            traits: %{String.t() => term()},
            metadata: map()
          }

    defstruct [
      :name,
      :input,
      :output,
      :http,
      :auth,
      :pagination,
      :documentation,
      errors: [],
      traits: %{},
      metadata: %{}
    ]
  end

  defmodule Shape do
    @moduledoc """
    Represents a Smithy shape (type definition).
    """

    @enforce_keys [:name, :type]
    @type shape_type ::
            :structure
            | :union
            | :list
            | :map
            | :string
            | :integer
            | :long
            | :short
            | :byte
            | :float
            | :double
            | :boolean
            | :timestamp
            | :blob
            | :enum

    @type t :: %__MODULE__{
            name: String.t(),
            type: shape_type(),
            members: %{String.t() => Member.t()},
            target: String.t() | nil,
            enum_values: [String.t()] | nil,
            traits: %{String.t() => term()},
            documentation: String.t() | nil,
            metadata: map()
          }

    defstruct [
      :name,
      :type,
      :target,
      :enum_values,
      :documentation,
      members: %{},
      traits: %{},
      metadata: %{}
    ]
  end

  defmodule Member do
    @moduledoc """
    Represents a member of a structure or union.
    """

    @type t :: %__MODULE__{
            name: String.t(),
            target: String.t(),
            http_binding: :path | :query | :header | :body | nil,
            traits: %{String.t() => term()},
            documentation: String.t() | nil
          }

    defstruct [:name, :target, :http_binding, :documentation, traits: %{}]
  end

  defmodule HttpBinding do
    @moduledoc """
    Represents HTTP binding information for an operation.
    """

    @enforce_keys [:method, :uri]
    @type t :: %__MODULE__{
            method: String.t(),
            uri: String.t(),
            code: integer(),
            path_params: [String.t()],
            query_params: [String.t()],
            header_params: [String.t()]
          }

    defstruct [:method, :uri, code: 200, path_params: [], query_params: [], header_params: []]
  end

  defmodule Trait do
    @moduledoc """
    Represents a Smithy trait annotation.
    """

    @type t :: %__MODULE__{
            name: String.t(),
            value: term()
          }

    defstruct [:name, :value]
  end

  @doc """
  Creates a new IR Model from parsed Smithy AST.

  ## Examples

      iex> SmithyGen.IR.from_ast(%{"shapes" => %{}, "metadata" => %{}})
      {:ok, %SmithyGen.IR.Model{}}

  """
  @spec from_ast(map()) :: {:ok, Model.t()} | {:error, term()}
  def from_ast(ast) do
    with {:ok, namespace} <- extract_namespace(ast),
         {:ok, shapes} <- build_shapes(ast),
         {:ok, service} <- build_service(ast, shapes) do
      model = %Model{
        namespace: namespace,
        shapes: shapes,
        service: service,
        metadata: Map.get(ast, "metadata", %{})
      }

      {:ok, model}
    end
  end

  # Private helper functions

  defp extract_namespace(%{"metadata" => %{"namespace" => namespace}}), do: {:ok, namespace}

  defp extract_namespace(%{"shapes" => shapes}) when map_size(shapes) > 0 do
    # Extract namespace from first shape ID (format: "namespace#ShapeName")
    case shapes |> Map.keys() |> List.first() do
      nil ->
        {:error, :no_shapes}

      shape_id ->
        case String.split(shape_id, "#") do
          [namespace, _] -> {:ok, namespace}
          _ -> {:error, {:invalid_shape_id, shape_id}}
        end
    end
  end

  defp extract_namespace(_), do: {:error, :namespace_not_found}

  defp build_shapes(%{"shapes" => shapes_map}) do
    shapes =
      shapes_map
      |> Enum.map(fn {shape_id, shape_data} ->
        {shape_id, build_shape(shape_id, shape_data)}
      end)
      |> Enum.into(%{})

    {:ok, shapes}
  end

  defp build_shapes(_), do: {:ok, %{}}

  defp build_shape(shape_id, shape_data) do
    shape_name = extract_shape_name(shape_id)
    shape_type = String.to_atom(shape_data["type"] || "structure")

    %Shape{
      name: shape_name,
      type: shape_type,
      members: build_members(Map.get(shape_data, "members", %{})),
      target: shape_data["target"],
      enum_values: shape_data["enum"],
      traits: extract_traits(shape_data),
      documentation: get_documentation(shape_data),
      metadata: %{}
    }
  end

  defp build_members(members_map) when is_map(members_map) do
    members_map
    |> Enum.map(fn {member_name, member_data} ->
      {member_name,
       %Member{
         name: member_name,
         target: member_data["target"],
         http_binding: parse_http_binding(member_data),
         traits: extract_traits(member_data),
         documentation: get_documentation(member_data)
       }}
    end)
    |> Enum.into(%{})
  end

  defp build_members(_), do: %{}

  defp build_service(%{"shapes" => shapes}, _shapes_map) do
    service_shape =
      shapes
      |> Enum.find(fn {_id, data} -> data["type"] == "service" end)

    case service_shape do
      {service_id, service_data} ->
        operations = build_operations(service_data, shapes)

        service = %Service{
          name: extract_shape_name(service_id),
          version: service_data["version"] || "1.0",
          namespace: extract_namespace_from_id(service_id),
          operations: operations,
          protocol: detect_protocol(service_data),
          errors: service_data["errors"] || [],
          traits: extract_traits(service_data),
          documentation: get_documentation(service_data)
        }

        {:ok, service}

      nil ->
        {:ok, nil}
    end
  end

  defp build_service(_, _), do: {:ok, nil}

  defp build_operations(service_data, shapes) do
    operation_ids = service_data["operations"] || []

    operation_ids
    |> Enum.map(fn op_id ->
      case Map.get(shapes, op_id) do
        nil ->
          nil

        op_data ->
          build_operation(op_id, op_data, shapes)
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_operation(op_id, op_data, shapes) do
    %Operation{
      name: extract_shape_name(op_id),
      input: resolve_shape(op_data["input"], shapes),
      output: resolve_shape(op_data["output"], shapes),
      errors: resolve_shapes(op_data["errors"] || [], shapes),
      http: build_http_binding(op_data),
      traits: extract_traits(op_data),
      documentation: get_documentation(op_data)
    }
  end

  defp build_http_binding(op_data) do
    http_trait = get_in(op_data, ["traits", "smithy.api#http"]) || %{}

    uri = http_trait["uri"] || "/"
    path_params = extract_path_params(uri)

    %HttpBinding{
      method: http_trait["method"] || "POST",
      uri: uri,
      code: http_trait["code"] || 200,
      path_params: path_params,
      query_params: [],
      header_params: []
    }
  end

  defp resolve_shape(nil, _shapes), do: nil

  defp resolve_shape(shape_id, shapes) do
    Map.get(shapes, shape_id) |> then(&build_shape(shape_id, &1 || %{}))
  end

  defp resolve_shapes(shape_ids, shapes) when is_list(shape_ids) do
    Enum.map(shape_ids, &resolve_shape(&1, shapes))
  end

  defp extract_traits(%{"traits" => traits}) when is_map(traits), do: traits
  defp extract_traits(_), do: %{}

  defp get_documentation(data) do
    get_in(data, ["traits", "smithy.api#documentation"])
  end

  defp extract_shape_name(shape_id) do
    case String.split(shape_id, "#") do
      [_namespace, name] -> name
      [name] -> name
    end
  end

  defp extract_namespace_from_id(shape_id) do
    case String.split(shape_id, "#") do
      [namespace, _] -> namespace
      _ -> ""
    end
  end

  defp parse_http_binding(%{"traits" => traits}) do
    cond do
      Map.has_key?(traits, "smithy.api#httpLabel") -> :path
      Map.has_key?(traits, "smithy.api#httpQuery") -> :query
      Map.has_key?(traits, "smithy.api#httpHeader") -> :header
      Map.has_key?(traits, "smithy.api#httpPayload") -> :body
      true -> nil
    end
  end

  defp parse_http_binding(_), do: nil

  defp extract_path_params(uri) do
    Regex.scan(~r/\{([^}]+)\}/, uri)
    |> Enum.map(fn [_, param] -> String.trim_trailing(param, "+") end)
  end

  defp detect_protocol(%{"traits" => traits}) do
    cond do
      Map.has_key?(traits, "aws.protocols#restJson1") -> :restJson1
      Map.has_key?(traits, "aws.protocols#awsJson1_0") -> :awsJson1_0
      Map.has_key?(traits, "aws.protocols#awsJson1_1") -> :awsJson1_1
      true -> :restJson1
    end
  end

  defp detect_protocol(_), do: :restJson1
end
