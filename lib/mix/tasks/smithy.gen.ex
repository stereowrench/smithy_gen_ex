defmodule Mix.Tasks.Smithy.Gen do
  @moduledoc """
  Generates Elixir code from Smithy IDL files.

  This task discovers Smithy files in `priv/smithy/`, parses them, and generates:
  - Ecto embedded schemas for types
  - Phoenix controllers and behaviours for server code
  - HTTP client modules for client code

  ## Usage

      mix smithy.gen [OPTIONS]

  ## Options

    * `--client-only` - Generate only client code
    * `--server-only` - Generate only server code
    * `--base-module MODULE` - Base module name (default: inferred from mix.exs)
    * `--output-dir DIR` - Output directory (default: "lib")
    * `--smithy-dir DIR` - Smithy files directory (default: "priv/smithy")
    * `--force` - Overwrite existing files without prompting

  ## Examples

      # Generate both client and server code
      mix smithy.gen

      # Generate only client code
      mix smithy.gen --client-only

      # Specify custom base module
      mix smithy.gen --base-module MyApp.API

  """

  use Mix.Task

  alias SmithyGen.{Parser, IR, Writer}
  alias SmithyGen.Generators.{Types, Server, Client}

  require Logger

  @shortdoc "Generates Elixir code from Smithy IDL files"

  @impl Mix.Task
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          client_only: :boolean,
          server_only: :boolean,
          base_module: :string,
          output_dir: :string,
          smithy_dir: :string,
          force: :boolean
        ]
      )

    Mix.shell().info("Starting Smithy code generation...")

    config = build_config(opts)

    with {:ok, ast} <- parse_smithy_files(config.smithy_dir),
         {:ok, model} <- build_ir(ast),
         {:ok, file_specs} <- generate_code(model, config),
         {:ok, count} <- write_files(file_specs, config) do
      Mix.shell().info("\nSuccessfully generated #{count} files!")
      Mix.shell().info("\nNext steps:")
      Mix.shell().info("  1. Add `{:httpoison, \"~> 2.0\"}` to your dependencies for HTTP client")
      Mix.shell().info("  2. Implement the behaviour module(s) for server functionality")
      Mix.shell().info("  3. Add generated routes to your Phoenix router")
    else
      {:error, reason} ->
        Mix.shell().error("Generation failed: #{inspect(reason)}")
        Mix.raise("Smithy code generation failed")
    end
  end

  # Private functions

  defp build_config(opts) do
    app_name = Mix.Project.config()[:app]
    base_module = infer_base_module(opts[:base_module], app_name)

    %{
      app_name: app_name,
      base_module: base_module,
      output_dir: opts[:output_dir] || "lib",
      smithy_dir: opts[:smithy_dir] || "priv/smithy",
      generate_client: !opts[:server_only],
      generate_server: !opts[:client_only],
      force: opts[:force] || false
    }
  end

  defp infer_base_module(nil, app_name) do
    app_name
    |> to_string()
    |> Macro.camelize()
    |> then(&Module.concat([&1, "Generated"]))
  end

  defp infer_base_module(module_string, _app_name) do
    Module.concat([module_string])
  end

  defp parse_smithy_files(smithy_dir) do
    Mix.shell().info("Parsing Smithy files from #{smithy_dir}...")

    unless File.dir?(smithy_dir) do
      Mix.shell().error("Smithy directory not found: #{smithy_dir}")
      Mix.shell().info("Creating directory #{smithy_dir}...")
      File.mkdir_p!(smithy_dir)

      Mix.shell().info("\nPlease add your Smithy IDL files to #{smithy_dir}")
      Mix.shell().info("Example structure:")
      Mix.shell().info("  #{smithy_dir}/")
      Mix.shell().info("    service.smithy")
      Mix.shell().info("    types.smithy")

      {:error, :no_smithy_files}
    else
      Parser.parse_directory(smithy_dir)
    end
  end

  defp build_ir(ast) do
    Mix.shell().info("Building intermediate representation...")
    IR.from_ast(ast)
  end

  defp generate_code(model, config) do
    Mix.shell().info("Generating code...")

    generator_opts = [
      base_module: config.base_module,
      output_dir: config.output_dir,
      app_name: config.app_name
    ]

    file_specs = []

    # Always generate types
    Mix.shell().info("  - Generating types...")
    type_specs = Types.generate(model, generator_opts)
    file_specs = file_specs ++ type_specs

    # Generate server code if requested
    file_specs =
      if config.generate_server do
        Mix.shell().info("  - Generating server code...")
        server_specs = Server.generate(model, generator_opts)
        file_specs ++ server_specs
      else
        file_specs
      end

    # Generate client code if requested
    file_specs =
      if config.generate_client do
        Mix.shell().info("  - Generating client code...")
        client_specs = Client.generate(model, generator_opts)
        file_specs ++ client_specs
      else
        file_specs
      end

    {:ok, file_specs}
  end

  defp write_files(file_specs, config) do
    Mix.shell().info("Writing files...")

    Writer.write_files(file_specs, force: config.force, quiet: false)
  end
end
