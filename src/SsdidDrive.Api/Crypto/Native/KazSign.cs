/*
 * KAZ-SIGN C# Wrapper
 * Version 2.0.0
 *
 * P/Invoke bindings for the KAZ-SIGN post-quantum digital signature library.
 * Supports runtime security level selection (128, 192, and 256).
 *
 * Usage:
 *   using Antrapol.Kaz.Sign;
 *
 *   var signer = new KazSigner(SecurityLevel.Level128);
 *   signer.GenerateKeyPair(out byte[] publicKey, out byte[] secretKey);
 *   byte[] signature = signer.Sign(message, secretKey);
 *   bool valid = signer.Verify(signature, publicKey, out byte[] recoveredMessage);
 *
 *   // Detached signatures
 *   byte[] sig = signer.SignDetached(data, secretKey);
 *   bool ok = signer.VerifyDetached(data, sig, publicKey);
 *
 *   // SHA-256
 *   byte[] hash = KazSigner.Sha3_256(data);
 *
 *   // DER encoding, X.509 certificates, PKCS#12 keystores
 */

using System;
using System.Runtime.InteropServices;

namespace Antrapol.Kaz.Sign
{
    /// <summary>
    /// Security level for KAZ-SIGN operations
    /// </summary>
    public enum SecurityLevel
    {
        /// <summary>128-bit security (SHA-256)</summary>
        Level128 = 128,
        /// <summary>192-bit security (SHA-384)</summary>
        Level192 = 192,
        /// <summary>256-bit security (SHA-512)</summary>
        Level256 = 256
    }

    /// <summary>
    /// Error codes returned by KAZ-SIGN operations
    /// </summary>
    public enum KazSignError
    {
        /// <summary>Operation successful</summary>
        Success = 0,
        /// <summary>Memory allocation failed</summary>
        MemoryError = -1,
        /// <summary>Random number generation failed</summary>
        RngError = -2,
        /// <summary>Invalid parameter</summary>
        InvalidParameter = -3,
        /// <summary>Signature verification failed</summary>
        VerificationFailed = -4,
        /// <summary>DER encoding/decoding failed</summary>
        DerError = -5,
        /// <summary>X.509 certificate operation failed</summary>
        X509Error = -6,
        /// <summary>PKCS#12 operation failed</summary>
        P12Error = -7,
        /// <summary>Hash operation failed</summary>
        HashError = -8,
        /// <summary>Buffer too small</summary>
        BufferError = -9
    }

    /// <summary>
    /// Parameters for each security level
    /// Note: Size constants must be kept in sync with include/kaz/sign.h
    /// </summary>
    public static class KazSignParameters
    {
        /// <summary>Get secret key size in bytes for the given security level (s || t)</summary>
        public static int GetSecretKeyBytes(SecurityLevel level) => level switch
        {
            SecurityLevel.Level128 => 32,   // s(16) + t(16)
            SecurityLevel.Level192 => 50,   // s(25) + t(25)
            SecurityLevel.Level256 => 64,   // s(32) + t(32)
            _ => throw new ArgumentException($"Invalid security level: {level}")
        };

        /// <summary>Get public key size in bytes for the given security level (v)</summary>
        public static int GetPublicKeyBytes(SecurityLevel level) => level switch
        {
            SecurityLevel.Level128 => 54,
            SecurityLevel.Level192 => 88,
            SecurityLevel.Level256 => 118,
            _ => throw new ArgumentException($"Invalid security level: {level}")
        };

        /// <summary>Get signature overhead in bytes for the given security level</summary>
        /// <remarks>Values must match KAZ_SIGN_SIGNATURE_OVERHEAD in kaz/sign.h.
        /// Signature = S1 || S2 || S3 (3 equal-size components)</remarks>
        public static int GetSignatureOverhead(SecurityLevel level) => level switch
        {
            SecurityLevel.Level128 => 162,  // 3 * 54
            SecurityLevel.Level192 => 264,  // 3 * 88
            SecurityLevel.Level256 => 354,  // 3 * 118
            _ => throw new ArgumentException($"Invalid security level: {level}")
        };

        /// <summary>Get hash output size in bytes for the given security level</summary>
        public static int GetHashBytes(SecurityLevel level) => level switch
        {
            SecurityLevel.Level128 => 32,  // SHA-256
            SecurityLevel.Level192 => 48,  // SHA-384
            SecurityLevel.Level256 => 64,  // SHA-512
            _ => throw new ArgumentException($"Invalid security level: {level}")
        };

