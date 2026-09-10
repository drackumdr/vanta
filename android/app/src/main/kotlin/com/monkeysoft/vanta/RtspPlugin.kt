package com.monkeysoft.vanta

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.concurrent.ConcurrentHashMap

/**
 * Bridges Flutter/Dart to native Media3 ExoPlayer RTSP playback.
 *
 * Dart -> Native:
 *   create {url} -> {playerId, textureId}
 *   open   {playerId, url}
 *   play   {playerId}
 *   pause  {playerId}
 *   mute   {playerId, muted}
 *   dispose{playerId}
 *
 * Native -> Dart (EventChannel "vanta/rtsp/events"):
 *   {playerId, type: "state"|"error", payload: "0"|"1"|"2"|"3"| friendlyMessage}
 */
object RtspPlugin {
    private const val CHANNEL = "vanta/rtsp"
    private const val EVENTS = "vanta/rtsp/events"

    private val players = ConcurrentHashMap<Long, RtspPlayer>()
    private var appContext: Context? = null
    private var textureRegistry: TextureRegistry? = null
    private var eventSink: EventChannel.EventSink? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    fun register(engine: FlutterEngine, context: Context) {
        appContext = context.applicationContext
        textureRegistry = engine.renderer
        val messenger: BinaryMessenger = engine.dartExecutor.binaryMessenger

        methodChannel?.setMethodCallHandler(null)
        methodChannel = MethodChannel(messenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler(::onMethodCall)
        }

        eventChannel?.setStreamHandler(null)
        eventChannel = EventChannel(messenger, EVENTS).also { ec ->
            ec.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.error("E_ARGS", "Se requiere 'url'", null)
                    return
                }
                val registry = textureRegistry
                val ctx = appContext
                if (registry == null || ctx == null) {
                    result.error("E_NATIVE", "Plugin no inicializado", null)
                    return
                }
                try {
                    val entry = registry.createSurfaceTexture()
                    val player = RtspPlayer(ctx, entry) { type, payload ->
                        eventSink?.success(
                            mapOf(
                                "playerId" to entry.id(),
                                "type" to type,
                                "payload" to payload,
                            )
                        )
                    }
                    players[player.playerId] = player
                    player.open(url)
                    result.success(
                        mapOf(
                            "playerId" to player.playerId,
                            "textureId" to player.playerId,
                        )
                    )
                } catch (t: Throwable) {
                    result.error("E_CREATE", t.message, null)
                }
            }

            "open" -> {
                val player = playerArg(call) ?: return result.error("E_ID", "playerId inválido", null)
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.error("E_ARGS", "Se requiere 'url'", null)
                    return
                }
                player.open(url)
                result.success(null)
            }

            "play" -> {
                val player = playerArg(call) ?: return result.error("E_ID", "playerId inválido", null)
                player.play()
                result.success(null)
            }

            "pause" -> {
                val player = playerArg(call) ?: return result.error("E_ID", "playerId inválido", null)
                player.pause()
                result.success(null)
            }

            "mute" -> {
                val player = playerArg(call) ?: return result.error("E_ID", "playerId inválido", null)
                player.setMuted(call.argument<Boolean>("muted") ?: true)
                result.success(null)
            }

            "dispose" -> {
                val player = playerArg(call) ?: return result.error("E_ID", "playerId inválido", null)
                players.remove(player.playerId)
                player.release()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun playerArg(call: MethodCall): RtspPlayer? {
        val id = (call.argument<Any>("playerId") as? Number)?.toLong() ?: return null
        return players[id]
    }
}