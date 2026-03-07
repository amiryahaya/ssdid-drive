defmodule SecureSharing.Recovery.Shamir do
  @moduledoc """
  Shamir's Secret Sharing implementation over GF(256).

  Splits a secret into n shares where any k shares can reconstruct
  the original secret, but k-1 shares reveal no information.

  Uses GF(256) with the AES irreducible polynomial (0x11B) for byte-level
  operations, allowing arbitrary binary secrets to be split.

  ## Example

      # Split a 32-byte master key into 5 shares, requiring 3 to reconstruct
      {:ok, shares} = Shamir.split(master_key, 3, 5)

      # Reconstruct from any 3 shares
      {:ok, recovered} = Shamir.combine([share1, share2, share3])
      recovered == master_key  # true

  ## Security Notes

  - Uses cryptographically secure random coefficients
  - Each share reveals zero information about the secret
  - Share indices are 1-based (never 0, as that would be the secret)
  """

  @doc """
  Splits a binary secret into n shares with threshold k.

  Returns {:ok, shares} where shares is a list of {index, share_data} tuples.
  Each share has the same length as the secret.
  """
  @spec split(binary(), pos_integer(), pos_integer()) ::
          {:ok, [{pos_integer(), binary()}]} | {:error, atom()}
  def split(secret, k, n) when is_binary(secret) and k > 0 and n > 0 and k <= n and n <= 255 do
    secret_bytes = :binary.bin_to_list(secret)

    # For each byte position, generate ONE polynomial (same coefficients for all shares)
    # coefficients = [secret_byte, random_1, random_2, ..., random_{k-1}]
    polynomials =
      Enum.map(secret_bytes, fn secret_byte ->
        [secret_byte | random_coefficients(k - 1)]
      end)

    # Generate shares: evaluate all polynomials at x = 1, 2, ..., n
    shares =
      for x <- 1..n do
        share_bytes =
          Enum.map(polynomials, fn coefficients ->
            evaluate_polynomial(coefficients, x)
          end)

        {x, :binary.list_to_bin(share_bytes)}
      end

    {:ok, shares}
  end

  def split(_secret, _k, _n), do: {:error, :invalid_parameters}

  @doc """
  Combines shares to reconstruct the original secret.

  Takes a list of {index, share_data} tuples.
  Requires at least k shares (the threshold used during split).
  """
  @spec combine([{pos_integer(), binary()}]) :: {:ok, binary()} | {:error, atom()}
  def combine(shares) when is_list(shares) and length(shares) > 0 do
    # Verify all shares have the same length
    lengths = Enum.map(shares, fn {_x, data} -> byte_size(data) end)

    if Enum.uniq(lengths) |> length() != 1 do
      {:error, :share_length_mismatch}
    else
      secret_length = hd(lengths)

      # Convert shares to lists of bytes
      share_data =
        Enum.map(shares, fn {x, data} ->
          {x, :binary.bin_to_list(data)}
        end)

      # Reconstruct each byte using Lagrange interpolation
      secret_bytes =
        for pos <- 0..(secret_length - 1) do
          points =
            Enum.map(share_data, fn {x, bytes} ->
              {x, Enum.at(bytes, pos)}
            end)

          lagrange_interpolate_at_zero(points)
        end

      {:ok, :binary.list_to_bin(secret_bytes)}
    end
  end

  def combine(_), do: {:error, :invalid_shares}

  @doc """
  Verifies that shares can reconstruct to the expected secret.
  Useful for testing share validity without revealing the secret.
  """
  @spec verify(binary(), [{pos_integer(), binary()}], pos_integer()) :: boolean()
  def verify(secret, shares, k) when length(shares) >= k do
    # Take exactly k shares
    test_shares = Enum.take(shares, k)

    case combine(test_shares) do
      {:ok, recovered} -> recovered == secret
      _ -> false
    end
  end

  def verify(_secret, _shares, _k), do: false

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Generates k random bytes for polynomial coefficients
  defp random_coefficients(k) do
    :crypto.strong_rand_bytes(k)
    |> :binary.bin_to_list()
  end

  # Evaluates polynomial at x
  # coefficients = [a_0, a_1, ..., a_{k-1}]
  # result = a_0 + a_1*x + a_2*x^2 + ... + a_{k-1}*x^{k-1}
  defp evaluate_polynomial(coefficients, x) do
    # Use Horner's method: ((a_{k-1}*x + a_{k-2})*x + ...) + a_0
    coefficients
    |> Enum.reverse()
    |> Enum.reduce(0, fn coeff, acc ->
      gf_add(gf_mul(acc, x), coeff)
    end)
  end

  # Lagrange interpolation at x=0 to find the secret
  defp lagrange_interpolate_at_zero(points) do
    # f(0) = sum over i of (y_i * L_i(0))
    # L_i(0) = product over j!=i of (0 - x_j) / (x_i - x_j)
    #        = product over j!=i of x_j / (x_j - x_i)  [in GF arithmetic]

    xs = Enum.map(points, fn {x, _y} -> x end)

    points
    |> Enum.reduce(0, fn {xi, yi}, sum ->
      # Calculate Lagrange basis polynomial L_i(0)
      li =
        xs
        |> Enum.reject(fn xj -> xj == xi end)
        |> Enum.reduce(1, fn xj, prod ->
          # L_i(0) *= x_j / (x_j - x_i)
          numerator = xj
          denominator = gf_sub(xj, xi)
          gf_mul(prod, gf_div(numerator, denominator))
        end)

      # sum += y_i * L_i(0)
      gf_add(sum, gf_mul(yi, li))
    end)
  end

  # ============================================================================
  # GF(256) Arithmetic
  # AES polynomial: x^8 + x^4 + x^3 + x + 1 (0x11B)
  # ============================================================================

  # GF(256) addition (XOR)
  defp gf_add(a, b), do: Bitwise.bxor(a, b)

  # GF(256) subtraction (same as addition in GF(256))
  defp gf_sub(a, b), do: Bitwise.bxor(a, b)

  # GF(256) multiplication using Russian peasant algorithm
  defp gf_mul(0, _), do: 0
  defp gf_mul(_, 0), do: 0

  defp gf_mul(a, b) do
    gf_mul_loop(a, b, 0)
  end

  defp gf_mul_loop(_a, 0, result), do: result

  defp gf_mul_loop(a, b, result) do
    result =
      if Bitwise.band(b, 1) == 1 do
        Bitwise.bxor(result, a)
      else
        result
      end

    a = Bitwise.bsl(a, 1)

    a =
      if Bitwise.band(a, 0x100) != 0 do
        Bitwise.bxor(a, 0x11B)
      else
        a
      end

    b = Bitwise.bsr(b, 1)
    gf_mul_loop(a, b, result)
  end

  # GF(256) multiplicative inverse using extended Euclidean algorithm
  # a^(-1) = a^254 in GF(256) since a^255 = 1 for all a != 0
  defp gf_inv(0), do: 0
  defp gf_inv(a), do: gf_pow(a, 254)

  # GF(256) exponentiation using square-and-multiply
  defp gf_pow(_a, 0), do: 1
  defp gf_pow(a, 1), do: a

  defp gf_pow(a, n) do
    if Bitwise.band(n, 1) == 1 do
      gf_mul(a, gf_pow(gf_mul(a, a), Bitwise.bsr(n, 1)))
    else
      gf_pow(gf_mul(a, a), Bitwise.bsr(n, 1))
    end
  end

  # GF(256) division: a / b = a * b^(-1)
  defp gf_div(_, 0), do: raise("Division by zero in GF(256)")
  defp gf_div(0, _), do: 0
  defp gf_div(a, b), do: gf_mul(a, gf_inv(b))
end
