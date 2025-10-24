import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

void main() {
  runApp(MyApp());
}

// Clase para comunicación con el ecualizador nativo
class EqualizerChannel {
  static const platform =
      MethodChannel('com.example.reproductor_mp3/equalizer');

  static Future<int?> getAudioSessionId() async {
    try {
      final sessionId = await platform.invokeMethod('getAudioSessionId');
      return sessionId as int?;
    } catch (e) {
      print('Error al obtener audioSessionId: $e');
      return null;
    }
  }

  static Future<void> initializeEqualizer(int audioSessionId) async {
    try {
      await platform.invokeMethod('initializeEqualizer', {
        'audioSessionId': audioSessionId,
      });
      print('Ecualizador inicializado con sessionId: $audioSessionId');
    } catch (e) {
      print('Error al inicializar ecualizador: $e');
    }
  }

  static Future<void> setEqualizerEnabled(bool enabled) async {
    try {
      await platform.invokeMethod('setEqualizerEnabled', {
        'enabled': enabled,
      });
      print('Ecualizador ${enabled ? "activado" : "desactivado"}');
    } catch (e) {
      print('Error al cambiar estado del ecualizador: $e');
    }
  }

  static Future<void> setBandLevel(int bandIndex, double level) async {
    try {
      await platform.invokeMethod('setBandLevel', {
        'bandIndex': bandIndex,
        'level': level,
      });
    } catch (e) {
      print('Error al establecer nivel de banda: $e');
    }
  }

  static Future<void> resetBands() async {
    try {
      await platform.invokeMethod('resetBands');
      print('Bandas reseteadas');
    } catch (e) {
      print('Error al resetear bandas: $e');
    }
  }

  static Future<void> applyPreset(List<double> values) async {
    try {
      await platform.invokeMethod('applyPreset', {
        'values': values,
      });
      print('Preajuste aplicado: $values');
    } catch (e) {
      print('Error al aplicar preajuste: $e');
    }
  }

  static Future<Map<dynamic, dynamic>?> getEqualizerInfo() async {
    try {
      final info = await platform.invokeMethod('getEqualizerInfo');
      return info;
    } catch (e) {
      print('Error al obtener info del ecualizador: $e');
      return null;
    }
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reproductor MP3',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: AudioPlayerScreen(),
    );
  }
}

class AudioPlayerScreen extends StatefulWidget {
  @override
  _AudioPlayerScreenState createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late AudioPlayer _audioPlayer;
  List<String> _playlist = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isRandom = false;
  bool _fadeEnabled = false;
  bool _isMuted = false;
  double _lastVolume = 1.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    // Configurar el contexto de audio para Android
    if (Platform.isAndroid) {
      _audioPlayer.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );

