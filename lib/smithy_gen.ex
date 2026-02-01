defmodule SmithyGen do
  @moduledoc """
  SmithyGen - Smithy code generator for Elixir.

  Generates type-safe Elixir code from Smithy IDL definitions, including:
  - Ecto embedded schemas with validation
  - Phoenix server controllers and behaviours
  - HTTP client modules
  - Complete documentation and typespecs

  ## Quick Start

  1. Add Smithy files to `priv/smithy/`:

      ```
      priv/smithy/
        service.smithy
      ```

  2. Run the generator:

      ```
      mix smithy.gen
      ```

  3. Generated code appears in `lib/your_app/generated/`:

      ```
      lib/your_app/generated/
        types/          # Ecto schemas
        server/         # Phoenix controllers and behaviours
        client/         # HTTP clients
      ```

  ## Features

  - **Type Safety**: Generated Ecto schemas with typespecs
  - **Validation**: Automatic validation from Smithy traits (@required, @length, @range, @pattern)
  - **HTTP Bindings**: Full support for restJson1 protocol
  - **Phoenix Integration**: Controllers delegate to behaviour callbacks
  - **Documentation**: ExDoc-compatible documentation from Smithy docs
  - **Extensible**: Template-based generation with customization hooks

  ## Supported Smithy Features (MVP)

  - Basic types: structures, primitives, lists, maps
  - HTTP bindings: @http, @httpLabel, @httpQuery, @httpHeader, @httpPayload
  - Validation traits: @required, @length, @range, @pattern
  - Unions (tagged/discriminated unions)
  - Protocol: restJson1

  ## Coming Soon

  - Error handling (@error trait)
  - Enums (@enum trait)
  - Pagination (@paginated trait)
  - Authentication (@auth traits)
  - Additional protocols (awsJson1_0, restXml)

  ## Configuration

  Add to your `config/config.exs`:

      config :my_app,
        # For client code
        blog_service_base_url: "http://localhost:4000"

      # For server code
      config :my_app,
        smithy_behaviour_impl: MyApp.BlogServiceImpl

  ## Architecture

  SmithyGen follows a pragmatic balanced architecture:

  - **Parser**: Supports Smithy JSON AST or simple IDL parsing
  - **IR (Intermediate Representation)**: Normalized Smithy model
  - **Generators**: Types (AST-based), Server/Client (template-based)
  - **Writer**: File management with formatting

  ## Examples

  See `priv/smithy/example.smithy` for a complete example service.
  """

  @doc """
  Returns the version of SmithyGen.
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:smithy_gen, :vsn) |> to_string()
  end
end
