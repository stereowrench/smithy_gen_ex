defmodule SmithyGenTest do
  use ExUnit.Case

  test "version returns a string" do
    assert is_binary(SmithyGen.version())
  end
end
