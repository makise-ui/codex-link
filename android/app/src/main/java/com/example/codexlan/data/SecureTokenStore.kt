package com.example.codexlan.data

import android.content.Context

class SecureTokenStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("codex_lan_tokens", Context.MODE_PRIVATE)

    fun save(credentials: StoredBridgeCredentials) {
        prefs.edit()
            .putString(KEY_URL, credentials.url)
            .putString(KEY_DEVICE_ID, credentials.deviceId)
            .putString(KEY_DEVICE_TOKEN, credentials.deviceToken)
            .putString(KEY_SESSION_ID, credentials.sessionId)
            .apply()
    }

    fun load(): StoredBridgeCredentials? {
        val url = prefs.getString(KEY_URL, null) ?: return null
        val deviceId = prefs.getString(KEY_DEVICE_ID, null) ?: return null
        val deviceToken = prefs.getString(KEY_DEVICE_TOKEN, null) ?: return null
        val sessionId = prefs.getString(KEY_SESSION_ID, null) ?: return null
        return StoredBridgeCredentials(url, deviceId, deviceToken, sessionId)
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    private companion object {
        const val KEY_URL = "url"
        const val KEY_DEVICE_ID = "device_id"
        const val KEY_DEVICE_TOKEN = "device_token"
        const val KEY_SESSION_ID = "session_id"
    }
}

data class StoredBridgeCredentials(
    val url: String,
    val deviceId: String,
    val deviceToken: String,
    val sessionId: String,
)
