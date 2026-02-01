defmodule SmithyGen.Generators.ServerTest do
  use ExUnit.Case, async: true

  alias SmithyGen.Generators.Server
  alias SmithyGen.Test.{IRBuilder, CodeCompiler}

  @opts [base_module: TestServer.Generated, app_name: :test_server]

  describe "generate/2" do
    test "returns empty list when model has no service" do
      model = IRBuilder.model(service: nil)
      assert [] = Server.generate(model, @opts)
    end

    test "generates three files: behaviour, controller, router" do
      service = IRBuilder.service("UserService", [
        IRBuilder.operation("GetUser", http: IRBuilder.http_binding("GET", "/users"))
      ])

      model = IRBuilder.model(service: service)
      specs = Server.generate(model, @opts)

      assert length(specs) == 3

      paths = Enum.map(specs, & &1.path)
      assert Enum.any?(paths, &(&1 =~ "behaviour"))
      assert Enum.any?(paths, &(&1 =~ "controller"))
      assert Enum.any?(paths, &(&1 =~ "router"))
    end
  end

  describe "behaviour generation" do
    test "generates @callback for each operation" do
      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("CreatePost", http: IRBuilder.http_binding("POST", "/posts")),
        IRBuilder.operation("GetPost", http: IRBuilder.http_binding("GET", "/posts/{id}"))
      ])

      model = IRBuilder.model(service: service)
      [behaviour | _] = Server.generate(model, @opts)

      assert behaviour.content =~ "@callback create_post("
      assert behaviour.content =~ "@callback get_post("
    end

    test "callback includes input type in spec" do
      input = IRBuilder.shape("CreatePostInput", :structure)

      service = IRBuilder.service("Svc", [
        IRBuilder.operation("CreatePost",
          http: IRBuilder.http_binding("POST", "/posts"),
          input: input
        )
      ])

      model = IRBuilder.model(service: service)
      [behaviour | _] = Server.generate(model, @opts)

      assert behaviour.content =~ "CreatePostInput.t()"
    end

    test "callback includes output type in return spec" do
      output = IRBuilder.shape("CreatePostOutput", :structure)

      service = IRBuilder.service("Svc", [
        IRBuilder.operation("CreatePost",
          http: IRBuilder.http_binding("POST", "/posts"),
          output: output
        )
      ])

      model = IRBuilder.model(service: service)
      [behaviour | _] = Server.generate(model, @opts)

      assert behaviour.content =~ "CreatePostOutput.t()"
    end

    test "generates correct module name" do
      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("GET", "/"))
      ])

      model = IRBuilder.model(service: service)
      [behaviour | _] = Server.generate(model, @opts)

      assert behaviour.content =~ "Elixir.TestServer.Generated.Server.Behaviours.BlogServiceBehaviour"
    end

    test "includes service documentation" do
      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("GET", "/"))
      ], documentation: "My service")

      model = IRBuilder.model(service: service)
      [behaviour | _] = Server.generate(model, @opts)

      assert behaviour.content =~ "My service"
    end
  end

  describe "controller generation" do
    test "generates action function for each operation" do
      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("CreatePost", http: IRBuilder.http_binding("POST", "/posts")),
        IRBuilder.operation("GetPost", http: IRBuilder.http_binding("GET", "/posts/{id}"))
      ])

      model = IRBuilder.model(service: service)
      [_, controller, _] = Server.generate(model, @opts)

      assert controller.content =~ "def create_post(conn,"
      assert controller.content =~ "def get_post(conn,"
    end

    test "uses Phoenix.Controller" do
      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("GET", "/"))
      ])

      model = IRBuilder.model(service: service)
      [_, controller, _] = Server.generate(model, @opts)

      assert controller.content =~ "use Phoenix.Controller"
    end

    test "sets correct HTTP status code in response" do
      service = IRBuilder.service("Svc", [
        IRBuilder.operation("CreatePost",
          http: IRBuilder.http_binding("POST", "/posts", code: 201)
        )
      ])

      model = IRBuilder.model(service: service)
      [_, controller, _] = Server.generate(model, @opts)

      assert controller.content =~ "put_status(201)"
    end

    test "includes error handling for validation errors" do
      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("GET", "/"))
      ])

      model = IRBuilder.model(service: service)
      [_, controller, _] = Server.generate(model, @opts)

      assert controller.content =~ "Ecto.Changeset"
      assert controller.content =~ ":unprocessable_entity"
    end

    test "includes error handling for runtime errors" do
      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("GET", "/"))
      ])

      model = IRBuilder.model(service: service)
      [_, controller, _] = Server.generate(model, @opts)

      assert controller.content =~ ":internal_server_error"
    end

    test "generates correct module name" do
      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("GET", "/"))
      ])

      model = IRBuilder.model(service: service)
      [_, controller, _] = Server.generate(model, @opts)

      assert controller.content =~ "Elixir.TestServer.Generated.Server.Controllers.BlogServiceController"
    end

    test "aliases type modules" do
      input = IRBuilder.shape("OpInput", :structure)
      output = IRBuilder.shape("OpOutput", :structure)

      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Op",
          http: IRBuilder.http_binding("GET", "/"),
          input: input,
          output: output
        )
      ])

      model = IRBuilder.model(service: service)
      [_, controller, _] = Server.generate(model, @opts)

      assert controller.content =~ "alias Elixir.TestServer.Generated.Types.OpInput"
      assert controller.content =~ "alias Elixir.TestServer.Generated.Types.OpOutput"
    end
  end

  describe "router generation" do
    test "generates route for each operation with correct HTTP method" do
      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("CreatePost", http: IRBuilder.http_binding("POST", "/posts")),
        IRBuilder.operation("GetPost", http: IRBuilder.http_binding("GET", "/posts/{id}")),
        IRBuilder.operation("DeletePost", http: IRBuilder.http_binding("DELETE", "/posts/{id}"))
      ])

      model = IRBuilder.model(service: service)
      [_, _, router] = Server.generate(model, @opts)

      assert router.content =~ ~s(post "/posts")
      assert router.content =~ ~s(get "/posts/{id}")
      assert router.content =~ ~s(delete "/posts/{id}")
    end

    test "generates macro for route inclusion" do
      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("GET", "/"))
      ])

      model = IRBuilder.model(service: service)
      [_, _, router] = Server.generate(model, @opts)

      assert router.content =~ "defmacro blog_service_routes"
    end

    test "references correct controller module" do
      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("GET", "/"))
      ])

      model = IRBuilder.model(service: service)
      [_, _, router] = Server.generate(model, @opts)

      assert router.content =~ "Elixir.TestServer.Generated.Server.Controllers.BlogServiceController"
    end

    test "maps operation names to controller actions" do
      service = IRBuilder.service("Svc", [
        IRBuilder.operation("CreatePost", http: IRBuilder.http_binding("POST", "/posts"))
      ])

      model = IRBuilder.model(service: service)
      [_, _, router] = Server.generate(model, @opts)

      assert router.content =~ ":create_post"
    end

    test "generates correct module name" do
      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("GET", "/"))
      ])

      model = IRBuilder.model(service: service)
      [_, _, router] = Server.generate(model, @opts)

      assert router.content =~ "Elixir.TestServer.Generated.Server.BlogServiceRouter"
    end
  end

  describe "syntax validation" do
    test "all generated files have valid Elixir syntax" do
      input = IRBuilder.shape("CreateInput", :structure)
      output = IRBuilder.shape("CreateOutput", :structure)

      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("CreatePost",
          http: IRBuilder.http_binding("POST", "/posts", code: 201),
          input: input,
          output: output
        ),
        IRBuilder.operation("GetPost",
          http: IRBuilder.http_binding("GET", "/posts/{id}", path_params: ["id"]),
          input: IRBuilder.shape("GetInput", :structure),
          output: IRBuilder.shape("GetOutput", :structure)
        ),
        IRBuilder.operation("ListPosts",
          http: IRBuilder.http_binding("GET", "/posts")
        )
      ])

      model = IRBuilder.model(service: service)
      specs = Server.generate(model, @opts)

      Enum.each(specs, fn spec ->
        assert :ok = CodeCompiler.validate_syntax(spec.content),
               "Invalid syntax in #{spec.path}"
      end)
    end
  end
end
