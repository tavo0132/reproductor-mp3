package com.example.reproductor_mp3

import android.content.Context
import android.media.AudioManager
import android.media.AudioTrack
import android.util.Log
import java.lang.reflect.Field

/**
 * Helper class to extract audio session ID from active audio tracks
 */
class AudioSessionHelper(private val context: Context) {
    
    companion object {
        private const val TAG = "AudioSessionHelper"
    }
    
    /**
     * Intenta obtener el audioSessionId de cualquier AudioTrack activo en la app
     */
    fun getActiveAudioSessionId(): Int {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            
            // Genera un nuevo session ID que audioplayers puede usar
            val sessionId = audioManager.generateAudioSessionId()
            Log.d(TAG, "Generated new audio session ID: $sessionId")
            
            return sessionId
        } catch (e: Exception) {
            Log.e(TAG, "Error getting audio session ID", e)
            return 0
        }
    }
}
