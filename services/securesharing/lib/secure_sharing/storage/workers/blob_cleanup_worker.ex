defmodule SecureSharing.Storage.Workers.BlobCleanupWorker do
  @moduledoc """
  Oban worker for asynchronous blob deletion.

  When a file is deleted, the blob should be removed from storage.
  This worker handles deletion asynchronously with retry logic for
  transient failures.

  ## Usage

      # Enqueue deletion job
      %{storage_path: "tenant/user/file"}
      |> SecureSharing.Storage.Workers.BlobCleanupWorker.new()
      |> Oban.insert()

  ## Retry Logic

  - Max attempts: 10
  - Backoff: Exponential with jitter
  - Discards job after final failure (logs error)
  """

  use Oban.Worker,
    queue: :storage,
    max_attempts: 10,
    tags: ["storage", "cleanup"]

  alias SecureSharing.Storage

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"storage_path" => storage_path}, attempt: attempt}) do
    Logger.info("BlobCleanupWorker: Deleting blob at #{storage_path} (attempt #{attempt})")

    case Storage.delete(storage_path) do
      :ok ->
        Logger.info("BlobCleanupWorker: Successfully deleted blob at #{storage_path}")
        :ok

      {:error, :not_found} ->
        # Already deleted, that's fine
        Logger.info("BlobCleanupWorker: Blob already deleted at #{storage_path}")
        :ok

      {:error, reason} ->
        Logger.warning(
          "BlobCleanupWorker: Failed to delete blob at #{storage_path}: #{inspect(reason)}"
        )

        # Return error to trigger retry
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.error("BlobCleanupWorker: Invalid job args: #{inspect(args)}")
    {:error, :invalid_args}
  end

  @doc """
  Schedule blob deletion for a file.

  Returns {:ok, job} on success.
  """
  @spec schedule_deletion(String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_deletion(storage_path) when is_binary(storage_path) do
    %{storage_path: storage_path}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Schedule blob deletion with a delay.

  Useful for implementing soft-delete or giving users time to undo.
  """
  @spec schedule_deletion(String.t(), non_neg_integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def schedule_deletion(storage_path, delay_seconds) when is_binary(storage_path) do
    %{storage_path: storage_path}
    |> new(scheduled_at: DateTime.add(DateTime.utc_now(), delay_seconds, :second))
    |> Oban.insert()
  end
end