        /// <summary>KazWire header size in bytes</summary>
        public const int WireHeaderBytes = 5;

        /// <summary>Get KazWire-encoded signature size (header + raw sig)</summary>
        public static int GetWireSignatureBytes(SecurityLevel level) =>
            WireHeaderBytes + GetSignatureOverhead(level);
    }

    /// <summary>
    /// Native P/Invoke declarations for KAZ-SIGN library
    /// </summary>
    internal static class NativeMethods
    {
        // Single unified library with runtime level selection
        // On macOS: libkazsign.dylib
        // On Linux: libkazsign.so
        // On Windows: kazsign.dll
        private const string LibName = "libkazsign";

        // ============================================================
        // Version API
        // ============================================================

        [DllImport(LibName, EntryPoint = "kaz_sign_version")]
        public static extern IntPtr Version();

        [DllImport(LibName, EntryPoint = "kaz_sign_version_number")]
        public static extern int VersionNumber();

        // ============================================================
        // Runtime Security Level API (v2.1+)
        // ============================================================

        /// <summary>
        /// Initialize the library for a specific security level.
        /// Can be called multiple times with different levels.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_init_level")]
        public static extern int InitLevel(int level);

        /// <summary>
        /// Clear resources for a specific security level.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_clear_level")]
        public static extern void ClearLevel(int level);

        /// <summary>
        /// Clear resources for all security levels.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_clear_all")]
        public static extern void ClearAll();

        /// <summary>
        /// Generate a key pair for a specific security level.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_keypair_ex")]
        public static extern int KeyPairEx(int level, byte[] pk, byte[] sk);

        /// <summary>
        /// Sign a message with a specific security level.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_signature_ex")]
        public static extern int SignEx(int level, byte[] sig, ref ulong siglen,
            byte[] msg, ulong msglen, byte[] sk);

        /// <summary>
        /// Verify a signature with a specific security level.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_verify_ex")]
        public static extern int VerifyEx(int level, byte[] msg, ref ulong msglen,
            byte[] sig, ulong siglen, byte[] pk);

        /// <summary>
        /// Hash a message with the hash function for a specific security level.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_hash_ex")]
        public static extern int HashEx(int level, byte[] msg, ulong msglen, byte[] hash);

        // ============================================================
        // Legacy API (compile-time level selection) - kept for backwards compatibility
        // Note: These use the compile-time selected security level
        // ============================================================

        [Obsolete("Use InitLevel instead")]
        [DllImport(LibName, EntryPoint = "kaz_sign_init_random")]
        public static extern int InitRandom();

        [Obsolete("Use ClearLevel instead")]
        [DllImport(LibName, EntryPoint = "kaz_sign_clear_random")]
        public static extern void ClearRandom();

        [Obsolete("Use the Ex variant instead")]
        [DllImport(LibName, EntryPoint = "kaz_sign_is_initialized")]
        public static extern int IsInitialized();

        [Obsolete("Use KeyPairEx instead")]
        [DllImport(LibName, EntryPoint = "kaz_sign_keypair")]
        public static extern int KeyPair(byte[] pk, byte[] sk);

        [Obsolete("Use SignEx instead")]
        [DllImport(LibName, EntryPoint = "kaz_sign_signature")]
        public static extern int Sign(byte[] sig, ref ulong siglen, byte[] msg, ulong msglen, byte[] sk);

        [Obsolete("Use VerifyEx instead")]
        [DllImport(LibName, EntryPoint = "kaz_sign_verify")]
        public static extern int Verify(byte[] msg, ref ulong msglen, byte[] sig, ulong siglen, byte[] pk);

        [Obsolete("Use HashEx instead")]
        [DllImport(LibName, EntryPoint = "kaz_sign_hash")]
        public static extern int Hash(byte[] msg, ulong msglen, byte[] hash);

        // ============================================================
        // Detached Signature API (v3.0+)
        // ============================================================

        /// <summary>
        /// Get the detached signature size for a security level.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_detached_sig_bytes")]
        public static extern ulong DetachedSigBytes(int level);

        /// <summary>
        /// Create a detached signature (signature does not include the message).
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_detached_ex")]
        public static extern int DetachedEx(int level, byte[] sig, ref ulong siglen,
            byte[] msg, ulong msglen, byte[] sk);

        /// <summary>
        /// Verify a detached signature.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_verify_detached_ex")]
        public static extern int VerifyDetachedEx(int level, byte[] sig, ulong siglen,
            byte[] msg, ulong msglen, byte[] pk);

        // ============================================================
        // SHA-256 API (v3.0+)
        // ============================================================

