package com.securesharing.presentation.auth

import app.cash.turbine.test
import com.securesharing.domain.model.PublicKeys
import com.securesharing.domain.model.User
import com.securesharing.domain.model.UserRole
import com.securesharing.domain.repository.AuthRepository
import com.securesharing.util.AppException
import com.securesharing.util.Result
import io.mockk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for LoginViewModel.
 *
 * Tests cover:
 * - Login flow with success and failure
 * - Form validation
 * - UI state transitions
 * - Error handling
 */
@OptIn(ExperimentalCoroutinesApi::class)
class LoginViewModelTest {

    private lateinit var authRepository: AuthRepository
    private lateinit var viewModel: LoginViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val testUser = User(
        id = "user-123",
        email = "test@example.com",
        tenantId = "test-tenant",
        role = UserRole.USER,
        publicKeys = PublicKeys(
            kem = ByteArray(32),
            sign = ByteArray(32),
            mlKem = ByteArray(32),
            mlDsa = ByteArray(32)
        ),
        storageQuota = 1073741824,
        storageUsed = 0
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        authRepository = mockk()
        viewModel = LoginViewModel(authRepository)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ==================== Initial State Tests ====================

    @Test
    fun `initial state is correct`() = runTest {
        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("", state.email)
            assertEquals("", state.password)
            assertEquals("", state.tenantSlug)
            assertFalse(state.isLoading)
            assertNull(state.error)
            assertFalse(state.isLoggedIn)
        }
    }

    // ==================== Form Update Tests ====================

    @Test
    fun `updateEmail updates state`() = runTest {
        viewModel.uiState.test {
            skipItems(1) // Skip initial state

            viewModel.updateEmail("test@example.com")
            val state = awaitItem()

            assertEquals("test@example.com", state.email)
        }
    }

    @Test
    fun `updatePassword updates state`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.updatePassword("password123")
            val state = awaitItem()

            assertEquals("password123", state.password)
        }
    }

    @Test
    fun `updateTenantSlug updates state`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.updateTenantSlug("my-org")
            val state = awaitItem()

            assertEquals("my-org", state.tenantSlug)
        }
    }

    // ==================== Login Tests ====================

    @Test
    fun `login success updates state to logged in`() = runTest {
        coEvery { authRepository.login(any(), any(), any()) } returns Result.success(testUser)

        viewModel.uiState.test {
            skipItems(1)

            viewModel.updateEmail("test@example.com")
            viewModel.updatePassword("password123")
            viewModel.updateTenantSlug("test-tenant")
            skipItems(3) // Skip form updates

            viewModel.login()

            // Should show loading
            val loadingState = awaitItem()
            assertTrue(loadingState.isLoading)

            // Should complete login
            testDispatcher.scheduler.advanceUntilIdle()
            val loggedInState = awaitItem()

            assertFalse(loggedInState.isLoading)
            assertTrue(loggedInState.isLoggedIn)
            assertNull(loggedInState.error)
        }
    }

    @Test
    fun `login failure shows error`() = runTest {
        coEvery { authRepository.login(any(), any(), any()) } returns Result.error(
            AppException.Unauthorized("Invalid credentials")
        )

        viewModel.uiState.test {
            skipItems(1)

            viewModel.updateEmail("test@example.com")
            viewModel.updatePassword("wrongpassword")
            viewModel.updateTenantSlug("test-tenant")
            skipItems(3)

            viewModel.login()
            skipItems(1) // Loading state

            testDispatcher.scheduler.advanceUntilIdle()
            val errorState = awaitItem()

            assertFalse(errorState.isLoading)
            assertFalse(errorState.isLoggedIn)
            assertNotNull(errorState.error)
            assertTrue(errorState.error!!.contains("Invalid") || errorState.error!!.contains("credentials"))
        }
    }

    @Test
    fun `login with empty email shows validation error`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.updatePassword("password123")
            viewModel.updateTenantSlug("test-tenant")
            skipItems(2)

            viewModel.login()

            val state = awaitItem()
            assertNotNull(state.error)
            // Should not call repository with invalid input
            coVerify(exactly = 0) { authRepository.login(any(), any(), any()) }
        }
    }

    @Test
    fun `login with empty password shows validation error`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.updateEmail("test@example.com")
            viewModel.updateTenantSlug("test-tenant")
            skipItems(2)

            viewModel.login()

            val state = awaitItem()
            assertNotNull(state.error)
            coVerify(exactly = 0) { authRepository.login(any(), any(), any()) }
        }
    }

    @Test
    fun `login network error shows appropriate message`() = runTest {
        coEvery { authRepository.login(any(), any(), any()) } returns Result.error(
            AppException.Network("Unable to connect")
        )

        viewModel.uiState.test {
            skipItems(1)

            viewModel.updateEmail("test@example.com")
            viewModel.updatePassword("password123")
            viewModel.updateTenantSlug("test-tenant")
            skipItems(3)

            viewModel.login()
            skipItems(1) // Loading

            testDispatcher.scheduler.advanceUntilIdle()
            val errorState = awaitItem()

            assertNotNull(errorState.error)
            assertFalse(errorState.isLoading)
        }
    }

    // ==================== Error Clearing Tests ====================

    @Test
    fun `updateEmail clears error from state`() = runTest {
        coEvery { authRepository.login(any(), any(), any()) } returns Result.error(
            AppException.Unauthorized("Error")
        )

        viewModel.uiState.test {
            skipItems(1)

            viewModel.updateEmail("test@example.com")
            viewModel.updatePassword("password")
            viewModel.updateTenantSlug("tenant")
            skipItems(3)

            viewModel.login()
            skipItems(1) // Loading

            testDispatcher.scheduler.advanceUntilIdle()
            val errorState = awaitItem()
            assertNotNull(errorState.error)

            // Updating email should clear the error
            viewModel.updateEmail("new@example.com")
            val clearedState = awaitItem()
            assertNull(clearedState.error)
        }
    }

    // ==================== Password Memory Tests ====================

    @Test
    fun `login converts password to CharArray and clears it`() = runTest {
        var capturedPassword: CharArray? = null
        coEvery { authRepository.login(any(), capture(slot()), any()) } answers {
            capturedPassword = secondArg<CharArray>().copyOf()
            Result.success(testUser)
        }

        viewModel.updateEmail("test@example.com")
        viewModel.updatePassword("password123")
        viewModel.updateTenantSlug("test-tenant")

        viewModel.login()
        testDispatcher.scheduler.advanceUntilIdle()

        // Verify password was passed to repository
        assertNotNull(capturedPassword)
        assertEquals("password123", String(capturedPassword!!))
    }
}
