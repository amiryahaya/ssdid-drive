package my.ssdid.drive.domain.model

import my.ssdid.drive.crypto.PqcAlgorithm

/**
 * Domain model for tenant configuration.
 */
data class TenantConfig(
    val id: String,
    val name: String,
    val slug: String,
    val pqcAlgorithm: PqcAlgorithm,
    val plan: String,
    val settings: Map<String, Any>?
)
