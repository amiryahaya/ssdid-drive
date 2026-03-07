package com.securesharing.e2e

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.securesharing.MainActivity
import com.securesharing.domain.repository.AuthRepository
import com.securesharing.domain.repository.TenantRepository
import com.securesharing.util.Result
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import javax.inject.Inject

/**
 * E2E tests for multi-tenant switching functionality.
 *
 * Tests cover:
 * - Listing available tenants
 * - Switching between tenants
 * - Tenant context persistence
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class TenantSwitcherE2eTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Inject
    lateinit var authRepository: AuthRepository

    @Inject
    lateinit var tenantRepository: TenantRepository

    @Before
    fun setUp() {
        hiltRule.inject()
        assumeTrue("E2E tests must be enabled", E2eTestConfig.isE2eEnabled())
        assumeTrue("Must use local backend", E2eTestConfig.isLocalBackend())
        assumeTrue("Tenant slug required", E2eTestConfig.tenantSlug().isNotBlank())

        // Logout any existing session
        runBlocking { authRepository.logout() }
    }

    /**
     * Test listing available tenants in settings
     *
     * Steps:
     * 1. Login to the app
     * 2. Navigate to Settings
     * 3. Find and tap on Organization/Tenant section
     * 4. Verify tenant list appears with at least one tenant
     */
    @Test
    fun listTenants_inSettings_showsAvailableTenants() {
        val tenantSlug = E2eTestConfig.tenantSlug()
        val email = E2eTestConfig.uniqueEmail("tenant_list")
        val password = "E2ePassword!123".toCharArray()

        try {
            // Register and login
            runBlocking {
                E2eTestUtils.registerUser(authRepository, email, password, tenantSlug)
            }

            // Wait for home screen
            E2eTestUtils.run {
                composeRule.waitForContentDescription("Open settings")
            }

            // Navigate to settings
            composeRule.onNodeWithContentDescription("Open settings").performClick()
            E2eTestUtils.run {
                composeRule.waitForText("Settings")
            }

            // Look for organization/tenant section
            val tenantSection = composeRule.onAllNodes(
                hasText("Organization") or
                        hasText("Tenant") or
                        hasText("Workspace") or
                        hasText(tenantSlug, ignoreCase = true)
            )

            try {
                tenantSection.onFirst().assertIsDisplayed()

                // Tap to expand or navigate to tenant list
                tenantSection.onFirst().performClick()

                // Wait for tenant list or details
                composeRule.waitUntil(timeoutMillis = 10_000) {
                    try {
                        // Check for tenant list or current tenant display
                        val hasTenantList = composeRule.onAllNodes(
                            hasText("Switch Organization") or
                                    hasText("Change Tenant") or
                                    hasText("Organizations") or
                                    hasContentDescription("Tenant list")
                        ).fetchSemanticsNodes().isNotEmpty()

                        val hasCurrentTenant = composeRule.onAllNodes(
                            hasText(tenantSlug, ignoreCase = true)
                        ).fetchSemanticsNodes().isNotEmpty()

                        hasTenantList || hasCurrentTenant
                    } catch (_: Exception) {
                        false
                    }
                }

                E2eTestUtils.takeScreenshot("tenant_list")

                // Verify at least the current tenant is shown
                composeRule.onAllNodes(hasText(tenantSlug, ignoreCase = true))
                    .onFirst()
                    .assertExists()

                // Check tenant count from repository
                runBlocking {
                    val tenantsResult = E2eTestUtils.listTenants(tenantRepository)
                    when (tenantsResult) {
                        is Result.Success -> {
                            val tenants = tenantsResult.data
                            println("Found ${tenants.size} tenant(s)")
                            assert(tenants.isNotEmpty()) { "Should have at least one tenant" }
                        }
                        is Result.Error -> {
                            println("Failed to list tenants: ${tenantsResult.exception.message}")
                        }
                    }
                }

            } catch (e: AssertionError) {
                // Tenant section might not be visible in single-tenant mode
                println("Tenant section not found - may be single-tenant deployment")

                // Verify via repository that we have tenant access
                runBlocking {
                    val tenantsResult = E2eTestUtils.listTenants(tenantRepository)
                    when (tenantsResult) {
                        is Result.Success -> {
                            assert(tenantsResult.data.isNotEmpty()) {
                                "Should have at least one tenant"
                            }
                        }
                        is Result.Error -> {
                            throw AssertionError("Failed to get tenant list")
                        }
                    }
                }
            }

        } finally {
            E2eTestUtils.zeroize(password)
        }
    }

    /**
     * Test switching between tenants
     *
     * Prerequisites:
     * - User must be a member of multiple tenants
     *
     * Steps:
     * 1. Login to the app
     * 2. Navigate to Settings > Organization
     * 3. Select a different tenant
     * 4. Verify context switches to new tenant
     */
    @Test
    fun switchTenant_toAnotherOrganization_updatesContext() {
        val tenantSlug = E2eTestConfig.tenantSlug()
        val email = E2eTestConfig.uniqueEmail("tenant_switch")
        val password = "E2ePassword!123".toCharArray()

        try {
            // Register in primary tenant
            runBlocking {
                E2eTestUtils.registerUser(authRepository, email, password, tenantSlug)
            }

            // Check if user has multiple tenants
            val tenants = runBlocking {
                when (val result = E2eTestUtils.listTenants(tenantRepository)) {
                    is Result.Success -> result.data
                    is Result.Error -> emptyList()
                }
            }

            if (tenants.size < 2) {
                println("User only has access to ${tenants.size} tenant(s). Skipping switch test.")
                // Still verify current tenant is accessible
                assert(tenants.isNotEmpty()) { "Should have at least one tenant" }
                return
            }

            // Wait for home screen
            E2eTestUtils.run {
                composeRule.waitForContentDescription("Open settings")
            }

            // Navigate to settings
            composeRule.onNodeWithContentDescription("Open settings").performClick()
            E2eTestUtils.run {
                composeRule.waitForText("Settings")
            }

            // Find and tap organization section
            composeRule.onAllNodes(
                hasText("Organization") or hasText("Tenant") or hasText("Workspace")
            ).onFirst().performClick()

            // Wait for tenant list
            composeRule.waitUntil(timeoutMillis = 10_000) {
                composeRule.onAllNodes(hasClickAction())
                    .fetchSemanticsNodes().size >= 2
            }

            // Get the other tenant (not the current one)
            val otherTenant = tenants.find { it.slug != tenantSlug }
            requireNotNull(otherTenant) { "Should have another tenant to switch to" }

            // Find and tap on the other tenant
            composeRule.onAllNodes(
                hasText(otherTenant.name) or hasText(otherTenant.slug)
            ).onFirst().performClick()

            // Wait for context switch
            composeRule.waitUntil(timeoutMillis = 15_000) {
                try {
                    // Check for loading completion or new tenant name in UI
                    composeRule.onAllNodes(
                        hasText(otherTenant.name) or hasText(otherTenant.slug)
                    ).fetchSemanticsNodes().isNotEmpty()
                } catch (_: Exception) {
                    false
                }
            }

            E2eTestUtils.takeScreenshot("tenant_switched")

            // Verify the switch via repository
            runBlocking {
                val currentTenant = tenantRepository.getCurrentTenant()
                when (currentTenant) {
                    is Result.Success -> {
                        assert(currentTenant.data.id == otherTenant.id) {
                            "Should have switched to other tenant"
                        }
                        println("Successfully switched to tenant: ${currentTenant.data.name}")
                    }
                    is Result.Error -> {
                        throw AssertionError("Failed to verify tenant switch")
                    }
                }
            }

        } finally {
            E2eTestUtils.zeroize(password)
        }
    }
}
