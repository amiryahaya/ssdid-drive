package my.ssdid.drive.presentation.onboarding

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/**
 * Onboarding screen shown to first-time users.
 * Explains key features and benefits of SSDID Drive.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun OnboardingScreen(
    onComplete: () -> Unit
) {
    val haptic = LocalHapticFeedback.current
    val coroutineScope = rememberCoroutineScope()

    val pages = listOf(
        OnboardingPage(
            icon = Icons.Default.Security,
            title = "Post-Quantum Security",
            description = "Your files are protected with cutting-edge post-quantum cryptography, safe against both current and future quantum computer attacks.",
            color = Color(0xFF1976D2)
        ),
        OnboardingPage(
            icon = Icons.Default.Share,
            title = "Secure Sharing",
            description = "Share files with anyone using end-to-end encryption. Only you and your recipients can access the content.",
            color = Color(0xFF26A69A)
        ),
        OnboardingPage(
            icon = Icons.Default.Restore,
            title = "Social Recovery",
            description = "Never lose access to your files. Set up trusted contacts who can help you recover your account if needed.",
            color = Color(0xFF7C4DFF)
        ),
        OnboardingPage(
            icon = Icons.Default.Devices,
            title = "Multi-Device Sync",
            description = "Access your encrypted files from any device. Changes sync automatically while maintaining full security.",
            color = Color(0xFFFF7043)
        )
    )

    val pagerState = rememberPagerState(pageCount = { pages.size })

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        Column(
            modifier = Modifier.fillMaxSize()
        ) {
            // Skip button
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalArrangement = Arrangement.End
            ) {
                if (pagerState.currentPage < pages.size - 1) {
                    TextButton(
                        onClick = {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            onComplete()
                        }
                    ) {
                        Text("Skip")
                    }
                }
            }

            // Pager content
            HorizontalPager(
                state = pagerState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) { page ->
                OnboardingPageContent(
                    page = pages[page],
                    modifier = Modifier.fillMaxSize()
                )
            }

            // Bottom section with indicators and button
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Page indicators
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(bottom = 32.dp)
                ) {
                    pages.forEachIndexed { index, _ ->
                        PageIndicator(
                            isSelected = index == pagerState.currentPage,
                            color = pages[pagerState.currentPage].color
                        )
                    }
                }

                // Next/Get Started button
                Button(
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        if (pagerState.currentPage < pages.size - 1) {
                            coroutineScope.launch {
                                pagerState.animateScrollToPage(pagerState.currentPage + 1)
                            }
                        } else {
                            onComplete()
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = pages[pagerState.currentPage].color
                    )
                ) {
                    Text(
                        text = if (pagerState.currentPage < pages.size - 1) "Next" else "Get Started",
                        style = MaterialTheme.typography.titleMedium
                    )
                    if (pagerState.currentPage < pages.size - 1) {
                        Spacer(modifier = Modifier.width(8.dp))
                        Icon(
                            Icons.Default.ArrowForward,
                            contentDescription = null,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun OnboardingPageContent(
    page: OnboardingPage,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        // Animated icon with gradient background
        Box(
            modifier = Modifier
                .size(160.dp)
                .clip(CircleShape)
                .background(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            page.color.copy(alpha = 0.3f),
                            page.color.copy(alpha = 0.1f),
                            Color.Transparent
                        )
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .clip(CircleShape)
                    .background(page.color.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = page.icon,
                    contentDescription = null,
                    modifier = Modifier.size(56.dp),
                    tint = page.color
                )
            }
        }

        Spacer(modifier = Modifier.height(48.dp))

        // Title
        Text(
            text = page.title,
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onBackground
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Description
        Text(
            text = page.description,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp)
        )
    }
}

@Composable
private fun PageIndicator(
    isSelected: Boolean,
    color: Color
) {
    val width by animateDpAsState(
        targetValue = if (isSelected) 24.dp else 8.dp,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy),
        label = "indicator_width"
    )

    Box(
        modifier = Modifier
            .height(8.dp)
            .width(width)
            .clip(RoundedCornerShape(4.dp))
            .background(
                if (isSelected) color
                else MaterialTheme.colorScheme.outlineVariant
            )
    )
}

private data class OnboardingPage(
    val icon: ImageVector,
    val title: String,
    val description: String,
    val color: Color
)
