# SmithyGen

**Smithy code generator for Elixir** - Generate type-safe Phoenix server and HTTP client code from [Smithy IDL](https://smithy.io/) definitions.

## Features

- ✅ **Type-Safe Code Generation**: Generates Ecto embedded schemas with full typespecs
- ✅ **Automatic Validation**: Enforces Smithy constraints (@required, @length, @range, @pattern)
- ✅ **Phoenix Integration**: Generates controllers that delegate to behaviour callbacks
- ✅ **HTTP Client**: Generates client modules for calling services
- ✅ **REST Protocol Support**: Full restJson1 protocol implementation
- ✅ **Documentation**: Preserves Smithy documentation as ExDoc comments
- ✅ **Convention-Based**: Follows Elixir and Phoenix best practices

## Installation

Add `smithy_gen` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:smithy_gen, "~> 0.1.0"},
    {:ecto, "~> 3.11"},              # Required for schemas
    {:phoenix, "~> 1.7"},             # Required for server generation
    {:httpoison, "~> 2.0"},           # Required for client generation
    {:jason, "~> 1.4"}                # Required for JSON serialization
  ]
end
```

## Quick Start

### 1. Create Smithy Files

Create a Smithy service definition in `priv/smithy/service.smithy`:

```smithy
$version: "2.0"

namespace com.example.blog

@restJson1
service BlogService {
    version: "2024-01-01"
    operations: [CreatePost, GetPost]
}

@http(method: "POST", uri: "/posts", code: 201)
operation CreatePost {
    input := CreatePostInput
    output := CreatePostOutput
}

structure CreatePostInput {
    @required
    @length(min: 1, max: 200)
    title: String

    @required
    content: String
}

structure CreatePostOutput {
    @required
    post: Post
}

structure Post {
    @required
    id: String

    @required
    title: String
}
```

### 2. Generate Code

Run the generator:

```bash
mix smithy.gen
```

This generates:

```
lib/my_app/generated/
├── types/
│   ├── create_post_input.ex
│   ├── create_post_output.ex
│   └── post.ex
├── server/
│   ├── behaviours/
│   │   └── blog_service_behaviour.ex
│   ├── controllers/
│   │   └── blog_service_controller.ex
│   └── blog_service_router.ex
└── client/
    └── blog_service_client.ex
```

### 3. Implement Server Behaviour

Create your business logic by implementing the generated behaviour:

```elixir
defmodule MyApp.BlogServiceImpl do
  @behaviour MyApp.Generated.Server.Behaviours.BlogServiceBehaviour

  alias MyApp.Generated.Types.{CreatePostInput, CreatePostOutput, Post}

  @impl true
  def create_post(%CreatePostInput{} = input) do
    post = %Post{
      id: generate_id(),
      title: input.title,
      content: input.content
    }

    {:ok, %CreatePostOutput{post: post}}
  end
end
```

### 4. Add Routes to Phoenix Router

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import MyApp.Generated.Server.BlogServiceRouter

  scope "/api" do
    blog_service_routes()
  end
end
```

### 5. Configure Behaviour Implementation

Add to `config/config.exs`:

```elixir
config :my_app,
  smithy_behaviour_impl: MyApp.BlogServiceImpl
```

### 6. Use the Generated Client

```elixir
alias MyApp.Generated.Client.BlogServiceClient
alias MyApp.Generated.Types.CreatePostInput

input = %CreatePostInput{
  title: "Hello Smithy",
  content: "Generated code is great!"
}

{:ok, output} = BlogServiceClient.create_post(input)
IO.inspect(output.post)
```

## CLI Options

```bash
# Generate both client and server
mix smithy.gen

# Generate only server code
mix smithy.gen --server-only

# Generate only client code
mix smithy.gen --client-only

# Custom base module
mix smithy.gen --base-module MyApp.API

# Custom output directory
mix smithy.gen --output-dir lib/api

# Custom Smithy directory
mix smithy.gen --smithy-dir priv/models

# Force overwrite existing files
mix smithy.gen --force
```

## Supported Smithy Features (MVP)

### Types
- ✅ Structures
- ✅ Primitives (String, Integer, Long, Boolean, Float, Double, Timestamp, Blob)
- ✅ Lists
- ✅ Maps
- ✅ Unions (tagged/discriminated unions)

### HTTP Bindings
- ✅ @http (method, uri, code)
- ✅ @httpLabel (path parameters)
- ✅ @httpQuery (query parameters)
- ✅ @httpHeader (header parameters)
- ✅ @httpPayload (body binding)

### Validation Traits
- ✅ @required
- ✅ @length (min/max string/list/map length)
- ✅ @range (min/max numeric values)
- ✅ @pattern (regex validation)

### Protocols
- ✅ restJson1 (AWS REST + JSON)

## Roadmap (Phase 2)

- 🔜 Error handling (@error trait, FallbackController)
- 🔜 Enums (@enum trait)
- 🔜 Pagination (@paginated trait)
- 🔜 Authentication (@auth traits, Plug generation)
- 🔜 Streaming (@streaming trait)
- 🔜 Resource lifecycle operations
- 🔜 Additional protocols (awsJson1_0, awsJson1_1, restXml)
- 🔜 Custom trait support

## Architecture

SmithyGen follows a **pragmatic balanced architecture**:

1. **Parser**: Parses Smithy IDL or JSON AST
2. **IR (Intermediate Representation)**: Normalized model
3. **Generators**:
   - Types: AST-based (using `quote/unquote`)
   - Server/Client: Template-based (using EEx)
4. **Writer**: File management with automatic formatting

## Example

See `priv/smithy/example.smithy` for a complete blog service example with:
- Multiple operations (Create, Get, List)
- HTTP bindings
- Validation traits
- Documentation

Generate it with:

```bash
cd smithy_gen
mix deps.get
mix smithy.gen
```

Then explore the generated code in `lib/smithy_gen/generated/`!

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

Apache 2.0

## Resources

- [Smithy Specification](https://smithy.io/2.0/)
- [Phoenix Framework](https://www.phoenixframework.org/)
- [Ecto Documentation](https://hexdocs.pm/ecto)

