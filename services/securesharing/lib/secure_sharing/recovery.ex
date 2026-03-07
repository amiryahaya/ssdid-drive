defmodule SecureSharing.Recovery do
  @moduledoc """
  The Recovery context for Shamir Secret Sharing based key recovery.

  This implements a zero-knowledge recovery system where:
  - User's Master Key is split into n shares using Shamir's Secret Sharing
  - Each share is encrypted for a trustee's public key
  - Any k shares can reconstruct the Master Key
  - Server never sees plaintext shares or the Master Key

  ## Recovery Flow

  1. **Setup** (during registration):
     - User generates Master Key
     - Client splits MK into n shares (threshold k)
     - Each share is encrypted for a trustee's public key
     - Encrypted shares are stored on server

  2. **Recovery** (when user loses access):
     - User generates new keypair
     - User creates recovery request with new public key
     - Trustees are notified
     - Each trustee decrypts their share, re-encrypts for new public key
     - Once k approvals received, user reconstructs MK
     - User re-encrypts MK with new passkey

  ## Example

      # Setup recovery with 3-of-5 threshold
      {:ok, config} = Recovery.setup_recovery(user, %{threshold: 3, total_shares: 5})

      # Distribute shares to trustees (done client-side, this stores encrypted shares)
      for {trustee, encrypted_share} <- shares do
        Recovery.create_share(config, trustee, encrypted_share_data)
      end

      # When user needs to recover
      {:ok, request} = Recovery.create_recovery_request(user, new_public_key)

      # Trustees approve
      Recovery.approve_recovery(request, trustee, reencrypted_share_data)

      # Check if threshold reached
      if Recovery.threshold_reached?(request) do
        # User can now reconstruct MK from approvals
      end
  """

  import Ecto.Query, warn: false
  alias SecureSharing.Repo
  alias SecureSharing.Accounts.User

  alias SecureSharing.Recovery.{
    RecoveryConfig,
    RecoveryShare,
    RecoveryRequest,
    RecoveryApproval,
    Shamir
  }

  # ============================================================================
  # Shamir Secret Sharing (utility functions for client)
  # ============================================================================

  @doc """
  Splits a secret into n shares with threshold k.
  This is a utility for the client - actual splitting happens client-side.

  Returns {:ok, shares} where shares is a list of {index, share_data} tuples.
  """
  defdelegate split_secret(secret, k, n), to: Shamir, as: :split

  @doc """
  Combines shares to reconstruct the original secret.
  This is a utility for the client - actual combining happens client-side.
  """
  defdelegate combine_shares(shares), to: Shamir, as: :combine

  @doc """
  Verifies that shares can reconstruct to the expected secret.
  """
  defdelegate verify_shares(secret, shares, k), to: Shamir, as: :verify

  # ============================================================================
  # Recovery Configuration
  # ============================================================================

  @doc """
  Creates a recovery configuration for a user.

  ## Options
  - threshold: minimum shares needed (default: 3)
  - total_shares: total shares to distribute (default: 5)
  """
  def setup_recovery(%User{} = user, attrs \\ %{}) do
    # Extract values from attrs (handles both string and atom keys)
    threshold = attrs["threshold"] || attrs[:threshold] || 3
    total_shares = attrs["total_shares"] || attrs[:total_shares] || 5

    # Build attrs with consistent atom keys
    final_attrs = %{
      user_id: user.id,
      threshold: threshold,
      total_shares: total_shares
    }

    %RecoveryConfig{}
    |> RecoveryConfig.changeset(final_attrs)
    |> Repo.insert()
  end

  @doc """
  Gets the recovery configuration for a user.
  """
  def get_recovery_config(%User{id: user_id}) do
    RecoveryConfig
    |> where([c], c.user_id == ^user_id)
    |> Repo.one()
  end

  @doc """
  Gets recovery config by ID.
  """
  def get_recovery_config_by_id(id), do: Repo.get(RecoveryConfig, id)

  @doc """
  Checks if a user has recovery configured and complete.
  """
  @spec has_recovery_configured?(String.t()) :: boolean()
  def has_recovery_configured?(user_id) do
    RecoveryConfig
    |> where([c], c.user_id == ^user_id and c.setup_complete == true)
    |> Repo.exists?()
  end

  @doc """
  Marks recovery setup as complete.
  Called after all shares have been distributed and accepted.
  """
  def complete_recovery_setup(%RecoveryConfig{} = config) do
    config
    |> RecoveryConfig.complete_setup_changeset()
    |> Repo.update()
  end

  @doc """
  Updates the last verification timestamp.
  Called when user verifies they can still access their shares.
  """
  def verify_recovery(%RecoveryConfig{} = config) do
    config
    |> RecoveryConfig.verify_changeset()
    |> Repo.update()
  end

  @doc """
  Disables recovery for a user.
  Deletes the recovery config and all associated shares.
  """
  def disable_recovery(%User{} = user) do
    case get_recovery_config(user) do
      nil ->
        {:error, :not_found}

      config ->
        Repo.transaction(fn ->
          # Delete all shares for this config
          from(s in RecoveryShare, where: s.config_id == ^config.id)
          |> Repo.delete_all()

          # Delete any pending recovery requests
          from(r in RecoveryRequest, where: r.config_id == ^config.id)
          |> Repo.delete_all()

          # Delete the config
          {:ok, _} = Repo.delete(config)

          :ok
        end)
    end
  end

  # ============================================================================
  # Recovery Shares (Trustee Management)
  # ============================================================================

  @doc """
  Creates a recovery share for a trustee.

  The share data should be encrypted for the trustee's public key.

  ## Parameters
  - config: RecoveryConfig
  - owner: User who owns the secret
  - trustee: User who will hold the share
  - attrs: Map containing:
    - share_index: 1 to n
    - encrypted_share: Share encrypted for trustee's public key
    - kem_ciphertext: KEM ciphertext for decryption
    - signature: Owner's signature
  """
  def create_share(%RecoveryConfig{} = config, %User{} = owner, %User{} = trustee, attrs) do
    share_index = parse_integer(attrs[:share_index] || attrs["share_index"])

    cond do
      # Verify the owner actually owns this recovery config
      config.user_id != owner.id ->
        {:error, :not_config_owner}

      # Verify share_index is within bounds
      share_index == nil ->
        {:error, :missing_share_index}

      not is_integer(share_index) ->
        {:error, :invalid_share_index}

      share_index < 1 or share_index > config.total_shares ->
        {:error, :share_index_out_of_bounds}

      true ->
        # Normalize attrs to atom keys to avoid mixed key map issues with Ecto
        attrs =
          attrs
          |> normalize_keys()
          |> Map.put(:config_id, config.id)
          |> Map.put(:owner_id, owner.id)
          |> Map.put(:trustee_id, trustee.id)
          |> Map.put(:share_index, share_index)

        %RecoveryShare{}
        |> RecoveryShare.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc """
  Gets a share by ID.
  """
  def get_share(id), do: Repo.get(RecoveryShare, id)

  @doc """
  Lists all shares held by a trustee.
  """
  def list_trustee_shares(%User{id: trustee_id}) do
    RecoveryShare
    |> where([s], s.trustee_id == ^trustee_id)
    |> preload(:owner)
    |> order_by([s], desc: s.created_at)
    |> Repo.all()
  end

  @doc """
  Lists all shares for a user's recovery (owned shares).
  """
  def list_owner_shares(%User{id: owner_id}) do
    RecoveryShare
    |> where([s], s.owner_id == ^owner_id)
    |> preload(:trustee)
    |> order_by([s], asc: s.share_index)
    |> Repo.all()
  end

  @doc """
  Lists shares for a specific recovery config.
  """
  def list_config_shares(%RecoveryConfig{id: config_id}) do
    RecoveryShare
    |> where([s], s.config_id == ^config_id)
    |> preload(:trustee)
    |> order_by([s], asc: s.share_index)
    |> Repo.all()
  end

  @doc """
  Trustee accepts a share.
  """
  def accept_share(%RecoveryShare{} = share) do
    share
    |> RecoveryShare.accept_changeset()
    |> Repo.update()
  end

  @doc """
  Trustee rejects a share.
  Marks the share as rejected so the grantor can select a different trustee.
  """
  def reject_share(%RecoveryShare{} = share) do
    share
    |> Ecto.Changeset.change(status: :rejected)
    |> Repo.update()
  end

  @doc """
  Revokes a share (as the grantor/owner).
  The share is deleted, and the owner must distribute to a new trustee.
  """
  def revoke_share(%RecoveryShare{} = share) do
    Repo.delete(share)
  end

  @doc """
  Counts accepted shares for a config.
  """
  def count_accepted_shares(%RecoveryConfig{id: config_id}) do
    RecoveryShare
    |> where([s], s.config_id == ^config_id and s.accepted == true)
    |> Repo.aggregate(:count)
  end

  @doc """
  Checks if recovery setup is complete (all shares distributed and accepted).
  """
  def recovery_setup_complete?(%RecoveryConfig{} = config) do
    config = Repo.preload(config, :shares)
    expected = config.total_shares
    accepted = Enum.count(config.shares, & &1.accepted)
    accepted >= expected
  end

  # ============================================================================
  # Recovery Requests
  # ============================================================================

  @doc """
  Creates a recovery request.

  The user must provide their new public key. Trustees will re-encrypt
  their shares for this new key.

  ## Parameters
  - user: User requesting recovery
  - new_public_key: Binary public key for receiving re-encrypted shares
  - opts: Optional params
    - reason: Why recovery is needed
    - expires_in_days: Days until request expires (default: 7)
  """
  def create_recovery_request(%User{} = user, new_public_key, opts \\ []) do
    config = get_recovery_config(user)

    if is_nil(config) do
      {:error, :no_recovery_config}
    else
      expires_in_days = Keyword.get(opts, :expires_in_days, 7)

      expires_at =
        DateTime.utc_now()
        |> DateTime.add(expires_in_days, :day)
        |> DateTime.truncate(:microsecond)

      attrs = %{
        config_id: config.id,
        user_id: user.id,
        new_public_key: new_public_key,
        reason: Keyword.get(opts, :reason),
        expires_at: expires_at
      }

      %RecoveryRequest{}
      |> RecoveryRequest.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Gets a recovery request by ID.
  """
  def get_recovery_request(id), do: Repo.get(RecoveryRequest, id)

  @doc """
  Gets a recovery request with preloaded associations.
  """
  def get_recovery_request!(id, preloads \\ []) do
    RecoveryRequest
    |> Repo.get!(id)
    |> Repo.preload(preloads)
  end

  @doc """
  Lists pending recovery requests for trustees to review.
  Returns requests where the trustee holds a share for the requesting user.
  """
  def list_pending_requests_for_trustee(%User{id: trustee_id}) do
    now = DateTime.utc_now()

    # Find recovery requests where this user is a trustee
    from(r in RecoveryRequest,
      join: s in RecoveryShare,
      on: s.config_id == r.config_id and s.trustee_id == ^trustee_id,
      where: r.status == :pending and r.expires_at > ^now,
      preload: [:user, :config],
      order_by: [desc: r.created_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists all recovery requests for a user.
  """
  def list_user_requests(%User{id: user_id}) do
    RecoveryRequest
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], desc: r.created_at)
    |> Repo.all()
  end

  @doc """
  Verifies a recovery request (admin/security team action).
  """
  def verify_request(%RecoveryRequest{} = request, %User{} = verifier) do
    request
    |> RecoveryRequest.verify_changeset(verifier)
    |> Repo.update()
  end

  @doc """
  Updates request status.
  """
  def update_request_status(%RecoveryRequest{} = request, status) do
    request
    |> RecoveryRequest.status_changeset(status)
    |> Repo.update()
  end

  @doc """
  Cancels a pending recovery request.
  Only the request owner can cancel.
  """
  def cancel_request(%RecoveryRequest{} = request) do
    if request.status in [:pending, :approved] do
      # Delete any approvals
      from(a in RecoveryApproval, where: a.request_id == ^request.id)
      |> Repo.delete_all()

      # Delete the request
      Repo.delete(request)
    else
      {:error, :request_not_cancellable}
    end
  end

  # ============================================================================
  # Recovery Approvals
  # ============================================================================

  @doc """
  Trustee approves a recovery request.

  The trustee must:
  1. Decrypt their share using their private key
  2. Re-encrypt the share for the requesting user's new public key
  3. Sign the approval

  ## Parameters
  - request: RecoveryRequest being approved
  - share: RecoveryShare the trustee holds
  - trustee: User approving
  - attrs: Map containing:
    - reencrypted_share: Share re-encrypted for new public key
    - kem_ciphertext: KEM ciphertext for decryption
    - signature: Trustee's signature
  """
  def approve_recovery(
        %RecoveryRequest{} = request,
        %RecoveryShare{} = share,
        %User{} = trustee,
        attrs
      ) do
    cond do
      # Verify request is in an approvable state
      request.status not in [:pending, :approved] ->
        {:error, :request_not_approvable}

      # Verify request hasn't expired
      DateTime.compare(request.expires_at, DateTime.utc_now()) != :gt ->
        {:error, :request_expired}

      # Verify trustee owns this share
      share.trustee_id != trustee.id ->
        {:error, :not_share_owner}

      # Verify share has been accepted by the trustee
      not share.accepted ->
        {:error, :share_not_accepted}

      # Verify share belongs to this request's config
      share.config_id != request.config_id ->
        {:error, :share_config_mismatch}

      true ->
        attrs =
          attrs
          |> Map.put(:request_id, request.id)
          |> Map.put(:share_id, share.id)
          |> Map.put(:trustee_id, trustee.id)

        result =
          %RecoveryApproval{}
          |> RecoveryApproval.changeset(attrs)
          |> Repo.insert()

        # Check if threshold reached and update request status
        case result do
          {:ok, approval} ->
            check_and_update_threshold(request)
            {:ok, approval}

          error ->
            error
        end
    end
  end

  @doc """
  Lists approvals for a recovery request.
  """
  def list_request_approvals(%RecoveryRequest{id: request_id}) do
    RecoveryApproval
    |> where([a], a.request_id == ^request_id)
    |> preload([:trustee, :share])
    |> order_by([a], asc: a.created_at)
    |> Repo.all()
  end

  @doc """
  Counts approvals for a request.
  """
  def count_approvals(%RecoveryRequest{id: request_id}) do
    RecoveryApproval
    |> where([a], a.request_id == ^request_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Checks if the threshold has been reached for a recovery request.
  """
  def threshold_reached?(%RecoveryRequest{} = request) do
    request = Repo.preload(request, :config)
    approval_count = count_approvals(request)
    approval_count >= request.config.threshold
  end

  @doc """
  Gets the recovery progress for a request.
  """
  def get_recovery_progress(%RecoveryRequest{} = request) do
    request = Repo.preload(request, :config)
    approval_count = count_approvals(request)

    %{
      approvals: approval_count,
      threshold: request.config.threshold,
      total_shares: request.config.total_shares,
      threshold_reached: approval_count >= request.config.threshold,
      percentage: round(approval_count / request.config.threshold * 100)
    }
  end

  # Check if threshold reached and update status
  defp check_and_update_threshold(%RecoveryRequest{} = request) do
    if threshold_reached?(request) do
      update_request_status(request, :approved)
    end
  end

  # Safely parse an integer from string or return integer as-is
  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> :invalid
    end
  end

  defp parse_integer(_), do: :invalid

  # Extract known keys from a map, normalizing string keys to atoms
  # This avoids mixed key maps which Ecto rejects, and prevents atom exhaustion
  @known_share_keys ~w(encrypted_share kem_ciphertext signature algorithm)a
  defp normalize_keys(map) when is_map(map) do
    Enum.reduce(@known_share_keys, %{}, fn key, acc ->
      str_key = Atom.to_string(key)

      cond do
        Map.has_key?(map, key) -> Map.put(acc, key, Map.get(map, key))
        Map.has_key?(map, str_key) -> Map.put(acc, key, Map.get(map, str_key))
        true -> acc
      end
    end)
  end

  @doc """
  Marks a recovery request as completed.
  Called after user has successfully reconstructed their Master Key.
  """
  def complete_recovery(%RecoveryRequest{} = request) do
    update_request_status(request, :completed)
  end

  # ============================================================================
  # User Account Recovery
  # ============================================================================

  @doc """
  Updates user's key material after successful recovery.

  This is called after the user has:
  1. Reconstructed their Master Key from shares
  2. Generated a new passkey/credential
  3. Re-encrypted the Master Key with the new passkey

  Validates:
  - User owns the recovery request
  - Request is in :approved status
  - Threshold has been reached
  """
  def finalize_recovery(%User{} = user, %RecoveryRequest{} = request, new_key_material) do
    cond do
      # Verify user owns this recovery request
      request.user_id != user.id ->
        {:error, :not_request_owner}

      # Verify request is in approved status
      request.status != :approved ->
        {:error, :request_not_approved}

      # Verify threshold has been reached
      not threshold_reached?(request) ->
        {:error, :threshold_not_reached}

      true ->
        Repo.transaction(fn ->
          # Update user's key material
          {:ok, updated_user} =
            user
            |> Ecto.Changeset.change(new_key_material)
            |> Ecto.Changeset.change(status: :active)
            |> Repo.update()

          # Mark request as completed
          {:ok, _} = complete_recovery(request)

          # Update recovery setup to mark as verified
          config = get_recovery_config_by_id(request.config_id)
          {:ok, _} = verify_recovery(config)

          updated_user
        end)
    end
  end
end
