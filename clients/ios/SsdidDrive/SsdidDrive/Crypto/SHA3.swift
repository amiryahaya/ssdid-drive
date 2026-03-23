import Foundation
import KazSignNative

/// SHA3-256 hash utility using the KazSign native library.
/// Output: 32 bytes (256 bits), same size as SHA-256.
enum SHA3_256 {
    /// Compute SHA3-256 hash of input data.
    static func hash(data input: Data) -> Data {
        var output = Data(count: 32)
        let result = input.withUnsafeBytes { inputPtr in
            output.withUnsafeMutableBytes { outputPtr in
                kaz_sha3_256(
                    inputPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    UInt64(input.count),
                    outputPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                )
            }
        }
        precondition(result == 0, "SHA3-256 hash failed with code \(result)")
        return output
    }
}
