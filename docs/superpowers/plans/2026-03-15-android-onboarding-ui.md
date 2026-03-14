# Android Onboarding UI Improvements — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Android onboarding loop by adding multi-auth invitation acceptance, login screen entry points, and tenant request submission.

**Architecture:** Extend existing Compose screens (InviteAcceptScreen, LoginScreen) and add one new screen (TenantRequestScreen). Reuse existing repository methods where possible. The CreateInvitationScreen and `oidcVerify(invitationToken)` already exist — no duplication needed.

**Tech Stack:** Kotlin, Jetpack Compose, Hilt DI, Material 3, MockK + Turbine for tests, Retrofit for API.

---

## What Already Exists (Do NOT Rebuild)

- `CreateInvitationScreen.kt` + `CreateInvitationViewModel.kt` — full invitation creation UI with copy/share
- `AuthRepository.oidcVerify(provider, idToken, invitationToken?)` — OIDC verify with optional invitation token
- `TenantRepository.createInvitation(email, role, message)` — invitation creation API call
- `JoinTenantScreen.kt` — invite code entry with preview
- `Screen.CreateInvitation` route — already in NavGraph

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `presentation/auth/InviteAcceptScreen.kt` | Add Email+TOTP and OIDC buttons |
| Modify | `presentation/auth/InviteAcceptViewModel.kt` | Add OIDC and email auth methods |
| Modify | `presentation/auth/LoginScreen.kt` | Add invite code + org request links |
| Create | `presentation/tenant/TenantRequestScreen.kt` | Organization request form |
| Create | `presentation/tenant/TenantRequestViewModel.kt` | Org request state + API call |
| Modify | `presentation/navigation/Screen.kt` | Add TenantRequest route |
| Modify | `presentation/navigation/NavGraph.kt` | Wire TenantRequest screen |
| Modify | `presentation/settings/SettingsScreen.kt` | Add "Request Organization" link |
| Modify | `data/remote/ApiService.kt` | Add tenant request endpoint |
| Modify | `domain/repository/TenantRepository.kt` | Add submitTenantRequest method |
| Modify | `data/repository/TenantRepositoryImpl.kt` | Implement submitTenantRequest |
| Create | `test/.../TenantRequestViewModelTest.kt` | ViewModel tests |
| Modify | `test/.../InviteAcceptViewModelTest.kt` | Tests for new auth methods |

All paths relative to `clients/android/app/src/main/kotlin/my/ssdid/drive/`

---

## Chunk 1: TenantRequest Feature (New Screen)

### Task 1: Add API endpoint and repository method

**Files:**
- Modify: `data/remote/ApiService.kt`
- Modify: `domain/repository/TenantRepository.kt`
- Modify: `data/repository/TenantRepositoryImpl.kt`

- [ ] **Step 1: Add DTO for tenant request**

Create request/response DTOs. Find the existing DTO directory pattern:
`clients/android/app/src/main/kotlin/my/ssdid/drive/data/remote/dto/`

Add to a new or existing DTO file:

```kotlin
// In data/remote/dto/ (add to existing DTO pattern)
data class SubmitTenantRequestBody(
    @SerializedName("organization_name") val organizationName: String,
    @SerializedName("reason") val reason: String? = null
)

data class TenantRequestResponse(
    @SerializedName("id") val id: String,
    @SerializedName("organization_name") val organizationName: String,
    @SerializedName("reason") val reason: String?,
    @SerializedName("status") val status: String,
    @SerializedName("created_at") val createdAt: String
)
```

- [ ] **Step 2: Add API endpoint**

In `data/remote/ApiService.kt`, add in the Tenant Management section:

```kotlin
@POST("tenant-requests")
suspend fun submitTenantRequest(@Body request: SubmitTenantRequestBody): Response<TenantRequestResponse>
```

- [ ] **Step 3: Add repository interface method**

In `domain/repository/TenantRepository.kt`, add:

```kotlin
/**
 * Submit a request to create a new organization.
 * SuperAdmin will review and approve/reject.
 */
suspend fun submitTenantRequest(organizationName: String, reason: String? = null): Result<TenantRequestResult>
```

Add domain model:

```kotlin
// In domain/model/ or inline in TenantRepository.kt
data class TenantRequestResult(
    val id: String,
    val organizationName: String,
    val status: String
)
```

- [ ] **Step 4: Implement repository method**

In `data/repository/TenantRepositoryImpl.kt`, add:

