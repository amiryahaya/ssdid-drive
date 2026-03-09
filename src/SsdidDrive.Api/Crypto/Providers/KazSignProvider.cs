using Antrapol.Kaz.Sign;

namespace SsdidDrive.Api.Crypto.Providers;

/// <summary>
/// KAZ-Sign provider using the native C library.
/// Public keys are SPKI-encoded (X.509 SubjectPublicKeyInfo with OID 1.3.6.1.4.1.62395.1.1.2)
/// containing raw V bytes — matching the deployed Java JCA KAZ-SIGN provider.
/// Signatures are KazWire-encoded (5-byte header + S1 + S2).
/// Private keys are stored as raw bytes (local-only).
/// </summary>
public class KazSignProvider : ICryptoProvider, IDisposable
{
    public string Family => "KazSign";

    private const SecurityLevel DefaultLevel = SecurityLevel.Level128;

    /// <summary>
    /// OID 1.3.6.1.4.1.62395.1.1.2 encoded as DER value bytes.
    /// </summary>
    private static readonly byte[] OidPubKeyValue =
    {
        0x2B, 0x06, 0x01, 0x04, 0x01, 0x83, 0xE7, 0x3B, 0x01, 0x01, 0x02
    };

    public (byte[] PublicKey, byte[] PrivateKey) GenerateKeyPair(string? variant = null)
    {
        var level = ParseLevel(variant);
        using var signer = new KazSigner(level);
        signer.GenerateKeyPair(out var rawPublicKey, out var secretKey);
        var spkiPublicKey = WrapInSpki(rawPublicKey);
        return (spkiPublicKey, secretKey);
    }

    public byte[] Sign(byte[] message, byte[] privateKey, string? variant = null)
    {
        var level = ParseLevel(variant);
        using var signer = new KazSigner(level);
        var rawSig = signer.SignDetached(message, privateKey);
        return signer.SignatureToWire(rawSig);
    }

