import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for BaseViewModel error handling
@MainActor
final class BaseViewModelTests: XCTestCase {

    // MARK: - Concrete Subclass for Testing

    final class TestableViewModel: BaseViewModel {
        func triggerError(_ error: Error) {
            handleError(error)
        }
    }

    // MARK: - Properties

    var viewModel: TestableViewModel!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        viewModel = TestableViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - handleError Tests

    func testHandleError_apiError_setsErrorDescription() {
        // Given
        let apiError = APIClient.APIError.notFound

        // When
        viewModel.triggerError(apiError)

        // Then
        XCTAssertEqual(viewModel.errorMessage, apiError.errorDescription)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testHandleError_apiError_unauthorized() {
        let apiError = APIClient.APIError.unauthorized
        viewModel.triggerError(apiError)
        XCTAssertEqual(viewModel.errorMessage, "Unauthorized - please log in again")
    }

    func testHandleError_apiError_httpError() {
        let apiError = APIClient.APIError.httpError(statusCode: 500, message: "Internal server error")
        viewModel.triggerError(apiError)
        XCTAssertEqual(viewModel.errorMessage, "Internal server error")
    }

    func testHandleError_apiError_httpErrorNilMessage() {
        let apiError = APIClient.APIError.httpError(statusCode: 422, message: nil)
        viewModel.triggerError(apiError)
        XCTAssertEqual(viewModel.errorMessage, "HTTP error 422")
    }

    func testHandleError_authError_setsErrorDescription() {
        // Given
        let authError = AuthError.notAuthenticated

        // When
        viewModel.triggerError(authError)

        // Then
        XCTAssertEqual(viewModel.errorMessage, authError.errorDescription)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testHandleError_authError_biometricFailed() {
        let authError = AuthError.biometricFailed
        viewModel.triggerError(authError)
        XCTAssertEqual(viewModel.errorMessage, "Biometric authentication failed")
    }

    func testHandleError_authError_keysNotUnlocked() {
        let authError = AuthError.keysNotUnlocked
        viewModel.triggerError(authError)
        XCTAssertEqual(viewModel.errorMessage, "Keys not unlocked")
    }

    func testHandleError_genericError_setsLocalizedDescription() {
        // Given
        let genericError = MockError.testError("Something went wrong")

        // When
        viewModel.triggerError(genericError)

        // Then
        XCTAssertEqual(viewModel.errorMessage, "Something went wrong")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testHandleError_setsIsLoadingToFalse() {
        // Given
        viewModel.isLoading = true

        // When
        viewModel.triggerError(MockError.testError("Error"))

        // Then
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - clearError Tests

    func testClearError_clearsErrorMessage() {
        // Given
        viewModel.triggerError(MockError.testError("Error"))
        XCTAssertNotNil(viewModel.errorMessage)

        // When
        viewModel.clearError()

        // Then
        XCTAssertNil(viewModel.errorMessage)
    }
}
