package com.example.codexlan.data

import kotlinx.serialization.SerializationException
import kotlinx.serialization.encodeToString
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

class BridgeClient(
    private val json: kotlinx.serialization.json.Json = ProtocolJson,
) {
    private val client = OkHttpClient.Builder()
        .pingInterval(30, TimeUnit.SECONDS)
        .build()

    private var webSocket: WebSocket? = null

    fun connect(url: String, observer: (BridgeEvent) -> Unit) {
        close()
        observer(BridgeEvent.Connecting)
        val request = Request.Builder().url(url).build()
        webSocket = client.newWebSocket(
            request,
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    observer(BridgeEvent.Open)
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    val message = runCatching {
                        json.decodeFromString(ServerMessage.serializer(), text)
                    }.getOrElse { error ->
                        val explanation = when (error) {
                            is SerializationException -> error.message ?: "Serialization error"
                            else -> error.message ?: error.toString()
                        }
                        observer(BridgeEvent.Failure("Could not decode bridge message: $explanation"))
                        return
                    }
                    observer(BridgeEvent.Message(message))
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(code, reason)
                    observer(BridgeEvent.Closed(reason.ifBlank { "closing" }))
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    observer(BridgeEvent.Closed(reason.ifBlank { "closed" }))
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    observer(BridgeEvent.Failure(t.message ?: "WebSocket failure"))
                }
            },
        )
    }

    fun send(message: ClientMessage): Boolean {
        val encoded = json.encodeToString(ClientMessage.serializer(), message)
        return webSocket?.send(encoded) == true
    }

    fun close() {
        webSocket?.close(1000, "client closing")
        webSocket = null
    }
}

sealed interface BridgeEvent {
    data object Connecting : BridgeEvent
    data object Open : BridgeEvent
    data class Message(val message: ServerMessage) : BridgeEvent
    data class Closed(val reason: String) : BridgeEvent
    data class Failure(val message: String) : BridgeEvent
}
