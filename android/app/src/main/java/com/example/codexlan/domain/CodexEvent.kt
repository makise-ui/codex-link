package com.example.codexlan.domain

data class ChatLine(
    val id: String,
    val role: ChatRole,
    val text: String,
    val runId: String? = null,
    val stream: String? = null,
)

enum class ChatRole {
    User,
    Assistant,
    System,
    Error,
}