```kotlin
override suspend fun submitTenantRequest(
    organizationName: String,
    reason: String?
): Result<TenantRequestResult> {
    return try {
        val response = apiService.submitTenantRequest(
            SubmitTenantRequestBody(organizationName, reason)
        )
        if (response.isSuccessful) {
            val body = response.body() ?: return Result.error(AppException.Unknown("Empty response"))
            Result.success(TenantRequestResult(body.id, body.organizationName, body.status))
        } else {
            when (response.code()) {
                409 -> Result.error(AppException.Conflict("You already have a pending request"))
                else -> Result.error(AppException.Unknown("Failed: ${response.code()}"))
            }
        }
    } catch (e: Exception) {
        Result.error(AppException.Network("Failed to submit request", e))
    }
}
```

- [ ] **Step 5: Build to verify compilation**

Run: `cd clients/android && ./gradlew assembleDevDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 6: Commit**

```bash
git add clients/android/
git commit -m "feat(android): add tenant request API endpoint and repository method"
```

---

### Task 2: Create TenantRequestViewModel with tests

**Files:**
- Create: `presentation/tenant/TenantRequestViewModel.kt`
- Create: `test/.../presentation/tenant/TenantRequestViewModelTest.kt`

- [ ] **Step 1: Write failing tests**

Create `clients/android/app/src/test/kotlin/my/ssdid/drive/presentation/tenant/TenantRequestViewModelTest.kt`:

```kotlin
package my.ssdid.drive.presentation.tenant

import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import my.ssdid.drive.domain.model.TenantRequestResult
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class TenantRequestViewModelTest {
    private lateinit var tenantRepository: TenantRepository
    private lateinit var viewModel: TenantRequestViewModel
    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        tenantRepository = mockk()
        viewModel = TenantRequestViewModel(tenantRepository)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `initial state has empty fields`() {
        val state = viewModel.uiState.value
        assertEquals("", state.organizationName)
        assertEquals("", state.reason)
        assertFalse(state.isLoading)
        assertFalse(state.isSubmitted)
        assertNull(state.error)
    }

    @Test
    fun `submitRequest with blank name shows error`() = runTest {
        viewModel.updateOrganizationName("   ")
        viewModel.submitRequest()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertEquals("Organization name is required", state.error)
        assertFalse(state.isLoading)
    }

    @Test
    fun `submitRequest calls repository and sets submitted on success`() = runTest {
        coEvery { tenantRepository.submitTenantRequest("Acme Corp", "We need it") } returns
            Result.success(TenantRequestResult("123", "Acme Corp", "pending"))

        viewModel.updateOrganizationName("Acme Corp")
        viewModel.updateReason("We need it")
        viewModel.submitRequest()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(state.isSubmitted)
        assertFalse(state.isLoading)
        assertNull(state.error)
        coVerify { tenantRepository.submitTenantRequest("Acme Corp", "We need it") }
    }

    @Test
    fun `submitRequest shows error on conflict`() = runTest {
        coEvery { tenantRepository.submitTenantRequest("Acme Corp", null) } returns
            Result.error(AppException.Conflict("You already have a pending request"))

        viewModel.updateOrganizationName("Acme Corp")
        viewModel.submitRequest()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isSubmitted)
        assertEquals("You already have a pending request", state.error)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail (class doesn't exist yet)**

Run: `cd clients/android && ./gradlew testDevDebugUnitTest --tests "my.ssdid.drive.presentation.tenant.TenantRequestViewModelTest"`
Expected: FAIL — class not found

- [ ] **Step 3: Implement TenantRequestViewModel**

Create `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/tenant/TenantRequestViewModel.kt`:

```kotlin
package my.ssdid.drive.presentation.tenant

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.util.Result
import javax.inject.Inject

data class TenantRequestUiState(
    val organizationName: String = "",
    val reason: String = "",
    val isLoading: Boolean = false,
    val isSubmitted: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class TenantRequestViewModel @Inject constructor(
    private val tenantRepository: TenantRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(TenantRequestUiState())
    val uiState = _uiState.asStateFlow()

    fun updateOrganizationName(name: String) {
        _uiState.update { it.copy(organizationName = name, error = null) }
    }

    fun updateReason(reason: String) {
        _uiState.update { it.copy(reason = reason) }
    }

    fun submitRequest() {
        val name = _uiState.value.organizationName.trim()
        if (name.isBlank()) {
            _uiState.update { it.copy(error = "Organization name is required") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            val reason = _uiState.value.reason.trim().ifBlank { null }
            when (val result = tenantRepository.submitTenantRequest(name, reason)) {
                is Result.Success -> {
                    _uiState.update { it.copy(isLoading = false, isSubmitted = true) }
                }
                is Result.Error -> {
                    _uiState.update { it.copy(isLoading = false, error = result.exception.message) }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd clients/android && ./gradlew testDevDebugUnitTest --tests "my.ssdid.drive.presentation.tenant.TenantRequestViewModelTest"`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add clients/android/
git commit -m "feat(android): add TenantRequestViewModel with tests"
```

---

### Task 3: Create TenantRequestScreen composable

**Files:**
- Create: `presentation/tenant/TenantRequestScreen.kt`

- [ ] **Step 1: Create the screen composable**

Create `clients/android/app/src/main/kotlin/my/ssdid/drive/presentation/tenant/TenantRequestScreen.kt`:

```kotlin
package my.ssdid.drive.presentation.tenant

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TenantRequestScreen(
    onNavigateBack: () -> Unit,
    viewModel: TenantRequestViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Request Organization") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            if (uiState.isSubmitted) {
                RequestSubmittedContent(
                    organizationName = uiState.organizationName,
                    onNavigateBack = onNavigateBack
                )
            } else {
                RequestForm(
                    organizationName = uiState.organizationName,
                    reason = uiState.reason,
                    isLoading = uiState.isLoading,
                    error = uiState.error,
                    onOrganizationNameChange = viewModel::updateOrganizationName,
                    onReasonChange = viewModel::updateReason,
                    onSubmit = viewModel::submitRequest
                )
            }
        }
    }
}

