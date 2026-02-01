defmodule SmithyGenTest do
  use ExUnit.Case
  doctest SmithyGen

  test "greets the world" do
    assert SmithyGen.hello() == :world
  end
end
