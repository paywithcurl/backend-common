defmodule BackendCommon.Mixfile do
  # https://github.com/elixir-lang/elixir/blob/v1.15/CHANGELOG.md#potential-incompatibilities-1
  # compilation failed because of enquirer dep(vaultex -> eliver -> enquirer)
  Code.compiler_options(on_undefined_variable: :warn)

  use Mix.Project

  def project do
    [
      app: :backend_common,
      version: "1.0.0",
      elixir: "~> 1.15",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger, :poison]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:ex_doc, ">= 0.15.0", only: :dev},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_kms, "~> 2.0"},
      {:vaultex, "~> 1.0"},
      {:plug, "~> 1.3.3", only: :test},
      {:plug_logger_json, github: "paywithcurl/plug_logger_json", only: :test}
    ]
  end
end
