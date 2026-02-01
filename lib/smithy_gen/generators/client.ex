defmodule SmithyGen.Generators.Client do
  @moduledoc """
  Generates HTTP client code from Smithy services.

  This generator creates client modules that can call service operations
  over HTTP using the configured protocol (e.g., restJson1).

  Uses EEx templates for generation.
  """

  alias SmithyGen.IR.{Model, Service}
  alias SmithyGen.Writer

  require Logger
  require EEx

  # Compile template at build time
  EEx.function_from_file(
    :defp,
    :render_client,
    Path.expand("../../../priv/templates/client/client.ex.eex", __DIR__),
    [:assigns]
  )

  @doc """
  Generates client code from an IR model.

  Returns a list of file specifications to be written.

  ## Options

    * `:base_module` - Base module name (e.g., MyApp.Generated)
    * `:output_dir` - Output directory (default: "lib")
    * `:app_name` - Application name (e.g., :my_app)

  ## Examples

      iex> SmithyGen.Generators.Client.generate(model, base_module: MyApp.Generated, app_name: :my_app)
      [%{path: "lib/my_app/generated/client/...", content: "...", format: true}]

  """
  @spec generate(Model.t(), keyword()) :: [Writer.file_spec()]
  def generate(%Model{service: nil}, _opts), do: []

  def generate(%Model{service: service} = model, opts) do
    base_module = Keyword.fetch!(opts, :base_module)
    app_name = Keyword.fetch!(opts, :app_name)
    output_dir = Keyword.get(opts, :output_dir, "lib")

    [generate_client_module(service, base_module, app_name, output_dir, model)]
  end

  # Private functions

  defp generate_client_module(service, base_module, app_name, output_dir, model) do
    module_name = Module.concat([base_module, "Client", "#{service.name}Client"])

    # Collect all type modules referenced by operations
    type_modules =
      service.operations
      |> Enum.flat_map(fn op ->
        [op.input, op.output]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn shape ->
          Module.concat([base_module, "Types", shape.name])
        end)
      end)
      |> Enum.uniq()

    assigns = %{
      module_name: module_name,
      service_name: service.name,
      documentation: service.documentation,
      app_name: app_name,
      type_modules: type_modules,
      operations: service.operations
    }

    code = render_client(assigns)

    path = Writer.module_to_path(module_name, output_dir)

    Writer.file_spec(path, code, format: true)
  end
end