      // Inicializar el ecualizador inmediatamente con sessionId=0 (global)
      _initializeEqualizer();
    }

    // Listener para cuando termina una canción
    _audioPlayer.onPlayerComplete.listen((event) {
      _playNextWithFade();
    });

    // Listener para la duración
    _audioPlayer.onDurationChanged.listen((Duration d) {
      setState(() => _duration = d);
    });

    // Listener para la posición
    _audioPlayer.onPositionChanged.listen((Duration p) {
      setState(() => _position = p);
    });

    _loadMusicFromDevice();
  }

  Future<void> _initializeEqualizer() async {
    try {
      // Inicializar con sessionId=0 para afectar toda la salida de audio
      await EqualizerChannel.initializeEqualizer(0);

      // Obtener y mostrar info del ecualizador
      final info = await EqualizerChannel.getEqualizerInfo();
      print('Info del ecualizador: $info');

      // ACTIVAR el ecualizador inmediatamente
      await EqualizerChannel.setEqualizerEnabled(true);
      print('Ecualizador activado y listo');
    } catch (e) {
      print('Error al inicializar ecualizador: $e');
    }
  }

  Future<void> _loadMusicFromDevice() async {
    // Solicitar permisos de almacenamiento según versión de Android
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (sdkInt >= 30) {
        // Android 11 o superior
        if (await Permission.manageExternalStorage.isGranted == false) {
          var status = await Permission.manageExternalStorage.request();
          if (!status.isGranted) {
            await openAppSettings();
            setState(() {
              _playlist = [];
            });
            return;
          }
        }
      } else {
        // Android 10 o menor
        if (await Permission.storage.isGranted == false) {
          var status = await Permission.storage.request();
          if (!status.isGranted) {
            await openAppSettings();
            setState(() {
              _playlist = [];
            });
            return;
          }
        }
      }
    }
    // Ruta absoluta para la carpeta Music/Cristiana
    final musicDir = Directory('/storage/emulated/0/Music/Cristiana');
    if (await musicDir.exists()) {
      final files = musicDir
          .listSync()
          .where((f) => f.path.endsWith('.mp3'))
          .map((f) => f.path)
          .toList();
      print('Archivos encontrados en /storage/emulated/0/Music/Cristiana:');
      for (var f in files) {
        print(f);
      }
      setState(() {
        _playlist = files;
      });
    } else {
      print('La carpeta /storage/emulated/0/Music/Cristiana no existe');
      setState(() {
        _playlist = [];
      });
    }
  }

  Future<void> _playAudio() async {
    try {
      if (_playlist.isEmpty) return;

      await _audioPlayer.play(DeviceFileSource(_playlist[_currentIndex]));
      setState(() => _isPlaying = true);
    } catch (e) {
      print('Error al reproducir el audio: $e');
    }
  }

  Future<void> _stopAudio() async {
    try {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
    } catch (e) {
      print('Error al detener el audio: $e');
    }
  }

  Future<void> _playNextWithFade() async {
    if (_playlist.isEmpty) return;
    if (_fadeEnabled) {
      // Fade-out
      for (double v = 1.0; v > 0.0; v -= 0.1) {
        await _audioPlayer.setVolume(v);
        await Future.delayed(Duration(milliseconds: 50));
      }
    }
    int nextIndex;
    if (_isRandom) {
      final random = List<int>.generate(_playlist.length, (i) => i)
        ..remove(_currentIndex);
      if (random.isEmpty) {
        setState(() => _isPlaying = false);
        return;
      }
      random.shuffle();
      nextIndex = random.first;
    } else {
      if (_currentIndex < _playlist.length - 1) {
        nextIndex = _currentIndex + 1;
      } else {
        setState(() => _isPlaying = false);
        return;
      }
    }
    setState(() => _currentIndex = nextIndex);

    if (_fadeEnabled) {
      // Fade-in
      await _audioPlayer.setVolume(0.0);
      await _audioPlayer.play(DeviceFileSource(_playlist[_currentIndex]));
      for (double v = 0.0; v <= 1.0; v += 0.1) {
        await _audioPlayer.setVolume(v);
        await Future.delayed(Duration(milliseconds: 50));
      }
    } else {
      await _audioPlayer.play(DeviceFileSource(_playlist[_currentIndex]));
    }
    setState(() => _isPlaying = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.blue[900],
        title: Text('Reproductor MP3',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        elevation: 0,
      ),
      body: _playlist.isEmpty
          ? Center(
              child: Text('No se encontraron canciones en Music/Cristiana',
                  style: TextStyle(color: Colors.white70)))
          : Column(
              children: [
                // Panel superior: información de la canción
                Container(
                  color: Colors.blueGrey[900],
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.music_note, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _playlist.isNotEmpty
                              ? _playlist[_currentIndex].split('/').last
                              : 'N/A',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Barra de progreso
                LinearProgressIndicator(
                  value: (_duration.inMilliseconds > 0)
                      ? _position.inMilliseconds / _duration.inMilliseconds
                      : 0.0,
                  backgroundColor: Colors.blueGrey[800],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  minHeight: 6,
                ),
                // Panel de controles
                Container(
                  color: Colors.blueGrey[900],
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Column(
                    children: [
                      Column(
                        children: [
                          // Fila de controles principales
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Botón Anterior - Tamaño: 24px
                              IconButton(
                                icon: Icon(Icons.skip_previous,
                                    color: Colors.white),
                                iconSize: 24,
                                padding: EdgeInsets.all(2),
                                constraints: BoxConstraints(),
                                onPressed: _currentIndex > 0
                                    ? () {
                                        setState(() {
                                          _currentIndex--;
                                        });
                                        _playAudio();
                                      }
                                    : null,
                              ),
                              SizedBox(width: 2),
                              // Botón Play/Pausa - Tamaño: 38px
                              IconButton(
                                icon: Icon(
                                    _isPlaying
                                        ? Icons.pause_circle
                                        : Icons.play_circle,
                                    color: Colors.white),
                                iconSize: 38,
                                padding: EdgeInsets.all(2),
                                constraints: BoxConstraints(),
                                onPressed: _playlist.isEmpty
                                    ? null
                                    : () async {
                                        if (_isPlaying) {
                                          await _audioPlayer.pause();
                                          setState(() => _isPlaying = false);
                                        } else {
                                          await _audioPlayer.resume();
                                          setState(() => _isPlaying = true);
                                        }
                                      },
                              ),
                              SizedBox(width: 2),
                              // Botón Stop - Tamaño: 30px
                              IconButton(
                                icon: Icon(Icons.stop_circle,
                                    color: Colors.white),
                                iconSize: 30,
                                padding: EdgeInsets.all(2),
                                constraints: BoxConstraints(),
                                onPressed: _isPlaying ? _stopAudio : null,
                              ),
                              SizedBox(width: 2),
                              // Botón Siguiente - Tamaño: 24px
                              IconButton(
                                icon:
                                    Icon(Icons.skip_next, color: Colors.white),
                                iconSize: 24,
                                padding: EdgeInsets.all(2),
                                constraints: BoxConstraints(),
                                onPressed: _playlist.length > 1
                                    ? () async {
                                        if (_isRandom) {
                                          final random = List<int>.generate(
                                              _playlist.length, (i) => i)
                                            ..remove(_currentIndex);
                                          random.shuffle();
                                          setState(() {
                                            _currentIndex = random.first;
                                          });
                                          await _audioPlayer.play(
                                              DeviceFileSource(
                                                  _playlist[_currentIndex]));
                                          setState(() => _isPlaying = true);
                                        } else if (_currentIndex <
                                            _playlist.length - 1) {
                                          setState(() {
                                            _currentIndex++;
                                          });
                                          _playAudio();
                                        }
                                      }
                                    : null,
                              ),
                              SizedBox(width: 2),
                              // Botón Mute - Tamaño: 24px
                              IconButton(
                                icon: Icon(
                                  _isMuted ? Icons.volume_off : Icons.volume_up,
                                  color: _isMuted
                                      ? Colors.redAccent
                                      : Colors.white,
                                ),
                                iconSize: 24,
                                padding: EdgeInsets.all(2),
                                constraints: BoxConstraints(),
                                onPressed: () {
                                  setState(() {
                                    if (_isMuted) {
                                      _audioPlayer.setVolume(_lastVolume);
                                      _isMuted = false;
                                    } else {
                                      _lastVolume = 1.0;
                                      _audioPlayer.setVolume(0.0);
                                      _isMuted = true;
                                    }
                                  });
                                },
                              ),
                              SizedBox(width: 2),
                              // Slider Volumen - Ancho: 50px
                              Container(
                                width: 50,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2.0,
                                    thumbShape: RoundSliderThumbShape(
                                        enabledThumbRadius: 4.0),
                                    overlayShape: RoundSliderOverlayShape(
                                        overlayRadius: 8.0),
                                  ),
                                  child: Slider(
                                    value: 1.0,
                                    onChanged: (value) {
                                      setState(() {
                                        _audioPlayer.setVolume(value);
                                        if (value == 0.0) {
                                          _isMuted = true;
                                        } else {
                                          _isMuted = false;
                                          _lastVolume = value;
                                        }
                                      });
                                    },
                                    min: 0.0,
                                    max: 1.0,
                                    activeColor: Colors.blueAccent,
                                    inactiveColor: Colors.blueGrey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      // Fila de botones secundarios
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Botón Secuencial
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: !_isRandom
                                  ? Colors.blueAccent
                                  : Colors.blueGrey[700],
                              padding: EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                            ),
                            icon: Icon(Icons.format_list_numbered,
                                color: Colors.white, size: 16),
                            label: Text('Secuencial',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 11)),
                            onPressed: () {
                              setState(() {
                                _isRandom = false;
                              });
                            },
                          ),
                          SizedBox(width: 4),
                          // Botón Aleatorio
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isRandom
                                  ? Colors.blueAccent
                                  : Colors.blueGrey[700],
                              padding: EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                            ),
                            icon: Icon(Icons.shuffle,
                                color: Colors.white, size: 16),
                            label: Text('Aleatorio',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 11)),
                            onPressed: () {
                              setState(() {
                                _isRandom = true;
                              });
                            },
                          ),
                          SizedBox(width: 8),
                          // Botón Fade
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _fadeEnabled
                                  ? Colors.blueAccent
                                  : Colors.blueGrey[700],
                            ),
                            icon: Icon(Icons.blur_on, color: Colors.white),
                            label: Text('Fade',
                                style: TextStyle(color: Colors.white)),
                            onPressed: () {
                              setState(() {
                                _fadeEnabled = !_fadeEnabled;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Ecualizador funcional de 7 bandas tipo Winamp
                SizedBox(height: 4),
                WinampEqualizer(
                  onBandValuesChanged: (values) {
                    // Aquí puedes guardar los valores del ecualizador
                    // y aplicarlos al audio cuando sea posible
                    print('Valores del ecualizador: $values');
                  },
                ),
                SizedBox(height: 4),
                // Lista de reproducción
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    'Lista de reproducción',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
                Expanded(
                  child: ReorderableListView(
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _playlist.removeAt(oldIndex);
                        _playlist.insert(newIndex, item);
                        if (_currentIndex == oldIndex) {
                          _currentIndex = newIndex;
                        } else if (_currentIndex > oldIndex &&
                            _currentIndex <= newIndex) {
                          _currentIndex--;
                        } else if (_currentIndex < oldIndex &&
                            _currentIndex >= newIndex) {
                          _currentIndex++;
                        }
                      });
                    },
                    children: [
                      for (int index = 0; index < _playlist.length; index++)
                        GestureDetector(
                          key: ValueKey(_playlist[index]),
                          onDoubleTap: () async {
                            setState(() {
                              _currentIndex = index;
                            });
                            await _playAudio();
                          },
                          child: ListTile(
                            leading: Icon(
                              index == _currentIndex
                                  ? Icons.play_arrow
                                  : Icons.music_note,
                              color: index == _currentIndex
                                  ? Colors.blueAccent
                                  : Colors.white70,
                            ),
                            title: Text(_playlist[index].split('/').last,
                                style: TextStyle(color: Colors.white)),
                            selected: index == _currentIndex,
                            selectedTileColor: Colors.blueGrey[700],
                          ),
                        ),
                    ],
                  ),
                ),
                // Espacio para banner de publicidad
                Container(
                  height: 60,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: Text('Espacio para publicidad',
                      style: TextStyle(color: Colors.black54)),
                ),
              ],
            ),
    );
  }
}

