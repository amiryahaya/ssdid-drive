defmodule KazKem.MixProject do
  use Mix.Project

  @version "2.1.0"

  def project do
    [
      app: :kaz_kem,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      deps: deps(),
      description: "Elixir NIF bindings for KAZ-KEM post-quantum key encapsulation"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.8", runtime: false}
    ]
  end
end
