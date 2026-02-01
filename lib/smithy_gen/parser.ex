defmodule SmithyGen.Parser do
  @moduledoc """
  Parser for Smithy IDL files.

  This module handles parsing Smithy models into a format that can be consumed
  by the IR builder. It supports:

  1. Smithy JSON AST (output from Smithy CLI)
  2. Simple Smithy IDL files (basic subset for MVP)

  For production use, it's recommended to use the Smithy CLI to generate JSON AST:
  ```
  smithy build --output model.json
  ```

  Then parse the JSON with this module.
  """

  require Logger

  @doc """
  Parses Smithy files from a directory.

  Discovers all `.smithy` files in the given directory and parses them.

  ## Options

    * `:use_smithy_cli` - If true, uses Smithy CLI to parse files (default: false)
    * `:smithy_cli_path` - Path to Smithy CLI jar (default: "priv/smithy-cli.jar")

  ## Examples

      iex> SmithyGen.Parser.parse_directory("priv/smithy")
      {:ok, %{}}

  """
  @spec parse_directory(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse_directory(directory, opts \\\\ []) do
    use_cli = Keyword.get(opts, :use_smithy_cli, false)

    cond do
      use_cli ->
        parse_with_cli(directory, opts)

      true ->
        parse_smithy_files(directory)
    end
  end

  @doc """
  Parses a single Smithy file.

  ## Examples

      iex> SmithyGen.Parser.parse_file("service.smithy")
      {:ok, %{}}

  """
  @spec parse_file(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_file(filepath) do
    case File.read(filepath) do
      {:ok, content} ->
        parse_smithy_content(content, Path.basename(filepath))

      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Parses Smithy JSON AST.

  This is the preferred method when using Smithy CLI.

  ## Examples

      iex> SmithyGen.Parser.parse_json(~s({"smithy": "2.0", "shapes": {}}))
      {:ok, %{}}

  """
  @spec parse_json(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_json(json_content) do
    case Jason.decode(json_content) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  # Private functions

  defp parse_with_cli(directory, opts) do
    cli_path = Keyword.get(opts, :smithy_cli_path, "priv/smithy-cli.jar")

    unless File.exists?(cli_path) do
      Logger.warning("Smithy CLI not found at #{cli_path}. Falling back to simple parser.")
      return parse_smithy_files(directory)
    end

    temp_output = Path.join(System.tmp_dir!(), "smithy_output_#{:rand.uniform(10000)}.json")

    try do
      # Run Smithy CLI to generate JSON model
      {output, exit_code} =
        System.cmd("java", ["-jar", cli_path, "build", directory, "--output", temp_output])

      if exit_code != 0 do
        {:error, {:smithy_cli_error, output}}
      else
        case File.read(temp_output) do
          {:ok, json} -> parse_json(json)
          error -> error
        end
      end
    after
      File.rm(temp_output)
    end
  end

  defp parse_smithy_files(directory) do
    smithy_files =
      Path.wildcard(Path.join([directory, "**", "*.smithy"]))

    if Enum.empty?(smithy_files) do
      {:error, {:no_smithy_files, directory}}
    else
      results =
        smithy_files
        |> Enum.map(&parse_file/1)

      errors = Enum.filter(results, &match?({:error, _}, &1))

      if Enum.empty?(errors) do
        # Merge all parsed models
        merged =
          results
          |> Enum.map(fn {:ok, model} -> model end)
          |> merge_models()

        {:ok, merged}
      else
        {:error, {:parse_errors, errors}}
      end
    end
  end

  defp parse_smithy_content(content, filename) do
    # Simple parser for basic Smithy syntax
    # This is a minimal implementation for MVP
    # Production should use Smithy CLI

    try do
      ast = %{
        "smithy" => "2.0",
        "shapes" => %{},
        "metadata" => %{}
      }

      # Extract namespace
      namespace = extract_namespace_from_content(content)

      # Parse shapes
      shapes = parse_shapes_from_content(content, namespace)

      ast =
        ast
        |> Map.put("shapes", shapes)
        |> put_in(["metadata", "namespace"], namespace)

      {:ok, ast}
    rescue
      error ->
        Logger.error("Failed to parse #{filename}: #{inspect(error)}")
        {:error, {:parse_error, error}}
    end
  end

  defp extract_namespace_from_content(content) do
    case Regex.run(~r/namespace\s+([\w\.]+)/, content) do
      [_, namespace] -> namespace
      _ -> "unknown"
    end
  end

  defp parse_shapes_from_content(content, namespace) do
    # This is a simplified parser for MVP
    # It handles basic structures, operations, and services

    shapes = %{}

    # Parse service
    shapes = parse_service(content, namespace, shapes)

    # Parse structures
    shapes = parse_structures(content, namespace, shapes)

    # Parse operations
    shapes = parse_operations(content, namespace, shapes)

    shapes
  end

  defp parse_service(content, namespace, shapes) do
    service_regex = ~r/@(\w+)\([^)]*\)\s*service\s+(\w+)\s*\{([^}]+)\}/

    case Regex.run(service_regex, content) do
      [_, _trait, service_name, body] ->
        shape_id = "#{namespace}##{service_name}"

        service_shape = %{
          "type" => "service",
          "version" => extract_version(body),
          "operations" => extract_operations_list(body, namespace),
          "traits" => parse_traits(content, service_name)
        }

        Map.put(shapes, shape_id, service_shape)

      _ ->
        shapes
    end
  end

  defp parse_structures(content, namespace, shapes) do
    structure_regex = ~r/structure\s+(\w+)\s*\{([^}]+)\}/

    Regex.scan(structure_regex, content)
    |> Enum.reduce(shapes, fn [_, struct_name, body], acc ->
      shape_id = "#{namespace}##{struct_name}"

      members = parse_members(body, namespace)

      struct_shape = %{
        "type" => "structure",
        "members" => members,
        "traits" => %{}
      }

      Map.put(acc, shape_id, struct_shape)
    end)
  end

  defp parse_operations(content, namespace, shapes) do
    operation_regex = ~r/@http\(([^)]+)\)\s*operation\s+(\w+)\s*\{([^}]+)\}/

    Regex.scan(operation_regex, content)
    |> Enum.reduce(shapes, fn [_, http_config, op_name, body], acc ->
      shape_id = "#{namespace}##{op_name}"

      http_trait = parse_http_trait(http_config)

      operation_shape = %{
        "type" => "operation",
        "input" => extract_input(body, namespace),
        "output" => extract_output(body, namespace),
        "errors" => [],
        "traits" => %{"smithy.api#http" => http_trait}
      }

      Map.put(acc, shape_id, operation_shape)
    end)
  end

  defp parse_members(body, namespace) do
    member_regex = ~r/(\w+):\s*(\w+)/

    Regex.scan(member_regex, body)
    |> Enum.reduce(%{}, fn [_, member_name, type_name], acc ->
      target = resolve_type_target(type_name, namespace)

      Map.put(acc, member_name, %{
        "target" => target,
        "traits" => parse_member_traits(body, member_name)
      })
    end)
  end

  defp parse_member_traits(body, member_name) do
    # Check for @required trait
    if String.contains?(body, "@required") and String.contains?(body, member_name) do
      %{"smithy.api#required" => %{}}
    else
      %{}
    end
  end

  defp parse_http_trait(http_config) do
    method_match = Regex.run(~r/method:\s*"(\w+)"/, http_config)
    uri_match = Regex.run(~r/uri:\s*"([^"]+)"/, http_config)
    code_match = Regex.run(~r/code:\s*(\d+)/, http_config)

    %{
      "method" => if(method_match, do: Enum.at(method_match, 1), else: "POST"),
      "uri" => if(uri_match, do: Enum.at(uri_match, 1), else: "/"),
      "code" => if(code_match, do: String.to_integer(Enum.at(code_match, 1)), else: 200)
    }
  end

  defp parse_traits(content, shape_name) do
    # Extract @restJson1 or other protocol traits
    if String.contains?(content, "@restJson1") and String.contains?(content, shape_name) do
      %{"aws.protocols#restJson1" => %{}}
    else
      %{}
    end
  end

  defp extract_version(body) do
    case Regex.run(~r/version:\s*"([^"]+)"/, body) do
      [_, version] -> version
      _ -> "1.0"
    end
  end

  defp extract_operations_list(body, namespace) do
    case Regex.run(~r/operations:\s*\[([^\]]+)\]/, body) do
      [_, ops_string] ->
        ops_string
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn op -> "#{namespace}##{op}" end)

      _ ->
        []
    end
  end

  defp extract_input(body, namespace) do
    case Regex.run(~r/input\s*:=\s*(\w+)/, body) do
      [_, input_name] -> "#{namespace}##{input_name}"
      _ -> nil
    end
  end

  defp extract_output(body, namespace) do
    case Regex.run(~r/output\s*:=\s*(\w+)/, body) do
      [_, output_name] -> "#{namespace}##{output_name}"
      _ -> nil
    end
  end

  defp resolve_type_target(type_name, namespace) do
    # Built-in types
    builtin_types = ["String", "Integer", "Long", "Boolean", "Float", "Double", "Timestamp"]

    if type_name in builtin_types do
      "smithy.api##{type_name}"
    else
      "#{namespace}##{type_name}"
    end
  end

  defp merge_models(models) do
    Enum.reduce(models, %{"smithy" => "2.0", "shapes" => %{}, "metadata" => %{}}, fn model, acc ->
      %{
        "smithy" => "2.0",
        "shapes" => Map.merge(acc["shapes"], model["shapes"] || %{}),
        "metadata" => Map.merge(acc["metadata"], model["metadata"] || %{})
      }
    end)
  end
end
