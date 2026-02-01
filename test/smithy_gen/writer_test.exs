defmodule SmithyGen.WriterTest do
  use ExUnit.Case, async: false

  alias SmithyGen.Writer

  setup do
    temp_dir = Path.join(System.tmp_dir!(), "smithy_writer_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(temp_dir)
    on_exit(fn -> File.rm_rf!(temp_dir) end)
    %{temp_dir: temp_dir}
  end

  describe "file_spec/3" do
    test "creates spec with defaults" do
      spec = Writer.file_spec("path.ex", "content")
      assert spec.path == "path.ex"
      assert spec.content == "content"
      assert spec.format == true
    end

    test "allows disabling formatting" do
      spec = Writer.file_spec("path.ex", "content", format: false)
      assert spec.format == false
    end
  end

  describe "module_to_path/2" do
    test "converts module name to file path" do
      assert "lib/my_app/generated/types/user.ex" =
               Writer.module_to_path(MyApp.Generated.Types.User, "lib")
    end

    test "handles single-segment module" do
      assert "lib/user.ex" = Writer.module_to_path(User, "lib")
    end

    test "handles custom base directory" do
      assert "src/my_app/user.ex" = Writer.module_to_path(MyApp.User, "src")
    end

    test "underscores camelCase segments" do
      assert "lib/my_app/blog_service/create_post_input.ex" =
               Writer.module_to_path(MyApp.BlogService.CreatePostInput, "lib")
    end
  end

  describe "format_elixir_code/1" do
    test "formats valid Elixir code" do
      result = Writer.format_elixir_code("defmodule   Foo  do   def    bar,  do: :ok   end")
      assert result =~ "defmodule Foo do"
      assert result =~ "def bar"
    end

    test "returns original on invalid code" do
      input = "this is not valid elixir {{{;"
      assert Writer.format_elixir_code(input) == input
    end
  end

  describe "write_file/2" do
    test "writes file to disk", %{temp_dir: dir} do
      path = Path.join(dir, "test.ex")
      spec = Writer.file_spec(path, "defmodule Test do\nend", format: false)

      assert :ok = Writer.write_file(spec, quiet: true)
      assert File.exists?(path)
      assert File.read!(path) == "defmodule Test do\nend"
    end

    test "formats code when format: true", %{temp_dir: dir} do
      path = Path.join(dir, "formatted.ex")
      spec = Writer.file_spec(path, "defmodule   Test   do    end")

      assert :ok = Writer.write_file(spec, quiet: true, force: true)
      content = File.read!(path)
      assert content =~ "defmodule Test do"
    end

    test "creates nested directories", %{temp_dir: dir} do
      path = Path.join([dir, "nested", "deep", "file.ex"])
      spec = Writer.file_spec(path, "content", format: false)

      assert :ok = Writer.write_file(spec, quiet: true, force: true)
      assert File.exists?(path)
    end

    test "does not overwrite without force", %{temp_dir: dir} do
      path = Path.join(dir, "existing.ex")
      File.write!(path, "original")

      spec = Writer.file_spec(path, "new content", format: false)
      assert :ok = Writer.write_file(spec, quiet: true, force: false)

      assert File.read!(path) == "original"
    end

    test "overwrites with force: true", %{temp_dir: dir} do
      path = Path.join(dir, "existing.ex")
      File.write!(path, "original")

      spec = Writer.file_spec(path, "new content", format: false)
      assert :ok = Writer.write_file(spec, quiet: true, force: true)

      assert File.read!(path) == "new content"
    end
  end

  describe "write_files/2" do
    test "writes multiple files", %{temp_dir: dir} do
      specs = [
        Writer.file_spec(Path.join(dir, "one.ex"), "content 1", format: false),
        Writer.file_spec(Path.join(dir, "two.ex"), "content 2", format: false)
      ]

      assert {:ok, 2} = Writer.write_files(specs, quiet: true, force: true)
      assert File.exists?(Path.join(dir, "one.ex"))
      assert File.exists?(Path.join(dir, "two.ex"))
    end
  end

  describe "backup_file/1" do
    test "creates backup of existing file", %{temp_dir: dir} do
      path = Path.join(dir, "original.ex")
      File.write!(path, "original content")

      assert :ok = Writer.backup_file(path)
      assert File.exists?(path <> ".backup")
      assert File.read!(path <> ".backup") == "original content"
    end

    test "succeeds when file does not exist", %{temp_dir: dir} do
      path = Path.join(dir, "nonexistent.ex")
      assert :ok = Writer.backup_file(path)
    end
  end
end