@Composable
private fun RequestForm(
    organizationName: String,
    reason: String,
    isLoading: Boolean,
    error: String?,
    onOrganizationNameChange: (String) -> Unit,
    onReasonChange: (String) -> Unit,
    onSubmit: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Icon
        Icon(
            imageVector = Icons.Default.Business,
            contentDescription = null,
            modifier = Modifier
                .size(64.dp)
                .align(Alignment.CenterHorizontally),
            tint = MaterialTheme.colorScheme.primary
        )

        Text(
            text = "Create Your Organization",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center
        )

        Text(
            text = "Request a new organization for your team. An administrator will review your request.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(8.dp))

        // Organization name
        Text(
            text = "Organization Name",
            style = MaterialTheme.typography.labelLarge
        )
        OutlinedTextField(
            value = organizationName,
            onValueChange = onOrganizationNameChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Acme Corp") },
            singleLine = true,
            isError = error != null && organizationName.isBlank(),
            enabled = !isLoading
        )

        // Reason
        Text(
            text = "Reason (optional)",
            style = MaterialTheme.typography.labelLarge
        )
        OutlinedTextField(
            value = reason,
            onValueChange = onReasonChange,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 100.dp),
            placeholder = { Text("Tell us about your team...") },
            maxLines = 5,
            supportingText = {
                Text(
                    text = "${reason.length}/500",
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.End
                )
            },
            enabled = !isLoading
        )

        // Error
        if (error != null) {
            Text(
                text = error,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Submit button
        Button(
            onClick = onSubmit,
            modifier = Modifier.fillMaxWidth(),
            enabled = !isLoading && organizationName.isNotBlank()
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    color = MaterialTheme.colorScheme.onPrimary,
                    strokeWidth = 2.dp
                )
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text("Submit Request")
        }
    }
}

