package com.studypeaks.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.util.Log

/** Owns the in-app loop and the audio focus for that loop. Runs on the main thread. */
internal class StudyBgmPlayer(
    private val context: Context,
    private val report: (String, Int) -> Unit,
) {
    private val audio = context.getSystemService(AudioManager::class.java)
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()
    private var focusListener: AudioManager.OnAudioFocusChangeListener? = null
    private var focusRequest: AudioFocusRequest? = null
    private var focusSuspended = false
    private var player: MediaPlayer? = null
    private var prepared = false
    private var track: String? = null
    private var volume = 0.35f
    private var enabled = false
    private var playing = false
    private var attempt = 0
    private var interruptedAttempt: Int? = null

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                finishAttempt("interrupted")
            }
        }
    }

    // The noisy broadcast can be suppressed while no media is playing.
    // Watch output removal during breaks and pauses as well.
    private val outputCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            if (removedDevices.any { it.isSink && isHeadphone(it.type) }) {
                finishAttempt("interrupted")
            }
        }
    }

    private fun isHeadphone(type: Int): Boolean = when (type) {
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_HEARING_AID,
        AudioDeviceInfo.TYPE_USB_HEADSET -> true
        else -> false
    }

    init {
        audio.registerAudioDeviceCallback(outputCallback, null)
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(noisyReceiver, filter)
        }
    }

    fun update(track: String?, volume: Float, enabled: Boolean, playing: Boolean, attempt: Int) {
        this.attempt = attempt
        this.volume = volume
        this.enabled = enabled && attempt != interruptedAttempt
        this.playing = this.enabled && playing
        if (this.track != track) {
            releasePlayer()
            this.track = track
        }
        when {
            track != null && player == null && this.playing -> prepare(track)
            prepared -> applyPlayback()
            !this.playing -> releaseAudioFocus()
        }
    }

    fun suspendPlayback() {
        playing = false
        if (prepared) applyPlayback() else releaseAudioFocus()
    }

    private fun prepare(track: String) {
        val candidate = MediaPlayer()
        player = candidate
        try {
            candidate.setAudioAttributes(attributes)
            context.assets.openFd("study_bgm/$track.ogg").use { asset ->
                candidate.setDataSource(asset.fileDescriptor, asset.startOffset, asset.length)
            }
            candidate.setOnErrorListener { failed, what, extra ->
                if (player === failed) fail("MediaPlayer error $what/$extra")
                true
            }
            candidate.setOnPreparedListener { ready ->
                if (player === ready) {
                    prepared = true
                    applyPlayback()
                }
            }
            candidate.prepareAsync()
        } catch (error: Exception) {
            fail("Unable to prepare bundled audio", error)
        }
    }

    private fun applyPlayback() {
        val current = player ?: return
        try {
            current.isLooping = true
            current.setVolume(volume, volume)
            if (playing && !focusSuspended) {
                if (!current.isPlaying) {
                    if (!requestAudioFocus()) {
                        fail("Audio focus denied")
                        return
                    }
                    current.start()
                }
            } else {
                if (current.isPlaying) current.pause()
                if (!playing) releaseAudioFocus()
            }
        } catch (error: IllegalStateException) {
            fail("Unable to change audio playback", error)
        }
    }

    @Suppress("DEPRECATION")
    private fun requestAudioFocus(): Boolean {
        if (focusListener != null) return true
        val listener = object : AudioManager.OnAudioFocusChangeListener {
            override fun onAudioFocusChange(change: Int) {
                if (focusListener !== this) return
                when (change) {
                    AudioManager.AUDIOFOCUS_LOSS -> finishAttempt("interrupted")
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                        focusSuspended = true
                        if (prepared) applyPlayback()
                    }
                    AudioManager.AUDIOFOCUS_GAIN -> {
                        focusSuspended = false
                        if (prepared) applyPlayback()
                    }
                }
            }
        }
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes)
                .setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener(listener)
                .build()
            focusRequest = request
            audio.requestAudioFocus(request)
        } else {
            audio.requestAudioFocus(listener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            focusRequest = null
            return false
        }
        focusListener = listener
        return true
    }

    @Suppress("DEPRECATION")
    private fun releaseAudioFocus() {
        focusSuspended = false
        val listener = focusListener ?: return
        focusListener = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audio.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            audio.abandonAudioFocus(listener)
        }
    }

    private fun fail(message: String, error: Exception? = null) {
        Log.w("StudyBgmPlayer", message, error)
        finishAttempt("failed")
    }

    private fun finishAttempt(event: String) {
        if (!enabled) return
        enabled = false
        playing = false
        interruptedAttempt = attempt
        releasePlayer()
        releaseAudioFocus()
        report(event, attempt)
    }

    private fun releasePlayer() {
        val previous = player
        player = null
        prepared = false
        previous?.release()
    }

    fun dispose() {
        releasePlayer()
        releaseAudioFocus()
        audio.unregisterAudioDeviceCallback(outputCallback)
        context.unregisterReceiver(noisyReceiver)
    }
}
