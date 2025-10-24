package com.example.reproductor_mp3

import android.media.audiofx.Equalizer
import android.media.MediaPlayer
import android.util.Log

class EqualizerManager {
    private var equalizer: Equalizer? = null
    private var isEnabled = false
    
    companion object {
        private const val TAG = "EqualizerManager"
        
        // Frecuencias objetivo para las 7 bandas (en Hz)
        private val TARGET_FREQUENCIES = intArrayOf(
            60,      // Banda 0: 60 Hz
            150,     // Banda 1: 150 Hz
            400,     // Banda 2: 400 Hz
            1000,    // Banda 3: 1 kHz
            2400,    // Banda 4: 2.4 kHz
            6000,    // Banda 5: 6 kHz
            15000    // Banda 6: 15 kHz
        )
    }
    
    /**
     * Inicializa el ecualizador con el ID de sesión de audio
     */
    fun initialize(audioSessionId: Int) {
        try {
            release() // Liberar ecualizador anterior si existe
            
            Log.d(TAG, "Intentando inicializar ecualizador con sessionId: $audioSessionId")
            
            // Usar sessionId = 0 para afectar TODA la salida de audio de la app
            // Esto incluye el reproductor audioplayers
            equalizer = Equalizer(0, 0).apply {
                enabled = false // Iniciar desactivado
            }
            
            Log.d(TAG, "✓ Ecualizador inicializado correctamente!")
            Log.d(TAG, "Session ID usado: 0 (global - afecta toda la app incluyendo audioplayers)")
            Log.d(TAG, "Bandas disponibles: ${equalizer?.numberOfBands}")
            Log.d(TAG, "Rango de bandas: ${equalizer?.bandLevelRange?.get(0)} a ${equalizer?.bandLevelRange?.get(1)} mB")
            
            // Mostrar frecuencias centrales de cada banda
            for (i in 0 until (equalizer?.numberOfBands ?: 0)) {
                val freq = equalizer?.getCenterFreq(i.toShort()) ?: 0
                Log.d(TAG, "Banda $i: ${freq / 1000} Hz")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "✗ Error al inicializar ecualizador: ${e.message}")
            e.printStackTrace()
            equalizer = null
        }
    }
    
    /**
     * Activa o desactiva el ecualizador
     */
    fun setEnabled(enabled: Boolean) {
        isEnabled = enabled
        equalizer?.enabled = enabled
        Log.d(TAG, "Ecualizador ${if (enabled) "activado" else "desactivado"}")
    }
    
    /**
     * Establece el nivel de una banda específica
     * @param bandIndex Índice de la banda (0-6 para nuestras 7 bandas)
     * @param level Nivel en dB (-12.0 a +12.0)
     */
    fun setBandLevel(bandIndex: Int, level: Double) {
        try {
            val eq = equalizer ?: run {
                Log.w(TAG, "Ecualizador no inicializado")
                return
            }
            
            // Validar índice de banda
            if (bandIndex < 0 || bandIndex >= TARGET_FREQUENCIES.size) {
                Log.w(TAG, "Índice de banda inválido: $bandIndex")
                return
            }
            
            // Encontrar la banda nativa más cercana a nuestra frecuencia objetivo
            val nativeBandIndex = findClosestBand(TARGET_FREQUENCIES[bandIndex])
            
            // Convertir dB a milibelios (1 dB = 100 mB)
            val levelInMillibels = (level * 100).toInt().toShort()
            
            // Aplicar el nivel a la banda
            eq.setBandLevel(nativeBandIndex, levelInMillibels)
            
            Log.d(TAG, "Banda $bandIndex (${TARGET_FREQUENCIES[bandIndex]} Hz) -> Nivel: $level dB ($levelInMillibels mB)")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error al establecer nivel de banda: ${e.message}")
        }
    }
    
    /**
     * Encuentra la banda nativa más cercana a una frecuencia objetivo
     */
    private fun findClosestBand(targetFreq: Int): Short {
        val eq = equalizer ?: return 0
        
        var closestBand: Short = 0
        var minDiff = Int.MAX_VALUE
        
        for (i in 0 until eq.numberOfBands) {
            val bandFreq = eq.getCenterFreq(i.toShort()) / 1000 // Convertir mHz a Hz
            val diff = Math.abs(bandFreq - targetFreq)
            
            if (diff < minDiff) {
                minDiff = diff
                closestBand = i.toShort()
            }
        }
        
        return closestBand
    }
    
    /**
     * Resetea todas las bandas a 0 dB
     */
    fun resetBands() {
        try {
            val eq = equalizer ?: return
            
            for (i in 0 until TARGET_FREQUENCIES.size) {
                setBandLevel(i, 0.0)
            }
            
            Log.d(TAG, "Todas las bandas reseteadas a 0 dB")
        } catch (e: Exception) {
            Log.e(TAG, "Error al resetear bandas: ${e.message}")
        }
    }
    
    /**
     * Aplica un preajuste completo
     */
    fun applyPreset(bandValues: List<Double>) {
        if (bandValues.size != TARGET_FREQUENCIES.size) {
            Log.w(TAG, "Número incorrecto de valores para preajuste")
            return
        }
        
        for (i in bandValues.indices) {
            setBandLevel(i, bandValues[i])
        }
        
        Log.d(TAG, "Preajuste aplicado: $bandValues")
    }
    
    /**
     * Obtiene información del ecualizador
     */
    fun getEqualizerInfo(): Map<String, Any> {
        val eq = equalizer
        
        return if (eq != null) {
            mapOf(
                "initialized" to true,
                "enabled" to isEnabled,
                "numberOfBands" to eq.numberOfBands,
                "bandLevelRange" to listOf(
                    eq.bandLevelRange[0] / 100, // Convertir mB a dB
                    eq.bandLevelRange[1] / 100
                )
            )
        } else {
            mapOf(
                "initialized" to false,
                "enabled" to false
            )
        }
    }
    
    /**
     * Libera recursos del ecualizador
     */
    fun release() {
        try {
            equalizer?.release()
            equalizer = null
            Log.d(TAG, "Ecualizador liberado")
        } catch (e: Exception) {
            Log.e(TAG, "Error al liberar ecualizador: ${e.message}")
        }
    }
}