@Composable
private fun RequestSubmittedContent(
    organizationName: String,
    onNavigateBack: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = "Request submitted",
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Request Submitted!",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Your request for \"$organizationName\" has been submitted. An administrator will review and approve it.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "You'll be notified when your organization is ready.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(32.dp))

        Button(onClick = onNavigateBack) {
            Text("Done")
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd clients/android && ./gradlew assembleDevDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add clients/android/
git commit -m "feat(android): add TenantRequestScreen composable"
```

---

### Task 4: Wire TenantRequest into navigation

**Files:**
- Modify: `presentation/navigation/Screen.kt`
- Modify: `presentation/navigation/NavGraph.kt`
- Modify: `presentation/settings/SettingsScreen.kt`

- [ ] **Step 1: Add route to Screen.kt**

In `presentation/navigation/Screen.kt`, add in the Tenant screens section (after `JoinTenant`):

```kotlin
data object TenantRequest : Screen("tenant-request")
```

- [ ] **Step 2: Add composable to NavGraph.kt**

In `presentation/navigation/NavGraph.kt`, add after the JoinTenant composable:

```kotlin
composable(Screen.TenantRequest.route) {
    TenantRequestScreen(
        onNavigateBack = { navController.popBackStack() }
    )
}
```

Add import: `import my.ssdid.drive.presentation.tenant.TenantRequestScreen`

- [ ] **Step 3: Add navigation callback to SettingsScreen**

In `SettingsScreen.kt`, add `onNavigateToTenantRequest: () -> Unit = {}` parameter to the composable function.

Add a `SettingsNavigationCard` in the Organization section (near the existing "Join Organization" card):

```kotlin
SettingsNavigationCard(
    icon = Icons.Default.Business,
    title = "Request Organization",
    subtitle = "Request a new organization for your team",
    onClick = onNavigateToTenantRequest
)
```

- [ ] **Step 4: Wire callback in NavGraph**

In the NavGraph's Settings composable, pass the callback:

```kotlin
onNavigateToTenantRequest = { navController.navigate(Screen.TenantRequest.route) }
```

- [ ] **Step 5: Build and verify**

Run: `cd clients/android && ./gradlew assembleDevDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 6: Commit**

```bash
git add clients/android/
git commit -m "feat(android): wire TenantRequestScreen into navigation and settings"
```

---

## Chunk 2: LoginScreen Entry Points + InviteAccept Multi-Auth

### Task 5: Add invite code and org request links to LoginScreen

**Files:**
- Modify: `presentation/auth/LoginScreen.kt`

- [ ] **Step 1: Add navigation callbacks to LoginScreen**

Add two new parameters to the `LoginScreen` composable:

```kotlin
@Composable
fun LoginScreen(
    // ... existing params ...
    onNavigateToJoinTenant: () -> Unit = {},
    onNavigateToTenantRequest: () -> Unit = {},
    // ... existing params ...
)
```

- [ ] **Step 2: Add invite code card at top of screen**

Before the existing email field section, add:

```kotlin
// Invite code entry point
OutlinedCard(
    onClick = onNavigateToJoinTenant,
    modifier = Modifier.fillMaxWidth()
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "Have an invite code?",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = "Enter your code to join an organization",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Icon(
            Icons.Default.GroupAdd,
            contentDescription = "Enter invite code",
            tint = MaterialTheme.colorScheme.primary
        )
    }
}

Spacer(modifier = Modifier.height(16.dp))

// Divider
Row(
    modifier = Modifier.fillMaxWidth(),
    verticalAlignment = Alignment.CenterVertically
) {
    HorizontalDivider(modifier = Modifier.weight(1f))
    Text(
        text = "  or sign in  ",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    HorizontalDivider(modifier = Modifier.weight(1f))
}

Spacer(modifier = Modifier.height(16.dp))
```

- [ ] **Step 3: Add org request link at bottom of screen**

After the existing auth buttons and recovery link, add:

```kotlin
Spacer(modifier = Modifier.height(16.dp))

TextButton(onClick = onNavigateToTenantRequest) {
    Text("Need an organization? Request one")
}
```

- [ ] **Step 4: Wire callbacks in NavGraph**

In NavGraph's Login composable, add:

```kotlin
onNavigateToJoinTenant = { navController.navigate(Screen.JoinTenant.route) },
onNavigateToTenantRequest = { navController.navigate(Screen.TenantRequest.route) }
```

- [ ] **Step 5: Build and verify**

Run: `cd clients/android && ./gradlew assembleDevDebug`

- [ ] **Step 6: Commit**

```bash
git add clients/android/
git commit -m "feat(android): add invite code and org request links to LoginScreen"
```

---

### Task 6: Extend InviteAcceptScreen with multi-auth

**Files:**
- Modify: `presentation/auth/InviteAcceptScreen.kt`
- Modify: `presentation/auth/InviteAcceptViewModel.kt`

This is the most complex change. The screen currently only supports wallet auth. We need to add:
- "Continue with Email" → navigate to email registration with invitation token
- "Sign in with Google/Microsoft" → launch OIDC with invitation token
- "Sign In to Accept" → for existing logged-in users

- [ ] **Step 1: Add new state fields to InviteAcceptViewModel**

Read the existing `InviteAcceptViewModel.kt` first. Add to the UiState:

```kotlin
data class InviteAcceptUiState(
    // ... existing fields ...
    val isAcceptingAsExisting: Boolean = false,  // For logged-in user accept
    val acceptError: String? = null
)
```

Add new methods to the ViewModel:

```kotlin
/**
 * Accept invitation as an already-authenticated user.
 * Calls POST /api/invitations/{id}/accept directly.
 */
fun acceptAsExistingUser() {
    val invitation = _uiState.value.invitation ?: return
    viewModelScope.launch {
        _uiState.update { it.copy(isAcceptingAsExisting = true, acceptError = null) }
        when (val result = tenantRepository.acceptInvitationByToken(invitation.token)) {
            is Result.Success -> {
                _uiState.update { it.copy(isAcceptingAsExisting = false, isRegistered = true) }
            }
            is Result.Error -> {
                _uiState.update { it.copy(
                    isAcceptingAsExisting = false,
                    acceptError = result.exception.message
                ) }
            }
        }
    }
}

/**
 * Handle OIDC result for invitation-based registration.
 * Calls oidcVerify with invitationToken.
 */
fun handleOidcResult(provider: String, idToken: String) {
    viewModelScope.launch {
        _uiState.update { it.copy(isLoading = true, registrationError = null) }
        when (authRepository.oidcVerify(provider, idToken, _uiState.value.token)) {
            is Result.Success -> {
                _uiState.update { it.copy(isLoading = false, isRegistered = true) }
            }
            is Result.Error -> {
                _uiState.update { it.copy(
                    isLoading = false,
                    registrationError = "Sign-in failed. Please try again."
                ) }
            }
        }
    }
}
```

Note: You'll need to inject `AuthRepository` into the ViewModel (it may already have it for wallet auth — check first).

- [ ] **Step 2: Add multi-auth buttons to InviteAcceptScreen**

Read the existing `InviteAcceptScreen.kt`. After the invitation info card and before/instead of the single "Accept with SSDID Wallet" button, add:

```kotlin
// Section: Auth methods for accepting
if (uiState.invitation != null && !uiState.isWaitingForWallet) {
    Spacer(modifier = Modifier.height(24.dp))

    // Existing user: simple accept
    OutlinedButton(
        onClick = { viewModel.acceptAsExistingUser() },
        modifier = Modifier.fillMaxWidth(),
        enabled = !uiState.isLoading && !uiState.isAcceptingAsExisting
    ) {
        if (uiState.isAcceptingAsExisting) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            Spacer(modifier = Modifier.width(8.dp))
        }
        Text("Sign In to Accept")
    }

    // Divider
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        HorizontalDivider(modifier = Modifier.weight(1f))
        Text("  or create account  ", style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        HorizontalDivider(modifier = Modifier.weight(1f))
    }

    // Email registration with invitation
    OutlinedButton(
        onClick = { onNavigateToEmailRegister(uiState.token) },
        modifier = Modifier.fillMaxWidth(),
        enabled = !uiState.isLoading
    ) {
        Text("Continue with Email")
    }

    Spacer(modifier = Modifier.height(8.dp))

    // OIDC buttons
    OutlinedButton(
        onClick = { onOidcLogin("google") },
        modifier = Modifier.fillMaxWidth(),
        enabled = !uiState.isLoading
    ) {
        Text("Sign in with Google")
    }

    Spacer(modifier = Modifier.height(8.dp))

    OutlinedButton(
        onClick = { onOidcLogin("microsoft") },
        modifier = Modifier.fillMaxWidth(),
        enabled = !uiState.isLoading
    ) {
        Text("Sign in with Microsoft")
    }

    Spacer(modifier = Modifier.height(8.dp))

    // Existing wallet button (keep)
    Button(
        onClick = { viewModel.acceptWithWallet() },
        modifier = Modifier.fillMaxWidth(),
        enabled = !uiState.isLoading
    ) {
        Text("Accept with SSDID Wallet")
    }

    // Error display
    if (uiState.acceptError != null || uiState.registrationError != null) {
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = uiState.acceptError ?: uiState.registrationError ?: "",
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall
        )
    }
}
```

Add new navigation callbacks to the composable parameters:

```kotlin
@Composable
fun InviteAcceptScreen(
    // ... existing params ...
    onNavigateToEmailRegister: (invitationToken: String) -> Unit = {},
    onOidcLogin: (provider: String) -> Unit = {},
)
```

- [ ] **Step 3: Wire OIDC in NavGraph**

In NavGraph's InviteAccept composable, pass the OIDC callback that launches the native OIDC SDK with the invitation token. Look at how the Login screen handles OIDC — reuse the same pattern but pass `invitationToken`:

```kotlin
onOidcLogin = { provider ->
    // Reuse existing OIDC launcher pattern from LoginScreen
    // Pass invitation token via the OIDC authorize URL
}
```

The exact implementation depends on how the OIDC SDK is integrated (check `MainActivity.kt` for the OIDC launcher setup). The `oidcVerify` already accepts `invitationToken`.

- [ ] **Step 4: Wire email registration in NavGraph**

For "Continue with Email", navigate to the existing email registration flow but pass the invitation token. Check if `EmailRegister` screen exists in the nav routes. If not, navigate to Login with a flag:

```kotlin
onNavigateToEmailRegister = { token ->
    // Navigate to email registration with invitation token
    // The exact route depends on existing email register flow
}
```

- [ ] **Step 5: Build and verify**

Run: `cd clients/android && ./gradlew assembleDevDebug`

- [ ] **Step 6: Commit**

```bash
git add clients/android/
git commit -m "feat(android): add multi-auth support to InviteAcceptScreen"
```

---

### Task 7: Add tests for InviteAccept multi-auth

**Files:**
- Modify: `test/.../InviteAcceptViewModelTest.kt`

- [ ] **Step 1: Add tests for new methods**

Add to the existing test file:

```kotlin
@Test
fun `acceptAsExistingUser calls repository and sets registered on success`() = runTest {
    // Setup: load invitation first
    coEvery { tenantRepository.lookupInviteToken(any()) } returns
        Result.success(testInvitation)
    advanceUntilIdle()

    coEvery { tenantRepository.acceptInvitationByToken(any()) } returns
        Result.success(Unit)

    viewModel.acceptAsExistingUser()
    advanceUntilIdle()

    val state = viewModel.uiState.value
    assertTrue(state.isRegistered)
    assertFalse(state.isAcceptingAsExisting)
}

@Test
fun `acceptAsExistingUser shows error on failure`() = runTest {
    coEvery { tenantRepository.lookupInviteToken(any()) } returns
        Result.success(testInvitation)
    advanceUntilIdle()

    coEvery { tenantRepository.acceptInvitationByToken(any()) } returns
        Result.error(AppException.Forbidden("Email does not match"))

    viewModel.acceptAsExistingUser()
    advanceUntilIdle()

    val state = viewModel.uiState.value
    assertFalse(state.isRegistered)
    assertEquals("Email does not match", state.acceptError)
}

@Test
fun `handleOidcResult sets registered on success`() = runTest {
    coEvery { tenantRepository.lookupInviteToken(any()) } returns
        Result.success(testInvitation)
    advanceUntilIdle()

    coEvery { authRepository.oidcVerify("google", "id-token", any()) } returns
        Result.success(testUser)

    viewModel.handleOidcResult("google", "id-token")
    advanceUntilIdle()

    assertTrue(viewModel.uiState.value.isRegistered)
}
```

- [ ] **Step 2: Run tests**

Run: `cd clients/android && ./gradlew testDevDebugUnitTest --tests "my.ssdid.drive.invitation.presentation.InviteAcceptViewModelTest"`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add clients/android/
git commit -m "test(android): add tests for InviteAccept multi-auth methods"
```

---

### Task 8: Run full test suite and verify

- [ ] **Step 1: Run all Android unit tests**

Run: `cd clients/android && ./gradlew testDevDebugUnitTest`
Expected: All PASS (or same failure count as before our changes)

- [ ] **Step 2: Build release variant**

Run: `cd clients/android && ./gradlew assembleDevRelease`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit any fixes**

If any tests needed fixing, commit them.

- [ ] **Step 4: Final commit**

```bash
git add clients/android/
git commit -m "feat(android): complete onboarding UI improvements — multi-auth invite accept, tenant request, login entry points"
```

---

## Implementation Order & Dependencies

```
Task 1: API + Repository (tenant request)  ──┐
Task 2: TenantRequestViewModel + tests     ──┼── Chunk 1 (sequential)
Task 3: TenantRequestScreen composable     ──┤
Task 4: Navigation wiring                  ──┘
                                              │
Task 5: LoginScreen entry points           ──┤
Task 6: InviteAcceptScreen multi-auth      ──┼── Chunk 2 (5-6 parallel, 7-8 sequential)
Task 7: InviteAccept tests                 ──┤
Task 8: Full test suite verification       ──┘
```

Parallel opportunities:
- Tasks 5 and 6 modify independent files
- Tasks 1-4 can run before or after Tasks 5-6