    public bool Verify(byte[] message, byte[] signature, byte[] publicKey, string? variant = null)
    {
        try
        {
            byte[] rawPk;
            byte[] rawSig;

            // Extract raw public key from SPKI or use as-is
            if (IsSpkiEncoded(publicKey))
                rawPk = UnwrapFromSpki(publicKey);
            else
                rawPk = publicKey;

            // Extract raw signature from KazWire or use as-is
            if (IsKazWireSignature(signature))
                rawSig = KazSigner.SignatureFromWire(signature).Signature;
            else
                rawSig = signature;

            var level = InferLevelFromRawPublicKey(rawPk);
            using var signer = new KazSigner(level);
            return signer.VerifyDetached(message, rawSig, rawPk);
        }
        catch (KazSignException)
        {
            return false;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    /// <summary>
    /// Wrap raw public key bytes in SubjectPublicKeyInfo (SPKI) DER format.
    /// The BIT STRING contains KazWire-encoded bytes (5-byte header + raw V)
    /// to match the Java JCAJCE v2.0 convention.
    ///
    /// Structure:
    ///   SEQUENCE {
    ///     SEQUENCE { OID 1.3.6.1.4.1.62395.1.1.2 }   -- AlgorithmIdentifier
    ///     BIT STRING { 0x00, kazwire_header, raw_pk }  -- subjectPublicKey
    ///   }
    /// </summary>
    private static byte[] WrapInSpki(byte[] rawPk)
    {
        // Build KazWire public key: 5-byte header + raw V bytes
        var kazWirePk = new byte[5 + rawPk.Length];
        kazWirePk[0] = 0x67; // magic hi
        kazWirePk[1] = 0x52; // magic lo
        kazWirePk[2] = InferWireAlgByte(rawPk); // alg byte
        kazWirePk[3] = 0x02; // type = PUB
        kazWirePk[4] = 0x01; // version
        Array.Copy(rawPk, 0, kazWirePk, 5, rawPk.Length);

        // AlgorithmIdentifier: SEQUENCE { OID }
        // OID TLV: 06 0B [11 bytes] = 13 bytes
        // AlgID: 30 0D [13 bytes] = 15 bytes
        const int oidTlvLen = 2 + 11; // tag + length + value = 13
        const int algIdLen = 2 + oidTlvLen; // SEQUENCE tag + length + OID TLV = 15

        // BIT STRING content: unused-bits(1) + kazWirePk
        int bitStrContent = 1 + kazWirePk.Length;
        int bitStrLenSize = DerLengthSize(bitStrContent);
        int bitStrTlv = 1 + bitStrLenSize + bitStrContent;

        // Outer SEQUENCE content: AlgID + BIT STRING TLV
        int seqContent = algIdLen + bitStrTlv;
        int seqLenSize = DerLengthSize(seqContent);
        int totalLen = 1 + seqLenSize + seqContent;

        var der = new byte[totalLen];
        int p = 0;

        // Outer SEQUENCE
        der[p++] = 0x30;
        WriteDerLength(der, ref p, seqContent);

        // AlgorithmIdentifier SEQUENCE (lengths always < 128)
        der[p++] = 0x30;
        der[p++] = (byte)oidTlvLen;

        // OID tag + length + value
        der[p++] = 0x06;
        der[p++] = (byte)OidPubKeyValue.Length;
        Array.Copy(OidPubKeyValue, 0, der, p, OidPubKeyValue.Length);
        p += OidPubKeyValue.Length;

        // BIT STRING
        der[p++] = 0x03;
        WriteDerLength(der, ref p, bitStrContent);
        der[p++] = 0x00; // unused bits
        Array.Copy(kazWirePk, 0, der, p, kazWirePk.Length);

        return der;
    }

    /// <summary>
    /// Compute how many bytes a DER length field requires.
    /// </summary>
    private static int DerLengthSize(int length) =>
        length < 128 ? 1 : length <= 0xFF ? 2 : 3;

    /// <summary>
    /// Write a DER length field (supports short and long form).
    /// </summary>
    private static void WriteDerLength(byte[] buf, ref int p, int length)
    {
        if (length < 128)
        {
            buf[p++] = (byte)length;
        }
        else if (length <= 0xFF)
        {
            buf[p++] = 0x81;
            buf[p++] = (byte)length;
        }
        else
        {
            buf[p++] = 0x82;
            buf[p++] = (byte)(length >> 8);
            buf[p++] = (byte)length;
        }
    }

    /// <summary>
    /// Infer KazWire algorithm byte from raw public key size.
    /// Sizes must match KazSignParameters.GetPublicKeyBytes().
    /// </summary>
    private static byte InferWireAlgByte(byte[] rawPk) => rawPk.Length switch
    {
        54 => 0x01,   // SIGN_128
        88 => 0x02,   // SIGN_192
        118 => 0x03,  // SIGN_256
        _ => throw new ArgumentException($"Cannot infer KAZ-Sign algorithm from public key size: {rawPk.Length}")
    };

    /// <summary>
    /// Extract raw public key bytes from SPKI DER encoding.
    /// The BIT STRING contains KazWire-encoded bytes (5-byte header + raw V).
    /// We strip both the SPKI wrapper and the KazWire header.
    /// </summary>
    private static byte[] UnwrapFromSpki(byte[] spki)
    {
        // Parse: SEQUENCE { SEQUENCE { OID } BIT_STRING { 00 kazwire_pk } }
        int p = 0;

        // Outer SEQUENCE
        if (spki[p++] != 0x30) throw new ArgumentException("Invalid SPKI: not a SEQUENCE");
        p += ReadDerLength(spki, p, out _);

        // Skip AlgorithmIdentifier SEQUENCE
        if (spki[p] != 0x30) throw new ArgumentException("Invalid SPKI: missing AlgorithmIdentifier");
        p++; // tag
        p += ReadDerLength(spki, p, out var algIdContentLen);
        p += (int)algIdContentLen; // skip AlgID content

        // BIT STRING
        if (spki[p++] != 0x03) throw new ArgumentException("Invalid SPKI: missing BIT STRING");
        p += ReadDerLength(spki, p, out var bitStrContentLen);
        if (spki[p++] != 0x00) throw new ArgumentException("Invalid SPKI: non-zero unused bits");

        int payloadLen = (int)bitStrContentLen - 1;

        // Check for KazWire header (0x67 0x52) and strip it
        if (payloadLen > 5 && spki[p] == 0x67 && spki[p + 1] == 0x52)
        {
            // Skip 5-byte KazWire header
            int rawLen = payloadLen - 5;
            var raw = new byte[rawLen];
            Array.Copy(spki, p + 5, raw, 0, rawLen);
            return raw;
        }

        // No KazWire header — return as-is (backwards compat)
        var result = new byte[payloadLen];
        Array.Copy(spki, p, result, 0, payloadLen);
        return result;
    }

    /// <summary>
    /// Read a DER length field. Returns the number of bytes consumed.
    /// </summary>
    private static int ReadDerLength(byte[] data, int offset, out long length)
    {
        byte b = data[offset];
        if (b < 128)
        {
            length = b;
            return 1;
        }

        int numBytes = b & 0x7F;
        length = 0;
        for (int i = 0; i < numBytes; i++)
            length = (length << 8) | data[offset + 1 + i];
        return 1 + numBytes;
    }

    /// <summary>
    /// SPKI-encoded public keys start with ASN.1 SEQUENCE tag (0x30).
    /// </summary>
    /// <summary>
    /// SPKI-encoded public keys start with outer SEQUENCE (0x30) followed by
    /// an inner AlgorithmIdentifier SEQUENCE (0x30). Raw KAZ-Sign keys are
    /// 54/88/118 bytes and never start with 0x30.
    /// </summary>
    private static bool IsSpkiEncoded(byte[] data)
    {
        if (data.Length <= 60 || data[0] != 0x30)
            return false;

        // Skip outer SEQUENCE tag + length to check for inner AlgorithmIdentifier tag.
        int p = 1;
        if (data[p] < 0x80)
            p += 1;
        else
            p += 1 + (data[p] & 0x7F);

        return p < data.Length && data[p] == 0x30;
    }

    /// <summary>
    /// KazWire signatures start with magic bytes 0x67 0x52.
    /// </summary>
    private static bool IsKazWireSignature(byte[] data) =>
        data.Length >= 5 && data[0] == 0x67 && data[1] == 0x52;

    private static SecurityLevel ParseLevel(string? variant) => variant switch
    {
        "128" => SecurityLevel.Level128,
        "192" => SecurityLevel.Level192,
        "256" => SecurityLevel.Level256,
        null => DefaultLevel,
        _ => throw new ArgumentException($"Unsupported KAZ-Sign variant: {variant}")
    };

    private static SecurityLevel InferLevelFromRawPublicKey(byte[] publicKey) => publicKey.Length switch
    {
        54 => SecurityLevel.Level128,
        88 => SecurityLevel.Level192,
        118 => SecurityLevel.Level256,
        _ => throw new ArgumentException($"Cannot infer KAZ-Sign level from public key size: {publicKey.Length}")
    };

    public void Dispose() { }
}
