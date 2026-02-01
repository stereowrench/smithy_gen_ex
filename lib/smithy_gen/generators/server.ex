defmodule SmithyGen.Generators.Server do
  @moduledoc """
  Generates Phoenix server code from Smithy services.

  This generator creates:
  - Behaviour modules defining operation callbacks
  - Phoenix controllers that delegate to behaviours
  - Router macros for Phoenix integration

  Uses EEx templates for generation.
  """

  alias SmithyGen.IR.{Model, Service}
  alias SmithyGen.Writer

  require Logger
  require EEx

  # Compile templates at build time
  EEx.function_from_file(
    :defp,
    :render_behaviour,
    Path.expand("../../../priv/templates/server/behaviour.ex.eex", __DIR__),
    [:assigns]
  )

  EEx.function_from_file(
    :defp,
    :render_controller,
    Path.expand("../../../priv/templates/server/controller.ex.eex", __DIR__),
    [:assigns]
  )

  EEx.function_from_file(
    :defp,
    :render_router,
    Path.expand("../../../priv/templates/server/router.ex.eex", __DIR__),
    [:assigns]
  )

  @doc """
  Generates server code from an IR model.

  Returns a list of file specifications to be written.

  ## Options

    * `:base_module` - Base module name (e.g., MyApp.Generated)
    * `:output_dir` - Output directory (default: "lib")
    * `:app_name` - Application name (e.g., :my_app)

  ## Examples

      iex> SmithyGen.Generators.Server.generate(model, base_module: MyApp.Generated, app_name: :my_app)
      [%{path: "lib/my_app/generated/server/...", content: "...", format: true}]

  """
  @spec generate(Model.t(), keyword()) :: [Writer.file_spec()]
  def generate(%Model{service: nil}, _opts), do: []

  def generate(%Model{service: service} = model, opts) do
    base_module = Keyword.fetch!(opts, :base_module)
    app_name = Keyword.fetch!(opts, :app_name)
    output_dir = Keyword.get(opts, :output_dir, "lib")

    [
      generate_behaviour(service, base_module, output_dir),
      generate_controller(service, base_module, app_name, output_dir, model),
      generate_router(service, base_module, output_dir)
    ]
  end

  # Private functions

  defp generate_behaviour(service, base_module, output_dir) do
    module_name = Module.concat([base_module, "Server", "Behaviours", "#{service.name}Behaviour"])

    assigns = %{
      module_name: module_name,
      service_name: service.name,
      documentation: service.documentation,
      operations: service.operations
    }

    code = render_behaviour(assigns)

    path = Writer.module_to_path(module_name, output_dir)

    Writer.file_spec(path, code, format: true)
  end

  defp generate_controller(service, base_module, app_name, output_dir, model) do
    module_name = Module.concat([base_module, "Server", "Controllers", "#{service.name}Controller"])
    behaviour_module = Module.concat([base_module, "Server", "Behaviours", "#{service.name}Behaviour"])

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
      behaviour_module: behaviour_module,
      type_modules: type_modules,
      app_name: app_name,
      operations: service.operations
    }

    code = render_controller(assigns)

    path = Writer.module_to_path(module_name, output_dir)

    Writer.file_spec(path, code, format: true)
  end

  defp generate_router(service, base_module, output_dir) do
    module_name = Module.concat([base_module, "Server", "#{service.name}Router"])
    controller_module = Module.concat([base_module, "Server", "Controllers", "#{service.name}Controller"])

    assigns = %{
      module_name: module_name,
      service_name: service.name,
      controller_module: controller_module,
      operations: service.operations
    }

    code = render_router(assigns)

    path = Writer.module_to_path(module_name, output_dir)

    Writer.file_spec(path, code, format: true)
  end
end
