defmodule KazSign.Nif do
  @moduledoc false

  @on_load :load_nif

  @doc false
  def load_nif do
    path = :filename.join(:code.priv_dir(:kaz_sign), ~c"kaz_sign_nif")

    case :erlang.load_nif(path, 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def nif_init do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_init_level(_level) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_is_initialized do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_get_sizes(_level) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_keypair(_level) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_sign(_level, _message, _private_key) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_verify(_level, _signature, _public_key) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc false
  def nif_hash(_level, _message) do
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
