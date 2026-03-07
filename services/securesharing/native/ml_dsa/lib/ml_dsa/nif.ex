defmodule MlDsa.Nif do
  @moduledoc false

  @on_load :load_nif

  @doc false
  def load_nif do
    path = :filename.join(:code.priv_dir(:ml_dsa), ~c"ml_dsa_nif")

    case :erlang.load_nif(path, 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def nif_init(_level) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_is_initialized do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_get_level do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_get_sizes do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_keypair do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_sign(_message, _secret_key) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_verify(_message, _signature, _public_key) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_cleanup do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_version do
    :erlang.nif_error(:nif_not_loaded)
  end
end
