defmodule SmithyGen.Generators.TypesTest do
  use ExUnit.Case, async: true

  alias SmithyGen.Generators.Types
  alias SmithyGen.Test.{IRBuilder, CodeCompiler}

  describe "generate/2" do
    test "only generates modules for structure shapes" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#User" => IRBuilder.shape("User", :structure, members: %{
              "name" => IRBuilder.member("name", "smithy.api#String")
            }),
            "test#UserList" => IRBuilder.shape("UserList", :list, target: "smithy.api#String")
          }
        )

      file_specs = Types.generate(model, base_module: TestTypes)
      assert length(file_specs) == 1
      assert hd(file_specs).path =~ "user.ex"
    end

    test "generates correct module name from base_module and shape name" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#CreatePostInput" => IRBuilder.shape("CreatePostInput", :structure, members: %{
              "title" => IRBuilder.member("title", "smithy.api#String")
            })
          }
        )

      [spec] = Types.generate(model, base_module: MyApp.Generated)
      assert spec.content =~ "defmodule MyApp.Generated.Types.CreatePostInput"
    end

    test "generates Ecto embedded schema" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#User" => IRBuilder.shape("User", :structure, members: %{
              "id" => IRBuilder.member("id", "smithy.api#String"),
              "name" => IRBuilder.member("name", "smithy.api#String")
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "use Ecto.Schema"
      assert spec.content =~ "import Ecto.Changeset"
      assert spec.content =~ "@primary_key false"
      assert spec.content =~ "embedded_schema do"
    end

    test "generates changeset function" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#User" => IRBuilder.shape("User", :structure, members: %{
              "name" => IRBuilder.member("name", "smithy.api#String")
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "def changeset("
      assert spec.content =~ "cast("
    end

    test "generates file spec with format: true" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#User" => IRBuilder.shape("User", :structure, members: %{
              "name" => IRBuilder.member("name", "smithy.api#String")
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.format == true
    end
  end

  describe "schema field type mapping" do
    test "maps String to :string" do
      assert_ecto_field_type("smithy.api#String", ":string")
    end

    test "maps Integer to :integer" do
      assert_ecto_field_type("smithy.api#Integer", ":integer")
    end

    test "maps Long to :integer" do
      assert_ecto_field_type("smithy.api#Long", ":integer")
    end

    test "maps Boolean to :boolean" do
      assert_ecto_field_type("smithy.api#Boolean", ":boolean")
    end

    test "maps Float to :float" do
      assert_ecto_field_type("smithy.api#Float", ":float")
    end

    test "maps Double to :float" do
      assert_ecto_field_type("smithy.api#Double", ":float")
    end

    test "maps Timestamp to :utc_datetime" do
      assert_ecto_field_type("smithy.api#Timestamp", ":utc_datetime")
    end

    test "maps Blob to :binary" do
      assert_ecto_field_type("smithy.api#Blob", ":binary")
    end

    test "maps all primitive types in a single structure" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#AllTypes" => IRBuilder.shape("AllTypes", :structure, members: %{
              "str" => IRBuilder.member("str", "smithy.api#String"),
              "int" => IRBuilder.member("int", "smithy.api#Integer"),
              "long" => IRBuilder.member("long", "smithy.api#Long"),
              "short" => IRBuilder.member("short", "smithy.api#Short"),
              "byte" => IRBuilder.member("byte", "smithy.api#Byte"),
              "float" => IRBuilder.member("float", "smithy.api#Float"),
              "double" => IRBuilder.member("double", "smithy.api#Double"),
              "bool" => IRBuilder.member("bool", "smithy.api#Boolean"),
              "timestamp" => IRBuilder.member("timestamp", "smithy.api#Timestamp"),
              "blob" => IRBuilder.member("blob", "smithy.api#Blob")
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "field(:str, :string)"
      assert spec.content =~ "field(:int, :integer)"
      assert spec.content =~ "field(:long, :integer)"
      assert spec.content =~ "field(:short, :integer)"
      assert spec.content =~ "field(:byte, :integer)"
      assert spec.content =~ "field(:float, :float)"
      assert spec.content =~ "field(:double, :float)"
      assert spec.content =~ "field(:bool, :boolean)"
      assert spec.content =~ "field(:timestamp, :utc_datetime)"
      assert spec.content =~ "field(:blob, :binary)"
    end
  end

  describe "typespec generation" do
    test "required fields do not have | nil in typespec" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#User" => IRBuilder.shape("User", :structure, members: %{
              "id" => IRBuilder.member("id", "smithy.api#String",
                traits: %{"smithy.api#required" => %{}}
              )
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "@type t :: %__MODULE__{"
      # Should have String.t() without | nil
      assert spec.content =~ "id: String.t()"
      refute spec.content =~ "id: String.t() | nil"
    end

    test "optional fields have | nil in typespec" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#User" => IRBuilder.shape("User", :structure, members: %{
              "name" => IRBuilder.member("name", "smithy.api#String")
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "name: String.t() | nil"
    end
  end

  describe "validation generation" do
    test "generates validate_required for @required members" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#Post" => IRBuilder.shape("Post", :structure, members: %{
              "title" => IRBuilder.member("title", "smithy.api#String",
                traits: %{"smithy.api#required" => %{}}
              ),
              "body" => IRBuilder.member("body", "smithy.api#String",
                traits: %{"smithy.api#required" => %{}}
              ),
              "tags" => IRBuilder.member("tags", "smithy.api#String")
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "validate_required("
    end

    test "generates validate_length for @length trait" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#Post" => IRBuilder.shape("Post", :structure, members: %{
              "title" => IRBuilder.member("title", "smithy.api#String",
                traits: %{"smithy.api#length" => %{"min" => 1, "max" => 200}}
              )
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "validate_length(:title, min: 1, max: 200)"
    end

    test "generates validate_length with min only" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#Post" => IRBuilder.shape("Post", :structure, members: %{
              "title" => IRBuilder.member("title", "smithy.api#String",
                traits: %{"smithy.api#length" => %{"min" => 1}}
              )
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "validate_length(:title, min: 1)"
    end

    test "generates validate_length with max only" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#Post" => IRBuilder.shape("Post", :structure, members: %{
              "title" => IRBuilder.member("title", "smithy.api#String",
                traits: %{"smithy.api#length" => %{"max" => 200}}
              )
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "validate_length(:title, max: 200)"
    end

    test "generates validate_number for @range trait" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#Config" => IRBuilder.shape("Config", :structure, members: %{
              "limit" => IRBuilder.member("limit", "smithy.api#Integer",
                traits: %{"smithy.api#range" => %{"min" => 1, "max" => 100}}
              )
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "validate_number(:limit"
      assert spec.content =~ "greater_than_or_equal_to: 1"
      assert spec.content =~ "less_than_or_equal_to: 100"
    end

    test "generates validate_format for @pattern trait" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#User" => IRBuilder.shape("User", :structure, members: %{
              "email" => IRBuilder.member("email", "smithy.api#String",
                traits: %{"smithy.api#pattern" => "^[^@]+@[^@]+$"}
              )
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "validate_format(:email"
    end
  end

  describe "documentation" do
    test "includes shape documentation in moduledoc" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#User" => IRBuilder.shape("User", :structure,
              documentation: "Represents a user account.",
              members: %{
                "name" => IRBuilder.member("name", "smithy.api#String")
              }
            )
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "Represents a user account."
    end

    test "generates default moduledoc when no documentation" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#User" => IRBuilder.shape("User", :structure, members: %{
              "name" => IRBuilder.member("name", "smithy.api#String")
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert spec.content =~ "Represents a User."
    end
  end

  describe "compilation" do
    test "generated code has valid syntax" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#User" => IRBuilder.shape("User", :structure, members: %{
              "id" => IRBuilder.member("id", "smithy.api#String",
                traits: %{"smithy.api#required" => %{}}
              ),
              "name" => IRBuilder.member("name", "smithy.api#String"),
              "age" => IRBuilder.member("age", "smithy.api#Integer",
                traits: %{"smithy.api#range" => %{"min" => 0, "max" => 200}}
              )
            })
          }
        )

      [spec] = Types.generate(model, base_module: TestTypes)
      assert :ok = CodeCompiler.validate_syntax(spec.content)
    end

    test "generated code compiles and produces a working module" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#CompileTestUser" => IRBuilder.shape("CompileTestUser", :structure, members: %{
              "id" => IRBuilder.member("id", "smithy.api#String",
                traits: %{"smithy.api#required" => %{}}
              ),
              "name" => IRBuilder.member("name", "smithy.api#String")
            })
          }
        )

      [spec] = Types.generate(model, base_module: SmithyGenTest.Compiled)
      assert {:ok, module} = CodeCompiler.compile_and_load(spec.content)

      on_exit(fn -> CodeCompiler.purge_module(module) end)

      # Module exists and has changeset/2
      assert function_exported?(module, :changeset, 2)

      # Changeset validates required fields
      changeset = module.changeset(struct!(module), %{})
      refute changeset.valid?
      assert changeset.errors[:id]

      # Changeset succeeds with valid data
      changeset = module.changeset(struct!(module), %{"id" => "123", "name" => "Alice"})
      assert changeset.valid?
    end

    test "generated changeset enforces required fields" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#RequiredFieldsTest" => IRBuilder.shape("RequiredFieldsTest", :structure, members: %{
              "required_field" => IRBuilder.member("required_field", "smithy.api#String",
                traits: %{"smithy.api#required" => %{}}
              ),
              "optional_field" => IRBuilder.member("optional_field", "smithy.api#String")
            })
          }
        )

      [spec] = Types.generate(model, base_module: SmithyGenTest.Compiled)
      assert {:ok, module} = CodeCompiler.compile_and_load(spec.content)

      on_exit(fn -> CodeCompiler.purge_module(module) end)

      # Missing required field
      changeset = module.changeset(struct!(module), %{"optional_field" => "ok"})
      refute changeset.valid?
      assert changeset.errors[:required_field]

      # All fields present
      changeset = module.changeset(struct!(module), %{"required_field" => "yes", "optional_field" => "ok"})
      assert changeset.valid?
    end

    test "generated changeset enforces length validation" do
      model =
        IRBuilder.model(
          shapes: %{
            "test#LengthTest" => IRBuilder.shape("LengthTest", :structure, members: %{
              "title" => IRBuilder.member("title", "smithy.api#String",
                traits: %{"smithy.api#length" => %{"min" => 3, "max" => 10}}
              )
            })
          }
        )

      [spec] = Types.generate(model, base_module: SmithyGenTest.Compiled)
      assert {:ok, module} = CodeCompiler.compile_and_load(spec.content)

      on_exit(fn -> CodeCompiler.purge_module(module) end)

      # Too short
      changeset = module.changeset(struct!(module), %{"title" => "ab"})
      refute changeset.valid?

      # Valid length
      changeset = module.changeset(struct!(module), %{"title" => "hello"})
      assert changeset.valid?

      # Too long
      changeset = module.changeset(struct!(module), %{"title" => "way too long title"})
      refute changeset.valid?
    end
  end

  # Helper to test individual type mappings
  defp assert_ecto_field_type(smithy_target, expected_ecto_type) do
    model =
      IRBuilder.model(
        shapes: %{
          "test#TypeTest" => IRBuilder.shape("TypeTest", :structure, members: %{
            "field" => IRBuilder.member("field", smithy_target)
          })
        }
      )

    [spec] = Types.generate(model, base_module: TestTypes)
    assert spec.content =~ "field(:field, #{expected_ecto_type})"
  end
end
