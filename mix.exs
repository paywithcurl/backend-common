defmodule BackendCommon.Mixfile do
  use Mix.Project

  def project do
    [app: :backend_common,
     version: "0.2.0",
     elixir: "~> 1.4",
     elixirc_options: [
       warnings_as_errors: true
     ],
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
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
      {:vaultex, "~> 0.6"},
      {:plug, "~> 1.3.3", only: :test},
      {:server_sent_event, ">= 0.3.0"},
      {:plug_logger_json, github: "paywithcurl/plug_logger_json", only: :test},
    ]
  end
end
