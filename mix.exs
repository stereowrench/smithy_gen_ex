defmodule SmithyGen.MixProject do
  use Mix.Project

  def project do
    [
      app: :smithy_gen,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Smithy code generator for Elixir - generates client and server code from Smithy IDL",
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.11"},
      {:jason, "~> 1.4"},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/yourorg/smithy_gen"}
    ]
  end

  defp docs do
    [
      main: "SmithyGen",
      extras: ["README.md"]
    ]
  end
end
