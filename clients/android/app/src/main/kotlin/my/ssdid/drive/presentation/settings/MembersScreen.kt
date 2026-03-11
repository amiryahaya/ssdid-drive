package my.ssdid.drive.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import my.ssdid.drive.domain.model.TenantMember
import my.ssdid.drive.domain.model.UserRole

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MembersScreen(
    onNavigateBack: () -> Unit,
    viewModel: MembersViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.successMessage) {
        uiState.successMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearSuccessMessage()
        }
    }

    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Members") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { paddingValues ->
        PullToRefreshBox(
            isRefreshing = uiState.isLoading,
            onRefresh = { viewModel.loadMembers() },
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            when {
                uiState.isLoading && uiState.members.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }
                uiState.members.isEmpty() -> {
                    EmptyMembersContent(
                        modifier = Modifier
                            .fillMaxSize()
                            .wrapContentSize(Alignment.Center)
                    )
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(uiState.members) { member ->
                            MemberCard(
                                member = member,
                                currentUserId = uiState.currentUserId,
                                currentUserRole = uiState.currentUserRole,
                                isUpdating = uiState.isUpdating,
                                onChangeRole = { viewModel.showChangeRoleDialog(member) },
                                onRemove = { viewModel.showRemoveMemberDialog(member) }
                            )
                        }
                    }
                }
            }
        }

        // Loading overlay for updates
        if (uiState.isUpdating) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        }
    }

    // Change role dialog
    uiState.memberToChangeRole?.let { member ->
        ChangeRoleDialog(
            member = member,
            currentUserRole = uiState.currentUserRole,
            onDismiss = { viewModel.dismissChangeRoleDialog() },
            onConfirm = { newRole -> viewModel.changeRole(member, newRole) }
        )
    }

    // Remove member dialog
    uiState.memberToRemove?.let { member ->
        RemoveMemberDialog(
            member = member,
            onDismiss = { viewModel.dismissRemoveMemberDialog() },
            onConfirm = { viewModel.removeMember(member) }
        )
    }
}

@Composable
private fun EmptyMembersContent(
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Default.People,
            contentDescription = "No members",
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "No Members",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Organization members will appear here.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
    }
}

@Composable
private fun MemberCard(
    member: TenantMember,
    currentUserId: String?,
    currentUserRole: UserRole,
    isUpdating: Boolean,
    onChangeRole: () -> Unit,
    onRemove: () -> Unit
) {
    val isCurrentUser = member.userId == currentUserId
    val canManage = currentUserRole == UserRole.OWNER && !isCurrentUser && member.role != UserRole.OWNER
    var showMenu by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (isCurrentUser)
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
            else
                MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Avatar/initials
            Surface(
                shape = MaterialTheme.shapes.extraLarge,
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f),
                modifier = Modifier.size(48.dp)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        text = getInitials(member.displayName, member.email),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            Spacer(modifier = Modifier.width(12.dp))

            // Name and details
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = member.displayName ?: member.email ?: "Unknown",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    if (isCurrentUser) {
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = "(you)",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                if (member.displayName != null && member.email != null) {
                    Text(
                        text = member.email,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                if (member.joinedAt != null) {
                    Text(
                        text = "Joined ${formatMemberDate(member.joinedAt)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                    )
                }
            }

            Spacer(modifier = Modifier.width(8.dp))

            // Role badge
            MemberRoleBadge(role = member.role)

            // Actions menu (only for owners managing non-owners)
            if (canManage) {
                Box {
                    IconButton(
                        onClick = { showMenu = true },
                        enabled = !isUpdating
                    ) {
                        Icon(
                            Icons.Default.MoreVert,
                            contentDescription = "Member actions"
                        )
                    }
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Change Role") },
                            onClick = {
                                showMenu = false
                                onChangeRole()
                            },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.SwapHoriz,
                                    contentDescription = "Change role",
                                    modifier = Modifier.size(20.dp)
                                )
                            }
                        )
                        DropdownMenuItem(
                            text = {
                                Text(
                                    "Remove",
                                    color = MaterialTheme.colorScheme.error
                                )
                            },
                            onClick = {
                                showMenu = false
                                onRemove()
                            },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.PersonRemove,
                                    contentDescription = "Remove member",
                                    modifier = Modifier.size(20.dp),
                                    tint = MaterialTheme.colorScheme.error
                                )
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MemberRoleBadge(role: UserRole) {
    val (text, containerColor) = when (role) {
        UserRole.OWNER -> "Owner" to MaterialTheme.colorScheme.primary
        UserRole.ADMIN -> "Admin" to MaterialTheme.colorScheme.tertiary
        else -> "Member" to MaterialTheme.colorScheme.secondary
    }

    Surface(
        shape = MaterialTheme.shapes.small,
        color = containerColor.copy(alpha = 0.2f)
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelSmall,
            color = containerColor
        )
    }
}

@Composable
private fun ChangeRoleDialog(
    member: TenantMember,
    currentUserRole: UserRole,
    onDismiss: () -> Unit,
    onConfirm: (UserRole) -> Unit
) {
    var selectedRole by remember { mutableStateOf(member.role) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text("Change Role")
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = "Select a new role for ${member.displayName ?: member.email ?: "this member"}:",
                    style = MaterialTheme.typography.bodyMedium
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Member role option
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    RadioButton(
                        selected = selectedRole == UserRole.USER,
                        onClick = { selectedRole = UserRole.USER }
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Column {
                        Text("Member", fontWeight = FontWeight.Medium)
                        Text(
                            "Can view and upload files",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                // Admin role option
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    RadioButton(
                        selected = selectedRole == UserRole.ADMIN,
                        onClick = { selectedRole = UserRole.ADMIN }
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Column {
                        Text("Admin", fontWeight = FontWeight.Medium)
                        Text(
                            "Can manage members and invitations",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(selectedRole) },
                enabled = selectedRole != member.role
            ) {
                Text("Update")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

@Composable
private fun RemoveMemberDialog(
    member: TenantMember,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Remove Member") },
        text = {
            Text(
                "Are you sure you want to remove ${member.displayName ?: member.email ?: "this member"} from the organization? They will lose access to all shared files and folders."
            )
        },
        confirmButton = {
            TextButton(
                onClick = onConfirm,
                colors = ButtonDefaults.textButtonColors(
                    contentColor = MaterialTheme.colorScheme.error
                )
            ) {
                Text("Remove")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

private fun getInitials(displayName: String?, email: String?): String {
    if (displayName != null) {
        val parts = displayName.trim().split(" ")
        return if (parts.size >= 2) {
            "${parts.first().first().uppercase()}${parts.last().first().uppercase()}"
        } else {
            displayName.take(2).uppercase()
        }
    }
    return email?.take(2)?.uppercase() ?: "??"
}

private fun formatMemberDate(dateString: String): String {
    return try {
        dateString.substringBefore("T")
    } catch (e: Exception) {
        dateString
    }
}
