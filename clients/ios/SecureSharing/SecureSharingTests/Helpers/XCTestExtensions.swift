import XCTest
import Combine

// MARK: - XCTestCase Extensions

extension XCTestCase {

    /// Wait for a publisher to emit a value
    func awaitPublisher<T: Publisher>(
        _ publisher: T,
        timeout: TimeInterval = 1.0,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> T.Output where T.Failure == Error {
        var result: Result<T.Output, Error>?
        let expectation = expectation(description: "Awaiting publisher")

        let cancellable = publisher.sink(
            receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    result = .failure(error)
                case .finished:
                    break
                }
                expectation.fulfill()
            },
            receiveValue: { value in
                result = .success(value)
            }
        )

        waitForExpectations(timeout: timeout)
        cancellable.cancel()

        let unwrappedResult = try XCTUnwrap(
            result,
            "Awaited publisher did not produce any output",
            file: file,
            line: line
        )

        return try unwrappedResult.get()
    }

    /// Wait for a publisher that never fails
    func awaitPublisher<T: Publisher>(
        _ publisher: T,
        timeout: TimeInterval = 1.0,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> T.Output where T.Failure == Never {
        var result: T.Output?
        let expectation = expectation(description: "Awaiting publisher")

        let cancellable = publisher.sink { value in
            result = value
            expectation.fulfill()
        }

        waitForExpectations(timeout: timeout)
        cancellable.cancel()

        return try XCTUnwrap(
            result,
            "Awaited publisher did not produce any output",
            file: file,
            line: line
        )
    }

    /// Wait for async task to complete
    func waitForAsync(
        timeout: TimeInterval = 1.0,
        file: StaticString = #file,
        line: UInt = #line,
        task: @escaping () async throws -> Void
    ) {
        let expectation = expectation(description: "Async task")

        Task {
            do {
                try await task()
            } catch {
                XCTFail("Async task failed: \(error)", file: file, line: line)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: timeout)
    }
}

// MARK: - Assertion Helpers

/// Assert that an error is thrown with a specific type
func XCTAssertThrowsError<T, E: Error>(
    _ expression: @autoclosure () async throws -> T,
    of errorType: E.Type,
    file: StaticString = #file,
    line: UInt = #line,
    errorHandler: ((E) -> Void)? = nil
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error of type \(errorType) to be thrown", file: file, line: line)
    } catch let error as E {
        errorHandler?(error)
    } catch {
        XCTFail("Unexpected error type: \(type(of: error)). Expected \(errorType)", file: file, line: line)
    }
}

/// Assert that two dates are equal within a given precision
func XCTAssertDateEqual(
    _ date1: Date?,
    _ date2: Date?,
    precision: TimeInterval = 1.0,
    file: StaticString = #file,
    line: UInt = #line
) {
    guard let d1 = date1, let d2 = date2 else {
        if date1 == nil && date2 == nil {
            return // Both nil, equal
        }
        XCTFail("Dates not equal: \(String(describing: date1)) vs \(String(describing: date2))", file: file, line: line)
        return
    }

    let diff = abs(d1.timeIntervalSince(d2))
    XCTAssertLessThanOrEqual(diff, precision, "Dates differ by \(diff) seconds", file: file, line: line)
}

/// Assert that a string contains a substring
func XCTAssertContains(
    _ string: String?,
    _ substring: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    guard let string = string else {
        XCTFail("String is nil, expected to contain: \(substring)", file: file, line: line)
        return
    }
    XCTAssertTrue(string.contains(substring), "String '\(string)' does not contain '\(substring)'", file: file, line: line)
}

/// Assert that a collection is empty
func XCTAssertEmpty<T: Collection>(
    _ collection: T,
    _ message: String = "Collection should be empty",
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertTrue(collection.isEmpty, message, file: file, line: line)
}

/// Assert that a collection is not empty
func XCTAssertNotEmpty<T: Collection>(
    _ collection: T,
    _ message: String = "Collection should not be empty",
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertFalse(collection.isEmpty, message, file: file, line: line)
}

// MARK: - JSON Test Helpers

extension XCTestCase {

    /// Create JSON decoder configured for API responses
    var apiDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Create JSON encoder configured for API requests
    var apiEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Decode JSON string to type
    func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let data = json.data(using: .utf8)!
        return try apiDecoder.decode(type, from: data)
    }

    /// Encode object to JSON string
    func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try apiEncoder.encode(value)
        return String(data: data, encoding: .utf8)!
    }
}
