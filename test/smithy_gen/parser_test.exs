defmodule SmithyGen.ParserTest do
  use ExUnit.Case, async: true

  alias SmithyGen.Parser

  @example_smithy Path.expand("../../priv/smithy/example.smithy", __DIR__)

  describe "parse_file/1" do
    test "parses the example Smithy file" do
      assert {:ok, ast} = Parser.parse_file(@example_smithy)
      assert ast["smithy"] == "2.0"
      assert is_map(ast["shapes"])
      assert map_size(ast["shapes"]) > 0
    end

    test "returns error for non-existent file" do
      assert {:error, {:file_read_error, :enoent}} = Parser.parse_file("/nonexistent.smithy")
    end

    test "extracts namespace" do
      {:ok, ast} = Parser.parse_file(@example_smithy)
      assert get_in(ast, ["metadata", "namespace"]) == "com.example.blog"
    end

    test "parses service shape" do
      {:ok, ast} = Parser.parse_file(@example_smithy)

      service =
        ast["shapes"]
        |> Enum.find(fn {_id, data} -> data["type"] == "service" end)

      assert {id, data} = service
      assert id == "com.example.blog#BlogService"
      assert data["version"] == "2024-01-01"
      assert is_list(data["operations"])
    end

    test "parses structure shapes with members" do
      {:ok, ast} = Parser.parse_file(@example_smithy)

      create_input = ast["shapes"]["com.example.blog#CreatePostInput"]
      assert create_input["type"] == "structure"
      assert is_map(create_input["members"])
      assert Map.has_key?(create_input["members"], "title")
      assert create_input["members"]["title"]["target"] == "smithy.api#String"
    end

    test "parses @required trait on members" do
      {:ok, ast} = Parser.parse_file(@example_smithy)

      create_input = ast["shapes"]["com.example.blog#CreatePostInput"]
      title_traits = create_input["members"]["title"]["traits"]
      assert Map.has_key?(title_traits, "smithy.api#required")
      assert title_traits["smithy.api#required"] == %{}
    end

    test "parses operations with HTTP bindings" do
      {:ok, ast} = Parser.parse_file(@example_smithy)

      create_post = ast["shapes"]["com.example.blog#CreatePost"]
      assert create_post["type"] == "operation"
      assert create_post["traits"]["smithy.api#http"]["method"] == "POST"
      assert create_post["traits"]["smithy.api#http"]["uri"] == "/posts"
      assert create_post["traits"]["smithy.api#http"]["code"] == 201
    end

    test "parses operation input and output references" do
      {:ok, ast} = Parser.parse_file(@example_smithy)

      create_post = ast["shapes"]["com.example.blog#CreatePost"]
      assert create_post["input"] == "com.example.blog#CreatePostInput"
      assert create_post["output"] == "com.example.blog#CreatePostOutput"
    end

    test "resolves built-in type targets" do
      {:ok, ast} = Parser.parse_file(@example_smithy)

      post = ast["shapes"]["com.example.blog#Post"]
      assert post["members"]["id"]["target"] == "smithy.api#String"
      assert post["members"]["createdAt"]["target"] == "smithy.api#Timestamp"
    end

    test "resolves custom type targets" do
      {:ok, ast} = Parser.parse_file(@example_smithy)

      create_input = ast["shapes"]["com.example.blog#CreatePostInput"]
      assert create_input["members"]["tags"]["target"] == "com.example.blog#TagList"
    end
  end

  describe "parse_json/1" do
    test "parses valid Smithy JSON AST" do
      json = ~s({"smithy": "2.0", "shapes": {}, "metadata": {}})
      assert {:ok, ast} = Parser.parse_json(json)
      assert ast["smithy"] == "2.0"
      assert ast["shapes"] == %{}
    end

    test "returns error for invalid JSON" do
      assert {:error, {:json_decode_error, _}} = Parser.parse_json("{invalid json}")
    end
  end

  describe "parse_directory/1" do
    test "parses all Smithy files in directory" do
      dir = Path.expand("../../priv/smithy", __DIR__)
      assert {:ok, ast} = Parser.parse_directory(dir)
      assert is_map(ast["shapes"])
      assert map_size(ast["shapes"]) > 0
    end

    test "returns error for directory with no Smithy files" do
      dir = System.tmp_dir!() |> Path.join("empty_smithy_#{:rand.uniform(10000)}")
      File.mkdir_p!(dir)

      try do
        assert {:error, {:no_smithy_files, ^dir}} = Parser.parse_directory(dir)
      after
        File.rm_rf!(dir)
      end
    end
  end

  describe "parsing with temp files" do
    test "parses minimal structure" do
      assert {:ok, ast} =
               parse_temp_smithy("""
               namespace test.minimal

               structure SimpleUser {
                 name: String
               }
               """)

      user = ast["shapes"]["test.minimal#SimpleUser"]
      assert user["type"] == "structure"
      assert user["members"]["name"]["target"] == "smithy.api#String"
    end

    test "parses operation with GET method and path param" do
      assert {:ok, ast} =
               parse_temp_smithy("""
               namespace test.ops

               @http(method: "GET", uri: "/items/{id}", code: 200)
               operation GetItem {
                 input := GetItemInput
                 output := GetItemOutput
               }

               structure GetItemInput {
                 id: String
               }

               structure GetItemOutput {
                 item: String
               }
               """)

      op = ast["shapes"]["test.ops#GetItem"]
      assert op["traits"]["smithy.api#http"]["method"] == "GET"
      assert op["traits"]["smithy.api#http"]["uri"] == "/items/{id}"
      assert op["input"] == "test.ops#GetItemInput"
      assert op["output"] == "test.ops#GetItemOutput"
    end

    test "parses service with operation list" do
      assert {:ok, ast} =
               parse_temp_smithy("""
               namespace test.svc

               @restJson1
               service TestService {
                 version: "1.0"
                 operations: [DoThing]
               }

               @http(method: "POST", uri: "/things", code: 201)
               operation DoThing {
                 input := DoThingInput
                 output := DoThingOutput
               }

               structure DoThingInput {
                 name: String
               }

               structure DoThingOutput {
                 id: String
               }
               """)

      service = ast["shapes"]["test.svc#TestService"]
      assert service["type"] == "service"
      assert service["version"] == "1.0"
      assert "test.svc#DoThing" in service["operations"]
    end

    test "parses multiple structure members with different types" do
      assert {:ok, ast} =
               parse_temp_smithy("""
               namespace test.types

               structure AllTypes {
                 str: String
                 num: Integer
                 big: Long
                 flag: Boolean
                 dec: Float
                 when: Timestamp
               }
               """)

      shape = ast["shapes"]["test.types#AllTypes"]
      assert shape["members"]["str"]["target"] == "smithy.api#String"
      assert shape["members"]["num"]["target"] == "smithy.api#Integer"
      assert shape["members"]["big"]["target"] == "smithy.api#Long"
      assert shape["members"]["flag"]["target"] == "smithy.api#Boolean"
      assert shape["members"]["dec"]["target"] == "smithy.api#Float"
      assert shape["members"]["when"]["target"] == "smithy.api#Timestamp"
    end
  end

  defp parse_temp_smithy(content) do
    path = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(100_000)}.smithy")
    File.write!(path, content)

    try do
      Parser.parse_file(path)
    after
      File.rm(path)
    end
  end
end
