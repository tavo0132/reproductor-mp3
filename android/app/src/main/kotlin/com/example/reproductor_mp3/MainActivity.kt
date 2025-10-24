package com.example.reproductor_mp3

import android.media.AudioManager
import android.media.AudioTrack
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Method

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.reproductor_mp3/equalizer"
    private lateinit var equalizerManager: EqualizerManager
    private var currentAudioSessionId: Int = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        equalizerManager = EqualizerManager()
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAudioSessionId" -> {
                    // Obtener el último AudioTrack creado
                    val sessionId = getLastAudioSessionId()
                    result.success(sessionId)
                }
                
                "initializeEqualizer" -> {
                    val sessionId = call.argument<Int>("audioSessionId") ?: 0
                    currentAudioSessionId = sessionId
                    equalizerManager.initialize(sessionId)
                    result.success(true)
                }
                
                "setEqualizerEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    equalizerManager.setEnabled(enabled)
                    result.success(true)
                }
                
                "setBandLevel" -> {
                    val bandIndex = call.argument<Int>("bandIndex") ?: 0
                    val level = call.argument<Double>("level") ?: 0.0
                    equalizerManager.setBandLevel(bandIndex, level)
                    result.success(true)
                }
                
                "resetBands" -> {
                    equalizerManager.resetBands()
                    result.success(true)
                }
                
                "applyPreset" -> {
                    val values = call.argument<List<Double>>("values") ?: emptyList()
                    equalizerManager.applyPreset(values)
                    result.success(true)
                }
                
                "getEqualizerInfo" -> {
                    val info = equalizerManager.getEqualizerInfo()
                    result.success(info)
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun getLastAudioSessionId(): Int {
        try {
            // Intentar obtener el audioSessionId del último AudioTrack activo
            // Para esto, vamos a usar reflexión para acceder al player interno de audioplayers
            
            // Por ahora, generamos un sessionId válido usando AudioManager
            val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            val sessionId = audioManager.generateAudioSessionId()
            
            android.util.Log.d("MainActivity", "AudioSessionId generado: $sessionId")
            
            // Guardar este sessionId para que el ecualizador lo use
            currentAudioSessionId = sessionId
            
            return sessionId
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error al obtener audioSessionId", e)
            return 0
        }
    }
    
    override fun onDestroy() {
        equalizerManager.release()
        super.onDestroy()
    }
}

