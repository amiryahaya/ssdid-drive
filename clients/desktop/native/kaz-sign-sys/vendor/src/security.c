/*
 * KAZ-SIGN Security Utilities Implementation
 *
 * Production hardening functions for secure memory handling,
 * constant-time operations, and side-channel resistance.
 */

#include "kaz/security.h"
#include <stdlib.h>

/* Global security state */
static kaz_security_state_t g_security_state = {
    .initialized = 0,
    .constant_time_enabled = 1,
    .zeroize_on_free = 1,
    .operations_count = 0
};

kaz_security_state_t *kaz_get_security_state(void)
{
    return &g_security_state;
}

void kaz_security_init(void)
{
    g_security_state.initialized = 1;
    g_security_state.constant_time_enabled = 1;
    g_security_state.zeroize_on_free = 1;
    g_security_state.operations_count = 0;
}

void kaz_security_cleanup(void)
{
    /* Securely clear the state */
    kaz_secure_zero(&g_security_state, sizeof(g_security_state));
    g_security_state.initialized = 0;
}
