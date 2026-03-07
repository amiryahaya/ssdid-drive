package com.securesharing.presentation.common

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

// ==================== Speed Dial FAB ====================

/**
 * Data class representing a speed dial action item.
 */
data class SpeedDialItem(
    val icon: ImageVector,
    val label: String,
    val onClick: () -> Unit,
    val containerColor: Color? = null
)

/**
 * Expandable Speed Dial FAB that shows multiple action items when expanded.
 * Replaces multiple stacked FABs with a more intuitive pattern.
 */
@Composable
fun SpeedDialFab(
    items: List<SpeedDialItem>,
    modifier: Modifier = Modifier,
    mainIcon: ImageVector = Icons.Default.Add,
    expandedIcon: ImageVector = Icons.Default.Close,
    mainFabColor: Color = MaterialTheme.colorScheme.primaryContainer,
    mainFabContentColor: Color = MaterialTheme.colorScheme.onPrimaryContainer
) {
    var isExpanded by remember { mutableStateOf(false) }
    val haptic = LocalHapticFeedback.current

    // Rotation animation for main FAB icon
    val rotation by animateFloatAsState(
        targetValue = if (isExpanded) 45f else 0f,
        animationSpec = tween(300),
        label = "fab_rotation"
    )

    // Scale animation for main FAB
    val scale by animateFloatAsState(
        targetValue = if (isExpanded) 1.1f else 1f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy),
        label = "fab_scale"
    )

    Box(
        modifier = modifier,
        contentAlignment = Alignment.BottomEnd
    ) {
        // Scrim when expanded
        AnimatedVisibility(
            visible = isExpanded,
            enter = fadeIn(animationSpec = tween(200)),
            exit = fadeOut(animationSpec = tween(200))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.3f))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null
                    ) {
                        isExpanded = false
                    }
            )
        }

        Column(
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Speed dial items
            items.forEachIndexed { index, item ->
                val itemDelay = (items.size - 1 - index) * 50

                AnimatedVisibility(
                    visible = isExpanded,
                    enter = fadeIn(animationSpec = tween(200, delayMillis = itemDelay)) +
                            slideInVertically(
                                animationSpec = tween(200, delayMillis = itemDelay),
                                initialOffsetY = { it }
                            ) +
                            scaleIn(animationSpec = tween(200, delayMillis = itemDelay)),
                    exit = fadeOut(animationSpec = tween(150)) +
                            slideOutVertically(
                                animationSpec = tween(150),
                                targetOffsetY = { it }
                            ) +
                            scaleOut(animationSpec = tween(150))
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        // Label chip
                        Surface(
                            color = MaterialTheme.colorScheme.surfaceVariant,
                            shape = RoundedCornerShape(8.dp),
                            shadowElevation = 2.dp
                        ) {
                            Text(
                                text = item.label,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }

                        // Mini FAB
                        SmallFloatingActionButton(
                            onClick = {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                item.onClick()
                                isExpanded = false
                            },
                            containerColor = item.containerColor ?: MaterialTheme.colorScheme.secondaryContainer,
                            contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                            modifier = Modifier.semantics {
                                contentDescription = item.label
                            }
                        ) {
                            Icon(item.icon, contentDescription = null)
                        }
                    }
                }
            }

            // Main FAB
            FloatingActionButton(
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    isExpanded = !isExpanded
                },
                containerColor = mainFabColor,
                contentColor = mainFabContentColor,
                modifier = Modifier
                    .scale(scale)
                    .semantics {
                        contentDescription = if (isExpanded) "Close menu" else "Open actions menu"
                    }
            ) {
                Icon(
                    imageVector = if (isExpanded) expandedIcon else mainIcon,
                    contentDescription = null,
                    modifier = Modifier.rotate(rotation)
                )
            }
        }
    }
}

// ==================== Enhanced Empty States ====================

/**
 * Enhanced empty folder state with illustration and better visual hierarchy.
 */
