package com.securesharing.domain.model

/**
 * Configuration for LLM providers.
 */
data class LlmProvider(
    val id: String,
    val name: String,
    val models: List<String>
) {
    companion object {
        val providers = listOf(
            LlmProvider(
                id = "openai",
                name = "OpenAI",
                models = listOf("gpt-4o", "gpt-4o-mini", "gpt-4-turbo")
            ),
            LlmProvider(
                id = "anthropic",
                name = "Anthropic",
                models = listOf("claude-3-opus", "claude-3-sonnet", "claude-3-haiku")
            ),
            LlmProvider(
                id = "google",
                name = "Google",
                models = listOf("gemini-pro", "gemini-pro-vision")
            )
        )

        fun findById(id: String): LlmProvider? = providers.find { it.id == id }
    }
}
