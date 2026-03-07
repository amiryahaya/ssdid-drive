defmodule SecureSharing.Storage.Workers.BlobCleanupWorkerTest do
  @moduledoc """
  Tests for the BlobCleanupWorker Oban worker.
  """

  use SecureSharing.DataCase, async: true
  use Oban.Testing, repo: SecureSharing.Repo

  alias SecureSharing.Storage.Workers.BlobCleanupWorker

  describe "perform/1" do
    test "successfully deletes blob" do
      storage_path = "tenant-1/user-1/test-file-#{System.unique_integer()}"

      # Create a test file first (using local storage)
      {:ok, _} = SecureSharing.Storage.put(storage_path, "test content")

      # Verify file exists
      assert SecureSharing.Storage.exists?(storage_path)

      # Perform the worker job
      job = %Oban.Job{args: %{"storage_path" => storage_path}, attempt: 1}
      assert :ok = BlobCleanupWorker.perform(job)

      # Verify file was deleted
      refute SecureSharing.Storage.exists?(storage_path)
    end

    test "succeeds when blob already deleted" do
      storage_path = "tenant-1/user-1/nonexistent-file"

      # Ensure file doesn't exist
      refute SecureSharing.Storage.exists?(storage_path)

      # Perform the worker job - should succeed anyway
      job = %Oban.Job{args: %{"storage_path" => storage_path}, attempt: 1}
      assert :ok = BlobCleanupWorker.perform(job)
    end

    test "returns error for invalid args" do
      job = %Oban.Job{args: %{"invalid" => "args"}, attempt: 1}
      assert {:error, :invalid_args} = BlobCleanupWorker.perform(job)
    end

    test "returns error for empty args" do
      job = %Oban.Job{args: %{}, attempt: 1}
      assert {:error, :invalid_args} = BlobCleanupWorker.perform(job)
    end
  end

  describe "schedule_deletion/1" do
    test "enqueues deletion job" do
      storage_path = "tenant-1/user-1/scheduled-file"

      assert {:ok, job} = BlobCleanupWorker.schedule_deletion(storage_path)
      assert job.args == %{storage_path: storage_path}
      assert job.queue == "storage"

      # Verify job was enqueued
      assert_enqueued(worker: BlobCleanupWorker, args: %{storage_path: storage_path})
    end
  end

  describe "schedule_deletion/2 with delay" do
    test "enqueues deletion job with delay" do
      storage_path = "tenant-1/user-1/delayed-file"
      delay_seconds = 3600

      assert {:ok, job} = BlobCleanupWorker.schedule_deletion(storage_path, delay_seconds)
      assert job.args == %{storage_path: storage_path}

      # Verify job is scheduled in the future
      assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) == :gt
    end

    test "schedules job approximately at the specified delay" do
      storage_path = "tenant-1/user-1/timed-file"
      delay_seconds = 60

      before = DateTime.utc_now()
      assert {:ok, job} = BlobCleanupWorker.schedule_deletion(storage_path, delay_seconds)
      after_time = DateTime.utc_now()

      # The scheduled_at should be roughly delay_seconds from now
      expected_min = DateTime.add(before, delay_seconds - 1, :second)
      expected_max = DateTime.add(after_time, delay_seconds + 1, :second)

      assert DateTime.compare(job.scheduled_at, expected_min) in [:gt, :eq]
      assert DateTime.compare(job.scheduled_at, expected_max) in [:lt, :eq]
    end
  end

  describe "new/1" do
    test "creates a valid job changeset" do
      args = %{storage_path: "test/path"}

      job = BlobCleanupWorker.new(args)

      assert job.changes.args == %{storage_path: "test/path"}
      assert job.changes.queue == "storage"
      assert job.changes.max_attempts == 10
    end
  end
end