@Composable
fun EnhancedEmptyFolderState(
    isRootFolder: Boolean = true,
    onCreateFolder: (() -> Unit)? = null,
    onUploadFile: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val haptic = LocalHapticFeedback.current

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Animated illustration
        Box(
            modifier = Modifier
                .size(120.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = if (isRootFolder) Icons.Default.CloudUpload else Icons.Default.FolderOpen,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.primary
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = if (isRootFolder) "Welcome to SecureSharing" else "This folder is empty",
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = if (isRootFolder)
                "Your files are protected with post-quantum encryption.\nStart by uploading your first file."
            else
                "Add files or create subfolders to organize your content.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Primary action - Upload
        if (onUploadFile != null) {
            Button(
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onUploadFile()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
            ) {
                Icon(
                    Icons.Default.Upload,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Upload File")
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Secondary action - Create folder
        if (onCreateFolder != null) {
            OutlinedButton(
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onCreateFolder()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
            ) {
                Icon(
                    Icons.Default.CreateNewFolder,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Create Folder")
            }
        }

        // Tip for root folder
        if (isRootFolder) {
            Spacer(modifier = Modifier.height(24.dp))

            Surface(
                color = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.5f),
                shape = RoundedCornerShape(12.dp)
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.Lightbulb,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.tertiary,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = "Tip: Share files securely with other users using end-to-end encryption.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onTertiaryContainer
                    )
                }
            }
        }
    }
}

/**
 * Enhanced empty search results state.
 */
@Composable
fun EmptySearchState(
    query: String,
    onClearSearch: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.SearchOff,
            contentDescription = null,
            modifier = Modifier.size(80.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "No results found",
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurface
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "We couldn't find anything matching \"$query\"",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(24.dp))

        OutlinedButton(onClick = onClearSearch) {
            Icon(
                Icons.Default.Clear,
                contentDescription = null,
                modifier = Modifier.size(18.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text("Clear Search")
        }
    }
}

// ==================== Undo Snackbar ====================

/**
 * Data class for undo-able delete operations.
 */
data class DeletedItem(
    val id: String,
    val name: String,
    val isFolder: Boolean
)

/**
 * Show snackbar with undo action for delete operations.
 */
suspend fun SnackbarHostState.showUndoDeleteSnackbar(
    itemName: String,
    itemCount: Int = 1,
    onUndo: () -> Unit
): SnackbarResult {
    val message = if (itemCount == 1) {
        "\"$itemName\" deleted"
    } else {
        "$itemCount items deleted"
    }

    val result = showSnackbar(
        message = message,
        actionLabel = "Undo",
        duration = SnackbarDuration.Long
    )

    if (result == SnackbarResult.ActionPerformed) {
        onUndo()
    }

    return result
}

// ==================== Haptic Touch Modifiers ====================

/**
 * Extension function to add haptic feedback to clickable modifiers.
 */
@Composable
fun Modifier.hapticClickable(
    enabled: Boolean = true,
    hapticType: HapticFeedbackType = HapticFeedbackType.LongPress,
    onClick: () -> Unit
): Modifier {
    val haptic = LocalHapticFeedback.current
    return this.clickable(enabled = enabled) {
        haptic.performHapticFeedback(hapticType)
        onClick()
    }
}

// ==================== Pull to Refresh ====================

/**
 * Simple pull-to-refresh indicator that shows at the top when refreshing.
 * This is a simplified version that doesn't include the drag gesture
 * but works with the existing Material3 version.
 */
@Composable
fun PullToRefreshContainer(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Box(modifier = modifier) {
        content()

        // Animated refresh indicator at top
        AnimatedVisibility(
            visible = isRefreshing,
            enter = fadeIn() + slideInVertically(initialOffsetY = { -it }),
            exit = fadeOut() + slideOutVertically(targetOffsetY = { -it }),
            modifier = Modifier.align(Alignment.TopCenter)
        ) {
            Surface(
                modifier = Modifier
                    .padding(top = 8.dp)
                    .size(40.dp),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.primaryContainer,
                shadowElevation = 4.dp
            ) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier.fillMaxSize()
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
        }
    }
}

// ==================== Touch Target Size ====================

/**
 * Ensures minimum touch target size of 48dp as per accessibility guidelines.
 */
fun Modifier.minTouchTarget(size: Dp = 48.dp): Modifier {
    return this.sizeIn(minWidth = size, minHeight = size)
}

// ==================== Section Headers ====================

/**
 * Section header for separating content types (folders vs files).
 */
@Composable
fun SectionHeader(
    title: String,
    count: Int? = null,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary
        )

        if (count != null) {
            Spacer(modifier = Modifier.width(8.dp))
            Surface(
                color = MaterialTheme.colorScheme.primaryContainer,
                shape = CircleShape
            ) {
                Text(
                    text = count.toString(),
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
        }
    }
}

// ==================== Swipe Actions ====================

/**
 * Simple swipeable list item wrapper.
 * Note: Full swipe-to-dismiss requires newer Material3 APIs.
 * This is a placeholder that just renders the content.
 * Swipe actions can be added when upgrading to Material3 1.2+
 */
@Composable
fun SwipeableListItem(
    onSwipeLeft: () -> Unit = {},
    onSwipeRight: () -> Unit = {},
    leftContent: @Composable () -> Unit = {},
    rightContent: @Composable () -> Unit = {},
    content: @Composable () -> Unit
) {
    // Simple wrapper - swipe actions require newer Material3 version
    // For now, just render the content
    content()
}
