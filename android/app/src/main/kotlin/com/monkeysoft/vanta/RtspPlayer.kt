package com.monkeysoft.vanta

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.rtsp.RtspMediaSource
import io.flutter.view.TextureRegistry

/**
 * Wrapper over one ExoPlayer rendered into a Flutter external texture (SurfaceTexture).
 * One instance per visible camera. Frames are consumed automatically by the Flutter
 * engine via the registered texture id (same mechanism as video_player).
 */
class RtspPlayer(
    context: Context,
    private val textureEntry: TextureRegistry.SurfaceTextureEntry,
    private val onEvent: (type: String, payload: String?) -> Unit,
) {
    val playerId: Long = textureEntry.id()

    private val mainHandler = Handler(Looper.getMainLooper())
    private var surface: Surface? = null
    private var lastState = -1

    private val loadControl = DefaultLoadControl.Builder()
        .setBufferDurationsMs(
            500,  // minBufferMs
            3000, // maxBufferMs
            250,  // bufferForPlaybackMs
            500   // bufferForPlaybackAfterRebufferMs
        )
        .setPrioritizeTimeOverSizeThresholds(true)
        .build()

    val player: ExoPlayer = ExoPlayer.Builder(context)
        .setLoadControl(loadControl)
        .build()
        .apply {
            setVolume(0f)
            setHandleAudioBecomingNoisy(false)
        }

    init {
        val texture = textureEntry.surfaceTexture()
        texture.setDefaultBufferSize(1920, 1080)
        surface = Surface(texture)
        player.setVideoSurface(surface)
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                emitCurrentState()
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                emitCurrentState()
            }

            override fun onRenderedFirstFrame() {
                lastState = STATE_READY
                emit("state", STATE_READY.toString())
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    texture.setDefaultBufferSize(videoSize.width, videoSize.height)
                    emit("videoSize", "${videoSize.width}x${videoSize.height}")
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                lastState = STATE_IDLING
                emit("error", friendlyError(error))
            }
        })
    }

    fun open(url: String) {
        lastState = -1
        player.stop()
        val source = RtspMediaSource.Factory()
            .setForceUseRtpTcp(true)
            .setUserAgent("VANTA/1.0")
            .setTimeoutMs(10000L)
            .createMediaSource(MediaItem.fromUri(url))
        player.setMediaSource(source, true)
        player.prepare()
        player.play()
    }

    fun play() {
        player.play()
    }

    fun pause() {
        player.pause()
    }

    fun setMuted(muted: Boolean) {
        player.volume = if (muted) 0f else 1f
    }

    fun emitCurrentState(force: Boolean = false) {
        val newState = when {
            player.playbackState == Player.STATE_IDLE -> STATE_IDLING
            player.playbackState == Player.STATE_BUFFERING -> STATE_BUFFERING
            player.playbackState == Player.STATE_ENDED -> STATE_ENDED
            else -> STATE_READY
        }
        if (force || newState != lastState) {
            lastState = newState
            emit("state", newState.toString())
        }
    }

    private fun emit(type: String, payload: String?) {
        mainHandler.post { onEvent(type, payload) }
    }

    private fun friendlyError(error: PlaybackException): String {
        return when (error.errorCode) {
            PlaybackException.ERROR_CODE_TIMEOUT,
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT -> "Tiempo de espera agotado"
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
            PlaybackException.ERROR_CODE_IO_UNSPECIFIED,
            PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND -> "No se pudo conectar al dispositivo"
            PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS,
            PlaybackException.ERROR_CODE_IO_NO_PERMISSION -> "El dispositivo rechazó la conexión"
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED -> "Formato de video no soportado"
            else -> "No se pudo reproducir el video"
        }
    }

    fun release() {
        player.release()
        surface?.release()
        surface = null
        textureEntry.release()
    }

    companion object {
        const val STATE_IDLING = 0
        const val STATE_BUFFERING = 1
        const val STATE_READY = 2
        const val STATE_ENDED = 3
    }
}