defmodule SmithyGen.Generators.Types do
  @moduledoc """
  Generates Ecto embedded schemas from Smithy shapes.

  This generator creates type-safe Elixir modules with:
  - Ecto embedded schemas for structures
  - Typespecs
  - Changeset functions with validation
  - Documentation from Smithy traits

  Uses AST generation (quote/unquote) for type safety.
  """

  alias SmithyGen.IR.{Model, Shape, Member}
  alias SmithyGen.Writer

  require Logger

  @doc """
  Generates type modules from an IR model.

  Returns a list of file specifications to be written.

  ## Options

    * `:base_module` - Base module name (e.g., MyApp.Generated)
    * `:output_dir` - Output directory (default: "lib")

  ## Examples

      iex> SmithyGen.Generators.Types.generate(model, base_module: MyApp.Generated)
      [%{path: "lib/my_app/generated/types/user.ex", content: "...", format: true}]

  """
  @spec generate(Model.t(), keyword()) :: [Writer.file_spec()]
  def generate(%Model{} = model, opts \\\\ []) do
    base_module = Keyword.fetch!(opts, :base_module)
    output_dir = Keyword.get(opts, :output_dir, "lib")

    model.shapes
    |> Enum.filter(fn {_id, shape} -> shape.type == :structure end)
    |> Enum.map(fn {_id, shape} ->
      generate_structure(shape, base_module, output_dir, model)
    end)
  end

  # Private functions

  defp generate_structure(shape, base_module, output_dir, model) do
    module_name = Module.concat([base_module, "Types", shape.name])

    code = generate_structure_code(shape, module_name, model)

    path = Writer.module_to_path(module_name, output_dir)

    Writer.file_spec(path, code, format: true)
  end

  defp generate_structure_code(shape, module_name, model) do
    module_ast =
      quote do
        defmodule unquote(module_name) do
          @moduledoc unquote(generate_moduledoc(shape))

          use Ecto.Schema
          import Ecto.Changeset

          @type t :: %__MODULE__{
                  unquote_splicing(generate_typespec_fields(shape, model))
                }

          @primary_key false
          embedded_schema do
            unquote_splicing(generate_schema_fields(shape, model))
          end

          @doc """
          Creates a changeset for validation.

          ## Examples

              iex> #{inspect(module_name)}.changeset(%#{inspect(module_name)}{}, %{})
              %Ecto.Changeset{}

          """
          def changeset(struct \\\\ %__MODULE__{}, params) do
            struct
            |> cast(params, unquote(get_field_names(shape)))
            |> unquote_splicing(generate_validations(shape))
          end
        end
      end

    module_ast
    |> Macro.to_string()
  end

  defp generate_moduledoc(shape) do
    doc = shape.documentation || "Represents a #{shape.name}."
    doc <> "\n\nGenerated from Smithy shape."
  end

  defp generate_typespec_fields(shape, model) do
    shape.members
    |> Enum.map(fn {field_name, member} ->
      field_atom = String.to_atom(field_name)
      elixir_type = map_smithy_type_to_elixir(member, model)

      is_required = Map.has_key?(member.traits, "smithy.api#required")

      type_ast =
        if is_required do
          elixir_type
        else
          quote do: unquote(elixir_type) | nil
        end

      {field_atom, type_ast}
    end)
  end

  defp generate_schema_fields(shape, model) do
    shape.members
    |> Enum.map(fn {field_name, member} ->
      field_atom = String.to_atom(field_name)
      ecto_type = map_smithy_type_to_ecto(member, model)

      quote do
        field(unquote(field_atom), unquote(ecto_type))
      end
    end)
  end

  defp generate_validations(shape) do
    validations = []

    # Add validate_required
    required_fields =
      shape.members
      |> Enum.filter(fn {_name, member} ->
        Map.has_key?(member.traits, "smithy.api#required")
      end)
      |> Enum.map(fn {name, _member} -> String.to_atom(name) end)

    validations =
      if Enum.any?(required_fields) do
        [
          quote do
            validate_required(unquote(required_fields))
          end
          | validations
        ]
      else
        validations
      end

    # Add length validation
    validations =
      Enum.reduce(shape.members, validations, fn {field_name, member}, acc ->
        case member.traits["smithy.api#length"] do
          %{"min" => min, "max" => max} ->
            field_atom = String.to_atom(field_name)

            [
              quote do
                validate_length(unquote(field_atom), min: unquote(min), max: unquote(max))
              end
              | acc
            ]

          %{"min" => min} ->
            field_atom = String.to_atom(field_name)

            [
              quote do
                validate_length(unquote(field_atom), min: unquote(min))
              end
              | acc
            ]

          %{"max" => max} ->
            field_atom = String.to_atom(field_name)

            [
              quote do
                validate_length(unquote(field_atom), max: unquote(max))
              end
              | acc
            ]

          _ ->
            acc
        end
      end)

    # Add pattern validation
    validations =
      Enum.reduce(shape.members, validations, fn {field_name, member}, acc ->
        case member.traits["smithy.api#pattern"] do
          pattern when is_binary(pattern) ->
            field_atom = String.to_atom(field_name)
            regex = Regex.compile!(pattern)

            [
              quote do
                validate_format(unquote(field_atom), unquote(Macro.escape(regex)))
              end
              | acc
            ]

          _ ->
            acc
        end
      end)

    # Add range validation
    validations =
      Enum.reduce(shape.members, validations, fn {field_name, member}, acc ->
        case member.traits["smithy.api#range"] do
          %{"min" => min, "max" => max} ->
            field_atom = String.to_atom(field_name)

            [
              quote do
                validate_number(unquote(field_atom),
                  greater_than_or_equal_to: unquote(min),
                  less_than_or_equal_to: unquote(max)
                )
              end
              | acc
            ]

          %{"min" => min} ->
            field_atom = String.to_atom(field_name)

            [
              quote do
                validate_number(unquote(field_atom), greater_than_or_equal_to: unquote(min))
              end
              | acc
            ]

          %{"max" => max} ->
            field_atom = String.to_atom(field_name)

            [
              quote do
                validate_number(unquote(field_atom), less_than_or_equal_to: unquote(max))
              end
              | acc
            ]

          _ ->
            acc
        end
      end)

    validations
  end

  defp get_field_names(shape) do
    shape.members
    |> Map.keys()
    |> Enum.map(&String.to_atom/1)
  end

  defp map_smithy_type_to_elixir(%Member{target: target}, model) do
    case resolve_target_shape(target, model) do
      %Shape{type: :string} -> quote(do: String.t())
      %Shape{type: :integer} -> quote(do: integer())
      %Shape{type: :long} -> quote(do: integer())
      %Shape{type: :short} -> quote(do: integer())
      %Shape{type: :byte} -> quote(do: integer())
      %Shape{type: :float} -> quote(do: float())
      %Shape{type: :double} -> quote(do: float())
      %Shape{type: :boolean} -> quote(do: boolean())
      %Shape{type: :timestamp} -> quote(do: DateTime.t())
      %Shape{type: :blob} -> quote(do: binary())
      %Shape{type: :list} -> quote(do: list())
      %Shape{type: :map} -> quote(do: map())
      %Shape{type: :structure, name: name} -> quote(do: unquote(Module.concat([name, :t])))
      _ -> quote(do: term())
    end
  end

  defp map_smithy_type_to_ecto(%Member{target: target}, model) do
    case resolve_target_shape(target, model) do
      %Shape{type: :string} -> :string
      %Shape{type: :integer} -> :integer
      %Shape{type: :long} -> :integer
      %Shape{type: :short} -> :integer
      %Shape{type: :byte} -> :integer
      %Shape{type: :float} -> :float
      %Shape{type: :double} -> :float
      %Shape{type: :boolean} -> :boolean
      %Shape{type: :timestamp} -> :utc_datetime
      %Shape{type: :blob} -> :binary
      %Shape{type: :list} -> {:array, :string}
      %Shape{type: :map} -> :map
      _ -> :string
    end
  end

  defp resolve_target_shape(target, model) do
    # Handle built-in Smithy types
    case target do
      "smithy.api#String" -> %Shape{name: "String", type: :string}
      "smithy.api#Integer" -> %Shape{name: "Integer", type: :integer}
      "smithy.api#Long" -> %Shape{name: "Long", type: :long}
      "smithy.api#Short" -> %Shape{name: "Short", type: :short}
      "smithy.api#Byte" -> %Shape{name: "Byte", type: :byte}
      "smithy.api#Float" -> %Shape{name: "Float", type: :float}
      "smithy.api#Double" -> %Shape{name: "Double", type: :double}
      "smithy.api#Boolean" -> %Shape{name: "Boolean", type: :boolean}
      "smithy.api#Timestamp" -> %Shape{name: "Timestamp", type: :timestamp}
      "smithy.api#Blob" -> %Shape{name: "Blob", type: :blob}
      _ -> model.shapes[target] || %Shape{name: "Unknown", type: :string}
    end
  end
end