        /// <summary>
        /// Compute SHA-256 hash of a message in one shot.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sha3_256")]
        public static extern int Sha3_256(byte[] msg, ulong msglen, byte[] output);

        // ============================================================
        // DER Key Encoding API (v3.0+)
        // ============================================================

        /// <summary>
        /// Encode a public key to DER format.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_pubkey_to_der")]
        public static extern int PubKeyToDer(int level, byte[] pk, byte[] der, ref ulong derlen);

        /// <summary>
        /// Decode a public key from DER format.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_pubkey_from_der")]
        public static extern int PubKeyFromDer(int level, byte[] der, ulong derlen, byte[] pk);

        /// <summary>
        /// Encode a private key to DER format.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_privkey_to_der")]
        public static extern int PrivKeyToDer(int level, byte[] sk, byte[] der, ref ulong derlen);

        /// <summary>
        /// Decode a private key from DER format.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_privkey_from_der")]
        public static extern int PrivKeyFromDer(int level, byte[] der, ulong derlen, byte[] sk);

        // ============================================================
        // X.509 Certificate API (v3.0+)
        // ============================================================

        /// <summary>
        /// Generate a PKCS#10 Certificate Signing Request (CSR).
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_generate_csr")]
        public static extern int GenerateCsr(int level, byte[] sk, byte[] pk,
            [MarshalAs(UnmanagedType.LPStr)] string subject,
            byte[] csr, ref ulong csrlen);

        /// <summary>
        /// Verify a PKCS#10 CSR self-signature.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_verify_csr")]
        public static extern int VerifyCsr(int level, byte[] csr, ulong csrlen);

        /// <summary>
        /// Issue an X.509 certificate by signing a CSR.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_issue_certificate")]
        public static extern int IssueCertificate(int level, byte[] issuerSk, byte[] issuerPk,
            [MarshalAs(UnmanagedType.LPStr)] string issuerName,
            byte[] csr, ulong csrlen, ulong serial, int days,
            byte[] cert, ref ulong certlen);

        /// <summary>
        /// Extract the public key from an X.509 certificate.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_cert_extract_pubkey")]
        public static extern int CertExtractPubKey(int level, byte[] cert, ulong certlen, byte[] pk);

        /// <summary>
        /// Verify an X.509 certificate signature against an issuer public key.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_verify_certificate")]
        public static extern int VerifyCertificate(int level, byte[] cert, ulong certlen, byte[] issuerPk);

        // ============================================================
        // PKCS#12 Keystore API (v3.0+)
        // ============================================================

        /// <summary>
        /// Create a PKCS#12 keystore containing a key pair and optional certificate.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_create_p12")]
        public static extern int CreateP12(int level, byte[] sk, byte[] pk,
            byte[]? cert, ulong certlen,
            [MarshalAs(UnmanagedType.LPStr)] string password,
            [MarshalAs(UnmanagedType.LPStr)] string name,
            byte[] p12, ref ulong p12len);

        /// <summary>
        /// Load a key pair and certificate from a PKCS#12 keystore.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_load_p12")]
        public static extern int LoadP12(int level, byte[] p12, ulong p12len,
            [MarshalAs(UnmanagedType.LPStr)] string password,
            byte[] sk, byte[] pk, byte[]? cert, ref ulong certlen);

        // ============================================================
        // KazWire Encoding API
        // ============================================================

        /// <summary>
        /// Encode a detached signature to KazWire format (5-byte header + raw sig).
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_sig_to_wire")]
        public static extern int SigToWire(int level, byte[] sig, ulong siglen,
            byte[] wire, ref ulong wirelen);

        /// <summary>
        /// Decode a detached signature from KazWire format to raw bytes.
        /// </summary>
        [DllImport(LibName, EntryPoint = "kaz_sign_sig_from_wire")]
        public static extern int SigFromWire(byte[] wire, ulong wirelen,
            ref int level, byte[] sig, ref ulong siglen);
    }

    /// <summary>
    /// Exception thrown when a KAZ-SIGN operation fails
    /// </summary>
    public class KazSignException : Exception
    {
        /// <summary>The error code returned by the native library</summary>
        public KazSignError ErrorCode { get; }

        public KazSignException(KazSignError errorCode)
            : base(GetErrorMessage(errorCode))
        {
            ErrorCode = errorCode;
        }

        public KazSignException(KazSignError errorCode, string message)
            : base(message)
        {
            ErrorCode = errorCode;
        }

