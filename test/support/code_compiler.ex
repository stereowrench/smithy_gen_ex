defmodule SmithyGen.Test.CodeCompiler do
  @moduledoc """
  Utilities for compiling and validating generated code in tests.
  """

  @doc """
  Validates that a string of Elixir code has correct syntax.
  Uses Code.format_string!/1 which requires valid syntax.
  """
  def validate_syntax(code) do
    Code.format_string!(code)
    :ok
  rescue
    error -> {:error, {:syntax_error, error}}
  end

  @doc """
  Compiles a string of Elixir code in-memory.
  Returns {:ok, [{module, binary}]} or {:error, reason}.

  Only works if all referenced modules are available in the test VM.
  """
  def compile_string(code) do
    modules = Code.compile_string(code)
    {:ok, modules}
  rescue
    error -> {:error, error}
  end

  @doc """
  Compiles code and returns the first module name.
  """
  def compile_and_load(code) do
    case compile_string(code) do
      {:ok, [{module, _binary} | _]} -> {:ok, module}
      {:ok, []} -> {:error, :no_modules}
      error -> error
    end
  end

  @doc """
  Purges a module from the VM. Use in test cleanup.
  """
  def purge_module(module) when is_atom(module) do
    :code.purge(module)
    :code.delete(module)
    :ok
  end
end
