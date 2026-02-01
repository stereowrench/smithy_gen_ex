defmodule SmithyGen.Generators.ClientTest do
  use ExUnit.Case, async: true

  alias SmithyGen.Generators.Client
  alias SmithyGen.Test.{IRBuilder, CodeCompiler}

  @opts [base_module: TestClient.Generated, app_name: :test_client]

  describe "generate/2" do
    test "returns empty list when model has no service" do
      model = IRBuilder.model(service: nil)
      assert [] = Client.generate(model, @opts)
    end

    test "generates one client module per service" do
      service = IRBuilder.service("UserService", [
        IRBuilder.operation("GetUser", http: IRBuilder.http_binding("GET", "/users"))
      ])

      model = IRBuilder.model(service: service)
      assert [_spec] = Client.generate(model, @opts)
    end

    test "generates correct module name" do
      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("GetPost", http: IRBuilder.http_binding("GET", "/posts"))
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "defmodule Elixir.TestClient.Generated.Client.BlogServiceClient"
    end

    test "generates correct file path" do
      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("GetPost", http: IRBuilder.http_binding("GET", "/posts"))
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.path =~ "blog_service_client.ex"
    end
  end

  describe "operation function generation" do
    test "generates a function per operation" do
      service = IRBuilder.service("UserService", [
        IRBuilder.operation("CreateUser", http: IRBuilder.http_binding("POST", "/users")),
        IRBuilder.operation("GetUser", http: IRBuilder.http_binding("GET", "/users/{id}")),
        IRBuilder.operation("DeleteUser", http: IRBuilder.http_binding("DELETE", "/users/{id}"))
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "def create_user("
      assert spec.content =~ "def get_user("
      assert spec.content =~ "def delete_user("
    end

    test "includes input parameter when operation has input shape" do
      input = IRBuilder.shape("CreateUserInput", :structure)

      service = IRBuilder.service("UserService", [
        IRBuilder.operation("CreateUser",
          http: IRBuilder.http_binding("POST", "/users"),
          input: input
        )
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "def create_user(input,"
    end

    test "omits input parameter when no input shape" do
      service = IRBuilder.service("UserService", [
        IRBuilder.operation("ListUsers", http: IRBuilder.http_binding("GET", "/users"))
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "def list_users(opts \\\\"
    end
  end

  describe "HTTP method mapping" do
    test "maps GET to :get" do
      assert_http_method("GET", ":get")
    end

    test "maps POST to :post" do
      assert_http_method("POST", ":post")
    end

    test "maps PUT to :put" do
      assert_http_method("PUT", ":put")
    end

    test "maps DELETE to :delete" do
      assert_http_method("DELETE", ":delete")
    end

    test "maps PATCH to :patch" do
      assert_http_method("PATCH", ":patch")
    end
  end

  describe "request construction" do
    test "includes JSON content-type headers" do
      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("POST", "/"))
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ ~s("content-type", "application/json")
      assert spec.content =~ ~s("accept", "application/json")
    end

    test "encodes input to JSON when input exists" do
      input = IRBuilder.shape("OpInput", :structure)

      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Op",
          http: IRBuilder.http_binding("POST", "/"),
          input: input
        )
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "Jason.encode!(input)"
    end

    test "uses empty body when no input" do
      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("GET", "/"))
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ ~s(body = "")
    end

    test "includes path parameter substitution for operations with path params" do
      input = IRBuilder.shape("GetInput", :structure)

      service = IRBuilder.service("Svc", [
        IRBuilder.operation("GetItem",
          http: IRBuilder.http_binding("GET", "/items/{id}", path_params: ["id"]),
          input: input
        )
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "build_url"
      assert spec.content =~ "{id}"
    end
  end

  describe "response handling" do
    test "includes JSON decoding for operations with output" do
      output = IRBuilder.shape("OpOutput", :structure)

      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Op",
          http: IRBuilder.http_binding("GET", "/"),
          output: output
        )
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "Jason.decode(response_body)"
    end

    test "includes changeset validation for output" do
      output = IRBuilder.shape("OpOutput", :structure)

      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Op",
          http: IRBuilder.http_binding("GET", "/"),
          output: output
        )
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "changeset"
      assert spec.content =~ "Ecto.Changeset.apply_changes"
    end

    test "matches expected status code" do
      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Create",
          http: IRBuilder.http_binding("POST", "/", code: 201)
        )
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "status_code: 201"
    end

    test "includes error handling for non-matching status" do
      service = IRBuilder.service("Svc", [
        IRBuilder.operation("Op", http: IRBuilder.http_binding("GET", "/"))
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ ":http_error"
      assert spec.content =~ ":request_error"
    end
  end

  describe "documentation" do
    test "includes service documentation in moduledoc" do
      service = IRBuilder.service("Svc", [], documentation: "My service docs")
      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "My service docs"
    end

    test "includes operation documentation" do
      service = IRBuilder.service("Svc", [
        IRBuilder.operation("GetUser",
          http: IRBuilder.http_binding("GET", "/users"),
          documentation: "Retrieves a user by ID"
        )
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "Retrieves a user by ID"
    end

    test "includes type aliases for referenced types" do
      input = IRBuilder.shape("GetUserInput", :structure)
      output = IRBuilder.shape("GetUserOutput", :structure)

      service = IRBuilder.service("Svc", [
        IRBuilder.operation("GetUser",
          http: IRBuilder.http_binding("GET", "/users"),
          input: input,
          output: output
        )
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert spec.content =~ "alias Elixir.TestClient.Generated.Types.GetUserInput"
      assert spec.content =~ "alias Elixir.TestClient.Generated.Types.GetUserOutput"
    end
  end

  describe "syntax validation" do
    test "generated code has valid Elixir syntax" do
      input = IRBuilder.shape("CreatePostInput", :structure)
      output = IRBuilder.shape("CreatePostOutput", :structure)

      service = IRBuilder.service("BlogService", [
        IRBuilder.operation("CreatePost",
          http: IRBuilder.http_binding("POST", "/posts", code: 201),
          input: input,
          output: output
        ),
        IRBuilder.operation("GetPost",
          http: IRBuilder.http_binding("GET", "/posts/{id}", path_params: ["id"]),
          input: IRBuilder.shape("GetPostInput", :structure),
          output: IRBuilder.shape("GetPostOutput", :structure)
        ),
        IRBuilder.operation("ListPosts",
          http: IRBuilder.http_binding("GET", "/posts")
        )
      ])

      model = IRBuilder.model(service: service)
      [spec] = Client.generate(model, @opts)

      assert :ok = CodeCompiler.validate_syntax(spec.content)
    end
  end

  # Helper
  defp assert_http_method(smithy_method, expected_atom) do
    service = IRBuilder.service("Svc", [
      IRBuilder.operation("Op", http: IRBuilder.http_binding(smithy_method, "/"))
    ])

    model = IRBuilder.model(service: service)
    [spec] = Client.generate(model, @opts)

    assert spec.content =~ "HTTPoison.request(#{expected_atom}"
  end
end