        private static string GetErrorMessage(KazSignError error) => error switch
        {
            KazSignError.Success => "Operation successful",
            KazSignError.MemoryError => "Memory allocation failed",
            KazSignError.RngError => "Random number generation failed",
            KazSignError.InvalidParameter => "Invalid parameter",
            KazSignError.VerificationFailed => "Signature verification failed",
            KazSignError.DerError => "DER encoding/decoding failed",
            KazSignError.X509Error => "X.509 certificate operation failed",
            KazSignError.P12Error => "PKCS#12 operation failed",
            KazSignError.HashError => "Hash operation failed",
            KazSignError.BufferError => "Buffer too small",
            _ => $"Unknown error: {(int)error}"
        };
    }

    /// <summary>
    /// Contents loaded from a PKCS#12 keystore
    /// </summary>
    public sealed class P12Contents
    {
        /// <summary>Secret signing key</summary>
        public byte[] SecretKey { get; }

        /// <summary>Public verification key</summary>
        public byte[] PublicKey { get; }

        /// <summary>DER-encoded certificate, or null if not present</summary>
        public byte[]? Certificate { get; }

        public P12Contents(byte[] secretKey, byte[] publicKey, byte[]? certificate)
        {
            SecretKey = secretKey;
            PublicKey = publicKey;
            Certificate = certificate;
        }
    }

    /// <summary>
    /// KAZ-SIGN digital signature operations with runtime security level selection.
    /// </summary>
    public sealed class KazSigner : IDisposable
    {
        private readonly SecurityLevel _level;
        private bool _initialized;
        private bool _disposed;

        /// <summary>
        /// Create a new KazSigner with the specified security level.
        /// </summary>
        /// <param name="level">Security level (128, 192, or 256)</param>
        /// <param name="autoInitialize">If true, automatically initialize for this level</param>
        public KazSigner(SecurityLevel level, bool autoInitialize = true)
        {
            _level = level;
            if (autoInitialize)
            {
                Initialize();
            }
        }

        /// <summary>The security level being used</summary>
        public SecurityLevel Level => _level;

        /// <summary>Size of secret key in bytes</summary>
        public int SecretKeyBytes => KazSignParameters.GetSecretKeyBytes(_level);

        /// <summary>Size of public key in bytes</summary>
        public int PublicKeyBytes => KazSignParameters.GetPublicKeyBytes(_level);

        /// <summary>Signature overhead in bytes (excluding message)</summary>
        public int SignatureOverhead => KazSignParameters.GetSignatureOverhead(_level);

        /// <summary>Hash output size in bytes</summary>
        public int HashBytes => KazSignParameters.GetHashBytes(_level);

        /// <summary>
        /// Initialize the library for this security level.
        /// </summary>
        public void Initialize()
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (_initialized) return;

