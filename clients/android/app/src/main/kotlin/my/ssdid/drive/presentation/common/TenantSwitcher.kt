package my.ssdid.drive.presentation.common

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import my.ssdid.drive.domain.model.Tenant
import my.ssdid.drive.domain.model.UserRole

/**
 * Compact tenant indicator that shows the current tenant and can be clicked to switch.
 */
@Composable
fun TenantIndicator(
    currentTenant: Tenant?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Tenant icon
            Icon(
                imageVector = Icons.Default.Business,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.primary
            )

            // Tenant name
            Text(
                text = currentTenant?.name ?: "Select Organization",
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false)
            )

            // Role badge
            currentTenant?.role?.let { role ->
                RoleBadge(role = role)
            }

            // Dropdown arrow
            Icon(
                imageVector = Icons.Default.KeyboardArrowDown,
                contentDescription = "Switch organization",
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * Role badge showing user's role in the tenant.
 */
@Composable
fun RoleBadge(
    role: UserRole,
    modifier: Modifier = Modifier
) {
    val (backgroundColor, textColor) = when (role) {
        UserRole.OWNER -> MaterialTheme.colorScheme.primaryContainer to MaterialTheme.colorScheme.onPrimaryContainer
        UserRole.ADMIN -> MaterialTheme.colorScheme.tertiaryContainer to MaterialTheme.colorScheme.onTertiaryContainer
        UserRole.USER -> MaterialTheme.colorScheme.surfaceVariant to MaterialTheme.colorScheme.onSurfaceVariant
    }

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(4.dp),
        color = backgroundColor
    ) {
        Text(
            text = role.name.lowercase().replaceFirstChar { it.uppercase() },
            style = MaterialTheme.typography.labelSmall,
            color = textColor,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
        )
    }
}

/**
 * Full tenant switcher dialog/sheet showing all available tenants.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TenantSwitcherBottomSheet(
    currentTenant: Tenant?,
    availableTenants: List<Tenant>,
    onTenantSelected: (String) -> Unit,
    onDismiss: () -> Unit,
    isLoading: Boolean = false,
    isSwitching: Boolean = false,
    modifier: Modifier = Modifier
) {
    val sheetState = rememberModalBottomSheetState()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        modifier = modifier
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 32.dp)
        ) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Switch Organization",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold
                )

                if (isLoading || isSwitching) {
                    Spacer(modifier = Modifier.width(8.dp))
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp
                    )
                }
            }

            Divider(modifier = Modifier.padding(vertical = 8.dp))

            // Tenant list
            LazyColumn(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(vertical = 8.dp)
            ) {
                items(
                    items = availableTenants,
                    key = { it.id }
                ) { tenant ->
                    TenantListItem(
                        tenant = tenant,
                        isSelected = tenant.id == currentTenant?.id,
                        onClick = { onTenantSelected(tenant.id) },
                        enabled = !isSwitching
                    )
                }
            }

            if (availableTenants.isEmpty() && !isLoading) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(32.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "No organizations available",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

/**
 * Individual tenant list item.
 */
@Composable
fun TenantListItem(
    tenant: Tenant,
    isSelected: Boolean,
    onClick: () -> Unit,
    enabled: Boolean = true,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clickable(enabled = enabled && !isSelected, onClick = onClick),
        color = if (isSelected) {
            MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
        } else {
            MaterialTheme.colorScheme.surface
        }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Tenant avatar/icon
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(
                        if (isSelected) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.surfaceVariant
                        }
                    ),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = tenant.name.take(2).uppercase(),
                    style = MaterialTheme.typography.titleMedium,
                    color = if (isSelected) {
                        MaterialTheme.colorScheme.onPrimary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    fontWeight = FontWeight.Bold
                )
            }

            Spacer(modifier = Modifier.width(16.dp))

            // Tenant info
            Column(
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    text = tenant.name,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal
                )
                Text(
                    text = tenant.slug,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Role badge
            RoleBadge(role = tenant.role)

            // Check mark for selected
            if (isSelected) {
                Spacer(modifier = Modifier.width(8.dp))
                Icon(
                    imageVector = Icons.Default.Check,
                    contentDescription = "Selected",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

/**
 * Tenant switcher card for settings screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TenantSwitcherCard(
    currentTenant: Tenant?,
    tenantsCount: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Icon
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Business,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }

            Spacer(modifier = Modifier.width(16.dp))

            // Tenant info
            Column(
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    text = currentTenant?.name ?: "No Organization",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = if (tenantsCount > 1) {
                        "$tenantsCount organizations available"
                    } else {
                        currentTenant?.slug ?: ""
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Role badge
            currentTenant?.role?.let { role ->
                RoleBadge(role = role)
            }

            if (tenantsCount > 1) {
                Spacer(modifier = Modifier.width(8.dp))
                Icon(
                    imageVector = Icons.Default.ChevronRight,
                    contentDescription = "Switch organization",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