class TurntableWidget extends StatefulWidget {
  final bool isPlaying;
  final String label;
  const TurntableWidget(
      {Key? key, required this.isPlaying, required this.label})
      : super(key: key);

  @override
  State<TurntableWidget> createState() => _TurntableWidgetState();
}

class _TurntableWidgetState extends State<TurntableWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 4),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(TurntableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.rotate(
                angle: _controller.value * 2 * 3.1416,
                child: child,
              );
            },
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[300],
                border: Border.all(color: Colors.black, width: 4),
              ),
              child: Center(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(widget.label, style: TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// Widget del Ecualizador tipo Winamp
class WinampEqualizer extends StatefulWidget {
  final Function(List<double>)? onBandValuesChanged;

  const WinampEqualizer({Key? key, this.onBandValuesChanged}) : super(key: key);

  @override
  _WinampEqualizerState createState() => _WinampEqualizerState();
}

class _WinampEqualizerState extends State<WinampEqualizer> {
  List<double> _bandValues = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
  bool _isEnabled =
      true; // Estado del ecualizador (ON/OFF) - Activado por defecto

  // Frecuencias para las 7 bandas (típicas en ecualizadores)
  final List<String> _frequencies = [
    '60Hz',
    '150Hz',
    '400Hz',
    '1kHz',
    '2.4kHz',
    '6kHz',
    '15kHz'
  ];

  void _onBandValueChanged(int bandIndex, double value) {
    setState(() {
      _bandValues[bandIndex] = value;
    });

    // Enviar valor al ecualizador nativo si está habilitado
    if (_isEnabled && Platform.isAndroid) {
      EqualizerChannel.setBandLevel(bandIndex, value);
    }

    // Notificar cambios al padre si se proporciona callback
    if (widget.onBandValuesChanged != null) {
      widget.onBandValuesChanged!(_bandValues);
    }
  }

  void _resetEqualizer() {
    for (int i = 0; i < 7; i++) {
      _onBandValueChanged(i, 0.0);
    }

    // Resetear en el ecualizador nativo
    if (Platform.isAndroid) {
      EqualizerChannel.resetBands();
    }
  }

  void _applyPreset(List<double> values) {
    for (int i = 0; i < 7; i++) {
      _onBandValueChanged(i, values[i]);
    }

    // Aplicar preajuste en el ecualizador nativo si está habilitado
    if (_isEnabled && Platform.isAndroid) {
      EqualizerChannel.applyPreset(values);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header del ecualizador
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ECUALIZADOR - 7 BANDAS',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Row(
                children: [
                  // Botón ON/OFF
                  Container(
                    decoration: BoxDecoration(
                      color: _isEnabled ? Colors.green[700] : Colors.red[700],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: IconButton(
                      iconSize: 18,
                      padding: EdgeInsets.all(4),
                      constraints: BoxConstraints(),
                      icon: Icon(
                        _isEnabled ? Icons.power_settings_new : Icons.power_off,
                        color: Colors.white,
                      ),
                      onPressed: () async {
                        setState(() {
                          _isEnabled = !_isEnabled;
                        });

                        // Activar/desactivar en el ecualizador nativo
                        if (Platform.isAndroid) {
                          if (_isEnabled) {
                            // Re-inicializar antes de activar para asegurar que esté listo
                            await EqualizerChannel.initializeEqualizer(0);
                          }
                          await EqualizerChannel.setEqualizerEnabled(
                              _isEnabled);
                        }

                        // Notificar cambio de estado
                        if (widget.onBandValuesChanged != null) {
                          widget.onBandValuesChanged!(
                              _isEnabled ? _bandValues : List.filled(7, 0.0));
                        }
                      },
                      tooltip: _isEnabled
                          ? 'Apagar ecualizador'
                          : 'Encender ecualizador',
                    ),
                  ),
                  SizedBox(width: 4),
                  // Botón Reset
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.all(4),
                    constraints: BoxConstraints(),
                    icon: Icon(Icons.refresh, color: Colors.white),
                    onPressed: _resetEqualizer,
                    tooltip: 'Resetear ecualizador',
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: 8),

          // Sliders del ecualizador
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (index) => _buildBandSlider(index)),
          ),

          SizedBox(height: 6),

          // Preajustes rápidos
          _buildPresetButtons(),
        ],
      ),
    );
  }

  Widget _buildBandSlider(int bandIndex) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Valor numérico
        Container(
          width: 32,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Text(
              '${_bandValues[bandIndex].toStringAsFixed(1)}dB',
              style: TextStyle(
                color: Colors.greenAccent,
                fontSize: 7,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        SizedBox(height: 3),

        // Slider vertical
        Container(
          width: 32,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(14),
          ),
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: _bandValues[bandIndex],
              min: -12.0,
              max: 12.0,
              divisions: 48,
              onChanged: _isEnabled
                  ? (value) => _onBandValueChanged(bandIndex, value)
                  : null,
              activeColor: _isEnabled
                  ? _getSliderColor(_bandValues[bandIndex])
                  : Colors.grey,
              inactiveColor: Colors.grey[600],
            ),
          ),
        ),

        SizedBox(height: 4),

        // Etiqueta de frecuencia
        Text(
          _frequencies[bandIndex],
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  Widget _buildPresetButtons() {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        _buildPresetButton('Flat', [0, 0, 0, 0, 0, 0, 0]),
        _buildPresetButton('Rock', [4, 3, 0, 2, 3, 4, 2]),
        _buildPresetButton('Pop', [2, 1, 0, 2, 3, 2, 1]),
        _buildPresetButton('Jazz', [3, 2, 0, 1, 2, 3, 4]),
        _buildPresetButton('Classic', [4, 2, 0, -1, 0, 2, 3]),
      ],
    );
  }

  Widget _buildPresetButton(String name, List<double> values) {
    return ElevatedButton(
      onPressed: _isEnabled ? () => _applyPreset(values) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: _isEnabled ? Colors.grey[800] : Colors.grey[900],
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        minimumSize: Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        name,
        style: TextStyle(
            fontSize: 10, color: _isEnabled ? Colors.white : Colors.grey[600]),
      ),
    );
  }

  Color _getSliderColor(double value) {
    if (value > 0) {
      return Colors.greenAccent;
    } else if (value < 0) {
      return Colors.redAccent;
    } else {
      return Colors.blueAccent;
    }
  }
}