            int result = NativeMethods.InitLevel((int)_level);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }
            _initialized = true;
        }

        /// <summary>
        /// Check if the library is initialized for this level.
        /// </summary>
        public bool IsInitialized()
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            return _initialized;
        }

        /// <summary>
        /// Generate a new key pair.
        /// </summary>
        /// <param name="publicKey">Output: public verification key</param>
        /// <param name="secretKey">Output: secret signing key</param>
        public void GenerateKeyPair(out byte[] publicKey, out byte[] secretKey)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            EnsureInitialized();

            publicKey = new byte[PublicKeyBytes];
            secretKey = new byte[SecretKeyBytes];

            int result = NativeMethods.KeyPairEx((int)_level, publicKey, secretKey);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }
        }

        /// <summary>
        /// Sign a message.
        /// </summary>
        /// <param name="message">Message to sign</param>
        /// <param name="secretKey">Secret signing key</param>
        /// <returns>Signature (includes the message)</returns>
        public byte[] Sign(byte[] message, byte[] secretKey)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (message == null) throw new ArgumentNullException(nameof(message));
            if (secretKey == null) throw new ArgumentNullException(nameof(secretKey));
            if (secretKey.Length != SecretKeyBytes)
                throw new ArgumentException($"Secret key must be {SecretKeyBytes} bytes", nameof(secretKey));
            EnsureInitialized();

            byte[] signature = new byte[SignatureOverhead + message.Length];
            ulong siglen = 0;

            int result = NativeMethods.SignEx((int)_level, signature, ref siglen,
                message, (ulong)message.Length, secretKey);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            // Resize to actual length if different
            if ((int)siglen != signature.Length)
            {
                Array.Resize(ref signature, (int)siglen);
            }

            return signature;
        }

        /// <summary>
        /// Verify a signature and extract the message.
        /// </summary>
        /// <param name="signature">Signature to verify (includes the message)</param>
        /// <param name="publicKey">Public verification key</param>
        /// <param name="message">Output: extracted message if valid</param>
        /// <returns>True if signature is valid, false otherwise</returns>
        public bool Verify(byte[] signature, byte[] publicKey, out byte[] message)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (signature == null) throw new ArgumentNullException(nameof(signature));
            if (publicKey == null) throw new ArgumentNullException(nameof(publicKey));
            if (publicKey.Length != PublicKeyBytes)
                throw new ArgumentException($"Public key must be {PublicKeyBytes} bytes", nameof(publicKey));

            // Message can be at most signature length minus overhead
            int maxMsgLen = signature.Length - SignatureOverhead;
            if (maxMsgLen < 0)
            {
                message = Array.Empty<byte>();
                return false;
            }

            byte[] msgBuffer = new byte[maxMsgLen];
            ulong msglen = 0;

            int result = NativeMethods.VerifyEx((int)_level, msgBuffer, ref msglen,
                signature, (ulong)signature.Length, publicKey);

            if (result != (int)KazSignError.Success)
            {
                message = Array.Empty<byte>();
                return false;
            }

            message = new byte[msglen];
            Array.Copy(msgBuffer, message, (int)msglen);
            return true;
        }

        /// <summary>
        /// Hash a message using the appropriate hash function for this security level.
        /// </summary>
        /// <param name="message">Message to hash</param>
        /// <returns>Hash value</returns>
        public byte[] Hash(byte[] message)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (message == null) throw new ArgumentNullException(nameof(message));

            byte[] hash = new byte[HashBytes];

            int result = NativeMethods.HashEx((int)_level, message, (ulong)message.Length, hash);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            return hash;
        }

        /// <summary>
        /// Create a detached signature (signature does not include the message).
        /// </summary>
        /// <param name="data">Data to sign</param>
        /// <param name="secretKey">Secret signing key</param>
        /// <returns>Detached signature</returns>
        public byte[] SignDetached(byte[] data, byte[] secretKey)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (data == null) throw new ArgumentNullException(nameof(data));
            if (secretKey == null) throw new ArgumentNullException(nameof(secretKey));
            if (secretKey.Length != SecretKeyBytes)
                throw new ArgumentException($"Secret key must be {SecretKeyBytes} bytes", nameof(secretKey));
            EnsureInitialized();

            ulong sigBytes = NativeMethods.DetachedSigBytes((int)_level);
            byte[] signature = new byte[sigBytes];
            ulong siglen = 0;

            int result = NativeMethods.DetachedEx((int)_level, signature, ref siglen,
                data, (ulong)data.Length, secretKey);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            if ((int)siglen != signature.Length)
            {
                Array.Resize(ref signature, (int)siglen);
            }

            return signature;
        }

        /// <summary>
        /// Verify a detached signature.
        /// </summary>
        /// <param name="data">Original data that was signed</param>
        /// <param name="signature">Detached signature to verify</param>
        /// <param name="publicKey">Public verification key</param>
        /// <returns>True if signature is valid, false otherwise</returns>
        public bool VerifyDetached(byte[] data, byte[] signature, byte[] publicKey)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (data == null) throw new ArgumentNullException(nameof(data));
            if (signature == null) throw new ArgumentNullException(nameof(signature));
            if (publicKey == null) throw new ArgumentNullException(nameof(publicKey));
            if (publicKey.Length != PublicKeyBytes)
                throw new ArgumentException($"Public key must be {PublicKeyBytes} bytes", nameof(publicKey));
            EnsureInitialized();

            int result = NativeMethods.VerifyDetachedEx((int)_level, signature, (ulong)signature.Length,
                data, (ulong)data.Length, publicKey);

            return result == (int)KazSignError.Success;
        }

        /// <summary>
        /// Compute SHA-256 hash of data.
        /// </summary>
        /// <param name="data">Data to hash</param>
        /// <returns>32-byte SHA-256 hash</returns>
        public static byte[] Sha3_256(byte[] data)
        {
            if (data == null) throw new ArgumentNullException(nameof(data));

            byte[] hash = new byte[32];

            int result = NativeMethods.Sha3_256(data, (ulong)data.Length, hash);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            return hash;
        }

        /// <summary>
        /// Encode a public key to DER format.
        /// </summary>
        /// <param name="publicKey">Raw public key</param>
        /// <returns>DER-encoded public key</returns>
        public byte[] PublicKeyToDer(byte[] publicKey)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (publicKey == null) throw new ArgumentNullException(nameof(publicKey));
            if (publicKey.Length != PublicKeyBytes)
                throw new ArgumentException($"Public key must be {PublicKeyBytes} bytes", nameof(publicKey));
            EnsureInitialized();

            // Allocate generous buffer for DER encoding
            byte[] der = new byte[PublicKeyBytes + 128];
            ulong derlen = (ulong)der.Length;

            int result = NativeMethods.PubKeyToDer((int)_level, publicKey, der, ref derlen);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            if ((int)derlen != der.Length)
            {
                Array.Resize(ref der, (int)derlen);
            }

            return der;
        }

        /// <summary>
        /// Decode a public key from DER format.
        /// </summary>
        /// <param name="der">DER-encoded public key</param>
        /// <returns>Raw public key</returns>
        public byte[] PublicKeyFromDer(byte[] der)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (der == null) throw new ArgumentNullException(nameof(der));
            EnsureInitialized();

            byte[] pk = new byte[PublicKeyBytes];

            int result = NativeMethods.PubKeyFromDer((int)_level, der, (ulong)der.Length, pk);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            return pk;
        }

        /// <summary>
        /// Encode a private key to DER format.
        /// </summary>
        /// <param name="secretKey">Raw secret key</param>
        /// <returns>DER-encoded private key</returns>
        public byte[] PrivateKeyToDer(byte[] secretKey)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (secretKey == null) throw new ArgumentNullException(nameof(secretKey));
            if (secretKey.Length != SecretKeyBytes)
                throw new ArgumentException($"Secret key must be {SecretKeyBytes} bytes", nameof(secretKey));
            EnsureInitialized();

            // Allocate generous buffer for DER encoding
            byte[] der = new byte[SecretKeyBytes + 128];
            ulong derlen = (ulong)der.Length;

            int result = NativeMethods.PrivKeyToDer((int)_level, secretKey, der, ref derlen);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            if ((int)derlen != der.Length)
            {
                Array.Resize(ref der, (int)derlen);
            }

            return der;
        }

        /// <summary>
        /// Decode a private key from DER format.
        /// </summary>
        /// <param name="der">DER-encoded private key</param>
        /// <returns>Raw secret key</returns>
        public byte[] PrivateKeyFromDer(byte[] der)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (der == null) throw new ArgumentNullException(nameof(der));
            EnsureInitialized();

            byte[] sk = new byte[SecretKeyBytes];

            int result = NativeMethods.PrivKeyFromDer((int)_level, der, (ulong)der.Length, sk);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            return sk;
        }

        /// <summary>
        /// Generate a PKCS#10 Certificate Signing Request (CSR).
        /// </summary>
        /// <param name="secretKey">Secret signing key</param>
        /// <param name="publicKey">Public key</param>
        /// <param name="cn">Common Name (CN)</param>
        /// <param name="org">Organization (O), or null to omit</param>
        /// <param name="ou">Organizational Unit (OU), or null to omit</param>
        /// <returns>DER-encoded CSR</returns>
        public byte[] GenerateCsr(byte[] secretKey, byte[] publicKey, string cn, string? org, string? ou)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (secretKey == null) throw new ArgumentNullException(nameof(secretKey));
            if (publicKey == null) throw new ArgumentNullException(nameof(publicKey));
            if (cn == null) throw new ArgumentNullException(nameof(cn));
            if (secretKey.Length != SecretKeyBytes)
                throw new ArgumentException($"Secret key must be {SecretKeyBytes} bytes", nameof(secretKey));
            if (publicKey.Length != PublicKeyBytes)
                throw new ArgumentException($"Public key must be {PublicKeyBytes} bytes", nameof(publicKey));
            EnsureInitialized();

            // Build subject distinguished name
            string subject = $"CN={cn}";
            if (org != null) subject += $"/O={org}";
            if (ou != null) subject += $"/OU={ou}";

            byte[] csr = new byte[4096];
            ulong csrlen = (ulong)csr.Length;

            int result = NativeMethods.GenerateCsr((int)_level, secretKey, publicKey, subject,
                csr, ref csrlen);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            if ((int)csrlen != csr.Length)
            {
                Array.Resize(ref csr, (int)csrlen);
            }

            return csr;
        }

        /// <summary>
        /// Verify a PKCS#10 CSR self-signature.
        /// </summary>
        /// <param name="csr">DER-encoded CSR</param>
        /// <returns>True if the CSR signature is valid, false otherwise</returns>
        public bool VerifyCsr(byte[] csr)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (csr == null) throw new ArgumentNullException(nameof(csr));
            EnsureInitialized();

            int result = NativeMethods.VerifyCsr((int)_level, csr, (ulong)csr.Length);

            return result == (int)KazSignError.Success;
        }

        /// <summary>
        /// Issue an X.509 certificate by signing a CSR.
        /// </summary>
        /// <param name="issuerSk">Issuer secret key</param>
        /// <param name="issuerPk">Issuer public key</param>
        /// <param name="issuerName">Issuer distinguished name (e.g., "CN=Root CA")</param>
        /// <param name="csr">DER-encoded CSR from the subject</param>
        /// <param name="serial">Certificate serial number</param>
        /// <param name="days">Validity period in days</param>
        /// <returns>DER-encoded certificate</returns>
        public byte[] IssueCertificate(byte[] issuerSk, byte[] issuerPk, string issuerName,
            byte[] csr, ulong serial, int days)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (issuerSk == null) throw new ArgumentNullException(nameof(issuerSk));
            if (issuerPk == null) throw new ArgumentNullException(nameof(issuerPk));
            if (issuerName == null) throw new ArgumentNullException(nameof(issuerName));
            if (csr == null) throw new ArgumentNullException(nameof(csr));
            if (issuerSk.Length != SecretKeyBytes)
                throw new ArgumentException($"Issuer secret key must be {SecretKeyBytes} bytes", nameof(issuerSk));
            if (issuerPk.Length != PublicKeyBytes)
                throw new ArgumentException($"Issuer public key must be {PublicKeyBytes} bytes", nameof(issuerPk));
            EnsureInitialized();

            byte[] cert = new byte[8192];
            ulong certlen = (ulong)cert.Length;

            int result = NativeMethods.IssueCertificate((int)_level, issuerSk, issuerPk, issuerName,
                csr, (ulong)csr.Length, serial, days, cert, ref certlen);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            if ((int)certlen != cert.Length)
            {
                Array.Resize(ref cert, (int)certlen);
            }

            return cert;
        }

        /// <summary>
        /// Verify an X.509 certificate signature against an issuer public key.
        /// </summary>
        /// <param name="cert">DER-encoded certificate</param>
        /// <param name="issuerPk">Issuer public key</param>
        /// <returns>True if the certificate signature is valid, false otherwise</returns>
        public bool VerifyCertificate(byte[] cert, byte[] issuerPk)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (cert == null) throw new ArgumentNullException(nameof(cert));
            if (issuerPk == null) throw new ArgumentNullException(nameof(issuerPk));
            if (issuerPk.Length != PublicKeyBytes)
                throw new ArgumentException($"Issuer public key must be {PublicKeyBytes} bytes", nameof(issuerPk));
            EnsureInitialized();

            int result = NativeMethods.VerifyCertificate((int)_level, cert, (ulong)cert.Length, issuerPk);

            return result == (int)KazSignError.Success;
        }

        /// <summary>
        /// Extract the public key from an X.509 certificate.
        /// </summary>
        /// <param name="cert">DER-encoded certificate</param>
        /// <returns>Extracted public key</returns>
        public byte[] ExtractPublicKey(byte[] cert)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (cert == null) throw new ArgumentNullException(nameof(cert));
            EnsureInitialized();

            byte[] pk = new byte[PublicKeyBytes];

            int result = NativeMethods.CertExtractPubKey((int)_level, cert, (ulong)cert.Length, pk);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            return pk;
        }

        /// <summary>
        /// Create a PKCS#12 keystore containing a key pair and optional certificate.
        /// </summary>
        /// <param name="secretKey">Secret key</param>
        /// <param name="publicKey">Public key</param>
        /// <param name="cert">DER-encoded certificate, or null</param>
        /// <param name="password">Password to protect the keystore</param>
        /// <param name="name">Friendly name for the key entry</param>
        /// <returns>PKCS#12 data</returns>
        public byte[] CreateP12(byte[] secretKey, byte[] publicKey, byte[]? cert, string password, string name)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (secretKey == null) throw new ArgumentNullException(nameof(secretKey));
            if (publicKey == null) throw new ArgumentNullException(nameof(publicKey));
            if (password == null) throw new ArgumentNullException(nameof(password));
            if (name == null) throw new ArgumentNullException(nameof(name));
            if (secretKey.Length != SecretKeyBytes)
                throw new ArgumentException($"Secret key must be {SecretKeyBytes} bytes", nameof(secretKey));
            if (publicKey.Length != PublicKeyBytes)
                throw new ArgumentException($"Public key must be {PublicKeyBytes} bytes", nameof(publicKey));
            EnsureInitialized();

            ulong certlen = cert != null ? (ulong)cert.Length : 0;

            byte[] p12 = new byte[8192];
            ulong p12len = (ulong)p12.Length;

            int result = NativeMethods.CreateP12((int)_level, secretKey, publicKey,
                cert, certlen, password, name, p12, ref p12len);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            if ((int)p12len != p12.Length)
            {
                Array.Resize(ref p12, (int)p12len);
            }

            return p12;
        }

        /// <summary>
        /// Load a key pair and certificate from a PKCS#12 keystore.
        /// </summary>
        /// <param name="p12">PKCS#12 data</param>
        /// <param name="password">Password to unlock the keystore</param>
        /// <returns>Loaded key pair and optional certificate</returns>
        public P12Contents LoadP12(byte[] p12, string password)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (p12 == null) throw new ArgumentNullException(nameof(p12));
            if (password == null) throw new ArgumentNullException(nameof(password));
            EnsureInitialized();

            byte[] sk = new byte[SecretKeyBytes];
            byte[] pk = new byte[PublicKeyBytes];
            byte[] certBuf = new byte[8192];
            ulong certlen = (ulong)certBuf.Length;

            int result = NativeMethods.LoadP12((int)_level, p12, (ulong)p12.Length, password,
                sk, pk, certBuf, ref certlen);

            if (result != (int)KazSignError.Success)
            {
                throw new KazSignException((KazSignError)result);
            }

            byte[]? cert = null;
            if (certlen > 0)
            {
                cert = new byte[certlen];
                Array.Copy(certBuf, cert, (int)certlen);
            }

            return new P12Contents(sk, pk, cert);
        }

        /// <summary>
        /// Encode a raw detached signature to KazWire format (5-byte header + raw sig).
        /// </summary>
        public byte[] SignatureToWire(byte[] signature)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(KazSigner));
            if (signature == null) throw new ArgumentNullException(nameof(signature));
            EnsureInitialized();

            int wireSize = KazSignParameters.GetWireSignatureBytes(_level);
            byte[] wire = new byte[wireSize];
            ulong wireLen = (ulong)wireSize;

            int result = NativeMethods.SigToWire((int)_level, signature, (ulong)signature.Length,
                wire, ref wireLen);

            if (result != (int)KazSignError.Success)
                throw new KazSignException((KazSignError)result);

            if ((int)wireLen != wire.Length)
                Array.Resize(ref wire, (int)wireLen);

            return wire;
        }

        /// <summary>
        /// Decode a detached signature from KazWire format to raw bytes.
        /// </summary>
        public static (byte[] Signature, SecurityLevel Level) SignatureFromWire(byte[] wire)
        {
            if (wire == null) throw new ArgumentNullException(nameof(wire));
            if (wire.Length < KazSignParameters.WireHeaderBytes)
                throw new ArgumentException("Wire data too short", nameof(wire));

            int level = 0;
            byte[] sig = new byte[wire.Length];
            ulong sigLen = (ulong)sig.Length;

            int result = NativeMethods.SigFromWire(wire, (ulong)wire.Length,
                ref level, sig, ref sigLen);

            if (result != (int)KazSignError.Success)
                throw new KazSignException((KazSignError)result);

            if ((int)sigLen != sig.Length)
                Array.Resize(ref sig, (int)sigLen);

            return (sig, (SecurityLevel)level);
        }

        /// <summary>
        /// Get the library version string.
        /// </summary>
        public string GetVersion()
        {
            IntPtr ptr = NativeMethods.Version();
            return ptr != IntPtr.Zero ? Marshal.PtrToStringAnsi(ptr) ?? "unknown" : "unknown";
        }

        /// <summary>
        /// Get the library version number.
        /// </summary>
        public int GetVersionNumber()
        {
            return NativeMethods.VersionNumber();
        }

        private void EnsureInitialized()
        {
            if (!_initialized)
            {
                throw new InvalidOperationException("KazSigner not initialized. Call Initialize() first or set autoInitialize=true in constructor.");
            }
        }

        /// <summary>
        /// Clear resources for this security level.
        /// </summary>
        public void Dispose()
        {
            if (_disposed) return;

            if (_initialized)
            {
                NativeMethods.ClearLevel((int)_level);
                _initialized = false;
            }

            _disposed = true;
        }

        /// <summary>
        /// Clear all security level resources. Call when completely done with KAZ-SIGN.
        /// </summary>
        public static void ClearAll()
        {
            NativeMethods.ClearAll();
        }
    }
}
