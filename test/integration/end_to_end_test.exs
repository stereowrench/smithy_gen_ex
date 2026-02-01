defmodule SmithyGen.Integration.EndToEndTest do
  use ExUnit.Case, async: false

  alias SmithyGen.{Parser, IR, Writer}
  alias SmithyGen.Generators.{Types, Client, Server}
  alias SmithyGen.Test.CodeCompiler

  @example_smithy Path.expand("../../priv/smithy/example.smithy", __DIR__)

  setup do
    temp_dir = Path.join(System.tmp_dir!(), "smithy_e2e_#{:rand.uniform(100_000)}")
    File.mkdir_p!(temp_dir)
    on_exit(fn -> File.rm_rf!(temp_dir) end)
    %{temp_dir: temp_dir}
  end

  describe "full pipeline: parse -> IR -> generate -> write" do
    test "parses example.smithy successfully" do
      assert {:ok, ast} = Parser.parse_file(@example_smithy)
      assert ast["smithy"] == "2.0"
      assert is_map(ast["shapes"])
      assert map_size(ast["shapes"]) > 0
    end

    test "builds IR from parsed AST" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      assert {:ok, model} = IR.from_ast(ast)

      assert model.namespace == "com.example.blog"
      assert model.service.name == "BlogService"
      assert length(model.service.operations) == 3

      op_names = Enum.map(model.service.operations, & &1.name) |> Enum.sort()
      assert op_names == ["CreatePost", "GetPost", "ListPosts"]
    end

    test "generates type modules for all structures" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      type_specs = Types.generate(model, base_module: E2E.Generated)

      type_names =
        type_specs
        |> Enum.map(fn spec -> Path.basename(spec.path, ".ex") end)
        |> Enum.sort()

      assert "create_post_input" in type_names
      assert "create_post_output" in type_names
      assert "get_post_input" in type_names
      assert "get_post_output" in type_names
      assert "list_posts_input" in type_names
      assert "list_posts_output" in type_names
      assert "post" in type_names
    end

    test "generates client module with all operations" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      [client_spec] = Client.generate(model,
        base_module: E2E.Generated,
        app_name: :e2e_test
      )

      assert client_spec.content =~ "def create_post("
      assert client_spec.content =~ "def get_post("
      assert client_spec.content =~ "def list_posts("
    end

    test "generates server modules (behaviour, controller, router)" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      [behaviour, controller, router] = Server.generate(model,
        base_module: E2E.Generated,
        app_name: :e2e_test
      )

      # Behaviour
      assert behaviour.content =~ "@callback create_post("
      assert behaviour.content =~ "@callback get_post("
      assert behaviour.content =~ "@callback list_posts("

      # Controller
      assert controller.content =~ "def create_post(conn,"
      assert controller.content =~ "def get_post(conn,"
      assert controller.content =~ "def list_posts(conn,"

      # Router
      assert router.content =~ ~s(post "/posts")
      assert router.content =~ ~s(get "/posts/{id}")
      assert router.content =~ ~s(get "/posts")
    end

    test "writes all generated files to disk", %{temp_dir: dir} do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      all_specs =
        Types.generate(model, base_module: E2E.Generated, output_dir: dir) ++
        Client.generate(model, base_module: E2E.Generated, app_name: :e2e_test, output_dir: dir) ++
        Server.generate(model, base_module: E2E.Generated, app_name: :e2e_test, output_dir: dir)

      assert {:ok, count} = Writer.write_files(all_specs, force: true, quiet: true)
      assert count == length(all_specs)

      Enum.each(all_specs, fn spec ->
        assert File.exists?(spec.path), "Expected file to exist: #{spec.path}"
      end)
    end
  end

  describe "generated code validity" do
    test "all generated code has valid Elixir syntax" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      all_specs =
        Types.generate(model, base_module: E2E.Generated) ++
        Client.generate(model, base_module: E2E.Generated, app_name: :e2e_test) ++
        Server.generate(model, base_module: E2E.Generated, app_name: :e2e_test)

      Enum.each(all_specs, fn spec ->
        assert :ok = CodeCompiler.validate_syntax(spec.content),
               "Invalid syntax in #{spec.path}"
      end)
    end

    test "generated type modules compile and have working changesets" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      type_specs = Types.generate(model, base_module: E2ECompile.Generated)

      # Compile all type modules
      compiled_modules =
        Enum.map(type_specs, fn spec ->
          assert {:ok, module} = CodeCompiler.compile_and_load(spec.content)
          module
        end)

      on_exit(fn ->
        Enum.each(compiled_modules, &CodeCompiler.purge_module/1)
      end)

      # All type modules should have changeset/2
      Enum.each(compiled_modules, fn module ->
        assert function_exported?(module, :changeset, 2),
               "#{inspect(module)} should have changeset/2"
      end)
    end

    test "CreatePostInput changeset validates required fields" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      type_specs = Types.generate(model, base_module: E2EValidation.Generated)

      create_input_spec =
        Enum.find(type_specs, fn spec -> spec.path =~ "create_post_input.ex" end)

      assert {:ok, module} = CodeCompiler.compile_and_load(create_input_spec.content)
      on_exit(fn -> CodeCompiler.purge_module(module) end)

      # Missing required fields should fail
      changeset = module.changeset(struct!(module), %{})
      refute changeset.valid?

      # Verify at least title, content, author are required
      assert changeset.errors[:title]
      assert changeset.errors[:content]
      assert changeset.errors[:author]
    end

    test "CreatePostInput changeset validates length constraints via JSON AST" do
      # The simple IDL parser doesn't extract @length traits, so we test via
      # a JSON AST that includes them explicitly
      ast = %{
        "metadata" => %{"namespace" => "test.length"},
        "shapes" => %{
          "test.length#LenInput" => %{
            "type" => "structure",
            "members" => %{
              "title" => %{
                "target" => "smithy.api#String",
                "traits" => %{
                  "smithy.api#required" => %{},
                  "smithy.api#length" => %{"min" => 1, "max" => 10}
                }
              }
            }
          }
        }
      }

      {:ok, model} = IR.from_ast(ast)
      [spec] = Types.generate(model, base_module: E2ELength.Generated)

      assert {:ok, module} = CodeCompiler.compile_and_load(spec.content)
      on_exit(fn -> CodeCompiler.purge_module(module) end)

      # Title too long (max 10)
      changeset = module.changeset(struct!(module), %{"title" => String.duplicate("x", 11)})
      refute changeset.valid?
      assert changeset.errors[:title]

      # Valid length
      changeset = module.changeset(struct!(module), %{"title" => "hello"})
      assert changeset.valid?
    end
  end

  describe "HTTP binding correctness" do
    test "CreatePost uses POST /posts with 201 status" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      create_op = Enum.find(model.service.operations, &(&1.name == "CreatePost"))
      assert create_op.http.method == "POST"
      assert create_op.http.uri == "/posts"
      assert create_op.http.code == 201
    end

    test "GetPost uses GET /posts/{id} with path parameter" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      get_op = Enum.find(model.service.operations, &(&1.name == "GetPost"))
      assert get_op.http.method == "GET"
      assert get_op.http.uri == "/posts/{id}"
      assert get_op.http.path_params == ["id"]
    end

    test "ListPosts uses GET /posts" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      list_op = Enum.find(model.service.operations, &(&1.name == "ListPosts"))
      assert list_op.http.method == "GET"
      assert list_op.http.uri == "/posts"
      assert list_op.http.path_params == []
    end
  end

  describe "module hierarchy" do
    test "type modules are under base_module.Types.*" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      type_specs = Types.generate(model, base_module: E2E.Generated)

      Enum.each(type_specs, fn spec ->
        assert spec.content =~ "E2E.Generated.Types."
      end)
    end

    test "client module is under base_module.Client.*Client" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      [spec] = Client.generate(model, base_module: E2E.Generated, app_name: :e2e)
      assert spec.content =~ "Elixir.E2E.Generated.Client.BlogServiceClient"
    end

    test "server modules are under base_module.Server.*" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      {:ok, model} = IR.from_ast(ast)

      [behaviour, controller, router] =
        Server.generate(model, base_module: E2E.Generated, app_name: :e2e)

      assert behaviour.content =~ "Elixir.E2E.Generated.Server.Behaviours.BlogServiceBehaviour"
      assert controller.content =~ "Elixir.E2E.Generated.Server.Controllers.BlogServiceController"
      assert router.content =~ "Elixir.E2E.Generated.Server.BlogServiceRouter"
    end
  end
end
