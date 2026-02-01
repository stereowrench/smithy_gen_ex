defmodule SmithyGen.Writer do
  @moduledoc """
  Handles writing generated code to files.

  This module is responsible for:
  - Creating directories
  - Writing files with proper formatting
  - Handling file conflicts
  - Formatting Elixir code
  """

  require Logger

  @type file_spec :: %{
          path: String.t(),
          content: String.t(),
          format: boolean()
        }

  @doc """
  Writes a list of file specifications to disk.

  ## Options

    * `:output_dir` - Base output directory (default: "lib")
    * `:force` - Overwrite existing files without prompting (default: false)
    * `:quiet` - Suppress output messages (default: false)

  ## Examples

      iex> files = [%{path: "lib/my_app/types/user.ex", content: "defmodule ...", format: true}]
      iex> SmithyGen.Writer.write_files(files)
      {:ok, 1}

  """
  @spec write_files([file_spec()], keyword()) :: {:ok, integer()} | {:error, term()}
  def write_files(file_specs, opts \\\\ []) do
    quiet = Keyword.get(opts, :quiet, false)
    force = Keyword.get(opts, :force, false)

    results =
      file_specs
      |> Enum.map(fn spec ->
        write_file(spec, force: force, quiet: quiet)
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      success_count = Enum.count(results, &match?(:ok, &1))
      {:ok, success_count}
    else
      {:error, {:write_errors, errors}}
    end
  end

  @doc """
  Writes a single file to disk.

  ## Options

    * `:force` - Overwrite without prompting (default: false)
    * `:quiet` - Suppress output messages (default: false)

  ## Examples

      iex> SmithyGen.Writer.write_file(%{path: "lib/user.ex", content: "...", format: true})
      :ok

  """
  @spec write_file(file_spec(), keyword()) :: :ok | {:error, term()}
  def write_file(%{path: path, content: content, format: format?}, opts \\\\ []) do
    quiet = Keyword.get(opts, :quiet, false)
    force = Keyword.get(opts, :force, false)

    # Ensure directory exists
    path
    |> Path.dirname()
    |> File.mkdir_p()

    # Check if file exists
    exists? = File.exists?(path)

    if exists? and not force do
      unless quiet, do: Logger.warning("File exists: #{path}. Use --force to overwrite.")
      :ok
    else
      # Format content if requested
      formatted_content =
        if format? do
          format_elixir_code(content)
        else
          content
        end

      case File.write(path, formatted_content) do
        :ok ->
          unless quiet, do: log_file_action(path, exists?)
          :ok

        {:error, reason} ->
          {:error, {:file_write_error, path, reason}}
      end
    end
  end

  @doc """
  Formats Elixir code using the built-in formatter.

  ## Examples

      iex> SmithyGen.Writer.format_elixir_code("defmodule   User  do end")
      "defmodule User do\\nend\\n"

  """
  @spec format_elixir_code(String.t()) :: String.t()
  def format_elixir_code(code) do
    try do
      code
      |> Code.format_string!()
      |> IO.iodata_to_binary()
    rescue
      error ->
        Logger.warning("Failed to format code: #{inspect(error)}")
        code
    end
  end

  @doc """
  Creates a file specification for a generated file.

  ## Examples

      iex> SmithyGen.Writer.file_spec("lib/user.ex", "defmodule User do end")
      %{path: "lib/user.ex", content: "defmodule User do end", format: true}

  """
  @spec file_spec(String.t(), String.t(), keyword()) :: file_spec()
  def file_spec(path, content, opts \\\\ []) do
    %{
      path: path,
      content: content,
      format: Keyword.get(opts, :format, true)
    }
  end

  @doc """
  Generates a module path from a module name.

  ## Examples

      iex> SmithyGen.Writer.module_to_path(MyApp.Generated.Types.User, "lib")
      "lib/my_app/generated/types/user.ex"

  """
  @spec module_to_path(module(), String.t()) :: String.t()
  def module_to_path(module_name, base_dir) when is_atom(module_name) do
    module_name
    |> Module.split()
    |> Enum.map(&Macro.underscore/1)
    |> then(fn parts ->
      filename = List.last(parts) <> ".ex"
      dir_parts = Enum.slice(parts, 0..-2//1)
      Path.join([base_dir | dir_parts] ++ [filename])
    end)
  end

  @doc """
  Creates a backup of an existing file before overwriting.

  ## Examples

      iex> SmithyGen.Writer.backup_file("lib/user.ex")
      :ok

  """
  @spec backup_file(String.t()) :: :ok | {:error, term()}
  def backup_file(path) do
    if File.exists?(path) do
      backup_path = path <> ".backup"
      File.copy(path, backup_path)
      Logger.info("Created backup: #{backup_path}")
      :ok
    else
      :ok
    end
  end

  # Private functions

  defp log_file_action(path, existed?) do
    action = if existed?, do: "Updated", else: "Created"
    Logger.info("#{action} #{path}")
  end
end
