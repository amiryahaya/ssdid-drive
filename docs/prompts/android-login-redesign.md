# Android Login Screen Redesign — Smart Wallet Detection

Apply the same smart wallet detection pattern as iOS. See `docs/prompts/login-page-redesign.md` for the full spec.

## Implementation

### Wallet Detection (Kotlin)
```kotlin
val walletInstalled = try {
    context.packageManager.resolveActivity(
        Intent(Intent.ACTION_VIEW, Uri.parse("ssdid://")),
        PackageManager.MATCH_DEFAULT_ONLY
    ) != null
} catch (_: Exception) { false }
```

### Changes to `LoginScreen.kt`

1. Add `isWalletInstalled` to `LoginUiState` (set in ViewModel init)
2. If wallet installed:
   - Show big "Open SSDID Wallet" button as primary (full width, 56dp)
   - Collapse email/OIDC behind expandable "Other sign in options"
   - No QR code (same device)
3. If no wallet:
   - Show email + OIDC as primary (current layout minus QR prominence)
   - QR code at bottom for cross-device
   - "Get SSDID Wallet" link to Play Store

### Changes to `LoginViewModel.kt`

```kotlin
// In init:
val intent = Intent(Intent.ACTION_VIEW, Uri.parse("ssdid://"))
val walletInstalled = intent.resolveActivity(context.packageManager) != null
_uiState.update { it.copy(isWalletInstalled = walletInstalled) }
```

### Compose Layout (wallet installed)
```kotlin
if (uiState.isWalletInstalled) {
    // Big wallet button
    Button(
        onClick = { viewModel.openWallet() },
        modifier = Modifier.fillMaxWidth().height(56.dp)
    ) {
        Icon(Icons.Default.Lock, "Wallet")
        Spacer(Modifier.width(8.dp))
        Text("Open SSDID Wallet", fontWeight = FontWeight.SemiBold)
    }

    // Expandable "Other sign in options"
    var expanded by remember { mutableStateOf(false) }
    TextButton(onClick = { expanded = !expanded }) {
        Icon(if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore, null)
        Text("Other sign in options")
    }
    AnimatedVisibility(visible = expanded) {
        Column { /* email field, OIDC buttons */ }
    }
} else {
    // Current layout: email + OIDC + QR
}
```
