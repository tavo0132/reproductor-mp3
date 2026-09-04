import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  const MyApp({Key? key}) : super(key: key);

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
  bool _reverbEnabled = false;
  bool _delayEnabled = false;
  double _reverbLevel = 0.5;
  double _delayLevel = 0.5;
  bool _isMuted = false;
  double _volume = 1.0;
  double _lastVolume = 1.0;
  double _fadeDurationSeconds = 0.5;
  bool _isTransitioning = false;
  String? _musicFolder;
  List<double> _equalizerValues = List.filled(7, 0.0);
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _loadPreferences();

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
      if (!mounted) return;
      setState(() => _position = p);
      if (_fadeEnabled &&
          !_isTransitioning &&
          _duration > Duration.zero &&
          _duration - p <= _fadeDuration &&
          p < _duration) {
        _playNextWithFade();
      }
    });
  }

  Duration get _fadeDuration =>
      Duration(milliseconds: (_fadeDurationSeconds * 1000).round());

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _fadeEnabled = preferences.getBool('fade_enabled') ?? false;
      _fadeDurationSeconds = preferences.getDouble('fade_duration') ?? 0.5;
      _reverbEnabled = preferences.getBool('reverb_enabled') ?? false;
      _delayEnabled = preferences.getBool('delay_enabled') ?? false;
      _reverbLevel = preferences.getDouble('reverb_level') ?? 0.5;
      _delayLevel = preferences.getDouble('delay_level') ?? 0.5;
      _musicFolder = preferences.getString('music_folder');
      final savedBands = preferences.getStringList('equalizer_bands');
      if (savedBands != null && savedBands.length == 7) {
        _equalizerValues = savedBands.map(double.parse).toList();
      }
    });
    if (_musicFolder != null) {
      await _loadMusicFromFolder(_musicFolder!);
    } else {
      await _loadMusicFromDevice();
    }
  }

  Future<void> _saveFadePreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('fade_enabled', _fadeEnabled);
    await preferences.setDouble('fade_duration', _fadeDurationSeconds);
  }

  Future<void> _saveEffectPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('reverb_enabled', _reverbEnabled);
    await preferences.setBool('delay_enabled', _delayEnabled);
    await preferences.setDouble('reverb_level', _reverbLevel);
    await preferences.setDouble('delay_level', _delayLevel);
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _seekTo(double value) async {
    if (_duration <= Duration.zero) return;
    final position = Duration(
      milliseconds: (value.clamp(0.0, 1.0) * _duration.inMilliseconds).round(),
    );
    await _audioPlayer.seek(position);
  }

  Future<void> _selectMusicFolder() async {
    final folder = await FilePicker.getDirectoryPath();
    if (folder == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('music_folder', folder);
    if (!mounted) return;
    setState(() => _musicFolder = folder);
    await _loadMusicFromFolder(folder);
    if (mounted) Navigator.of(context).pop();
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
      if (_equalizerValues.any((value) => value != 0.0)) {
        await EqualizerChannel.applyPreset(_equalizerValues);
      }
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
    final musicDir =
        Directory(_musicFolder ?? '/storage/emulated/0/Music/Cristiana');
    await _loadMusicFromFolder(musicDir.path);
  }

  Future<void> _loadMusicFromFolder(String folderPath) async {
    final musicDir = Directory(folderPath);
    if (await musicDir.exists()) {
      final files = musicDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.mp3'))
          .map((f) => f.path)
          .toList();
      if (!mounted) return;
      setState(() => _playlist = files);
    } else if (mounted) {
      setState(() => _playlist = []);
    }
  }

  Future<void> _playAudio() async {
    try {
      if (_playlist.isEmpty) return;

      await _audioPlayer.setVolume(_volume);
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
    if (_playlist.isEmpty || _isTransitioning) return;
    _isTransitioning = true;
    int nextIndex;
    if (_isRandom) {
      final random = List<int>.generate(_playlist.length, (i) => i)
        ..remove(_currentIndex);
      if (random.isEmpty) {
        setState(() => _isPlaying = false);
        _isTransitioning = false;
        return;
      }
      random.shuffle();
      nextIndex = random.first;
    } else {
      if (_currentIndex < _playlist.length - 1) {
        nextIndex = _currentIndex + 1;
      } else {
        setState(() => _isPlaying = false);
        _isTransitioning = false;
        return;
      }
    }
    final shouldFade = _fadeEnabled && _fadeDuration > Duration.zero;
    if (shouldFade) {
      await _fadeVolume(from: _volume, to: 0.0);
    }
    setState(() => _currentIndex = nextIndex);

    if (shouldFade) {
      await _audioPlayer.setVolume(0.0);
      await _audioPlayer.play(DeviceFileSource(_playlist[_currentIndex]));
      await _fadeVolume(from: 0.0, to: _volume);
    } else {
      await _audioPlayer.play(DeviceFileSource(_playlist[_currentIndex]));
    }
    if (mounted) setState(() => _isPlaying = true);
    _isTransitioning = false;
  }

  Future<void> _fadeVolume({required double from, required double to}) async {
    const steps = 10;
    final delay =
        Duration(milliseconds: (_fadeDuration.inMilliseconds / steps).round());
    for (var step = 1; step <= steps; step++) {
      final value = from + (to - from) * step / steps;
      await _audioPlayer.setVolume(value.clamp(0.0, 1.0));
      await Future.delayed(delay);
    }
  }

  void _updateEqualizer(List<double> values) {
    _equalizerValues = List<double>.from(values);
    SharedPreferences.getInstance().then((preferences) {
      preferences.setStringList(
        'equalizer_bands',
        _equalizerValues.map((value) => value.toString()).toList(),
      );
    });
  }

  Future<void> _showPlaybackSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Configuración de reproducción'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fundido cruzado'),
                value: _fadeEnabled,
                onChanged: (value) {
                  setDialogState(() => _fadeEnabled = value);
                  _saveFadePreferences();
                  setState(() {});
                },
              ),
              _buildEffectSetting(
                context: context,
                label: 'Reverb',
                enabled: _reverbEnabled,
                level: _reverbLevel,
                onEnabledChanged: (value) {
                  setDialogState(() => _reverbEnabled = value);
                  _saveEffectPreferences();
                  setState(() {});
                },
                onLevelChanged: (value) {
                  setDialogState(() => _reverbLevel = value);
                  _saveEffectPreferences();
                },
              ),
              _buildEffectSetting(
                context: context,
                label: 'Delay',
                enabled: _delayEnabled,
                level: _delayLevel,
                onEnabledChanged: (value) {
                  setDialogState(() => _delayEnabled = value);
                  _saveEffectPreferences();
                  setState(() {});
                },
                onLevelChanged: (value) {
                  setDialogState(() => _delayLevel = value);
                  _saveEffectPreferences();
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Duración'),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () {
                      setDialogState(() => _fadeDurationSeconds =
                          (_fadeDurationSeconds - 0.1).clamp(0.0, 30.0));
                      _saveFadePreferences();
                    },
                  ),
                  Text('${_fadeDurationSeconds.toStringAsFixed(1)} s'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      setDialogState(() => _fadeDurationSeconds =
                          (_fadeDurationSeconds + 0.1).clamp(0.0, 30.0));
                      _saveFadePreferences();
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectSetting({
    required BuildContext context,
    required String label,
    required bool enabled,
    required double level,
    required ValueChanged<bool> onEnabledChanged,
    required ValueChanged<double> onLevelChanged,
  }) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: enabled,
          onChanged: onEnabledChanged,
        ),
        Row(
          children: [
            Expanded(child: Text('Nivel: ${(level * 100).round()}%')),
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: () => onLevelChanged((level - 0.1).clamp(0.0, 1.0)),
            ),
            SizedBox(
              width: 90,
              child: Slider(
                value: level,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                onChanged: onLevelChanged,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => onLevelChanged((level + 0.1).clamp(0.0, 1.0)),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.blue[900],
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Abrir menú',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text('Reproductor MP3',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        elevation: 0,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text('Reproductor MP3',
                  style: TextStyle(color: Colors.white, fontSize: 20)),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Carpeta de música'),
              subtitle: Text(_musicFolder ?? 'No seleccionada'),
              onTap: _selectMusicFolder,
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Reproducción avanzada'),
              onTap: () {
                Navigator.of(context).pop();
                _showPlaybackSettings();
              },
            ),
          ],
        ),
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
                    ],
                  ),
                ),
                // Barra de progreso interactiva y tiempos de reproducción
                Row(
                  children: [
                    SizedBox(
                      width: 38,
                      child: Text(
                        _formatDuration(_position),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 5.0,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6.0,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12.0,
                          ),
                        ),
                        child: Slider(
                          value: _duration.inMilliseconds > 0
                              ? (_position.inMilliseconds /
                                      _duration.inMilliseconds)
                                  .clamp(0.0, 1.0)
                              : 0.0,
                          onChanged: _duration > Duration.zero
                              ? (value) {
                                  setState(() {
                                    _position = Duration(
                                      milliseconds:
                                          (value * _duration.inMilliseconds)
                                              .round(),
                                    );
                                  });
                                }
                              : null,
                          onChangeEnd: _seekTo,
                          activeColor: Colors.blueAccent,
                          inactiveColor: Colors.blueGrey[800],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 38,
                      child: Text(
                        _formatDuration(_duration),
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ),
                  ],
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
                                      _volume = _lastVolume;
                                      _isMuted = false;
                                    } else {
                                      _lastVolume = _volume;
                                      _audioPlayer.setVolume(0.0);
                                      _isMuted = true;
                                    }
                                  });
                                },
                              ),
                              SizedBox(width: 2),
                              // Slider Volumen - Ancho: 64px
                              Container(
                                width: 64,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3.0,
                                    thumbShape: RoundSliderThumbShape(
                                        enabledThumbRadius: 5.0),
                                    overlayShape: RoundSliderOverlayShape(
                                        overlayRadius: 10.0),
                                  ),
                                  child: Slider(
                                    value: _volume,
                                    onChanged: (value) {
                                      setState(() {
                                        _volume = value;
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
                      // Fila de efectos desplazable en pantallas estrechas
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
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
                                _saveFadePreferences();
                              },
                            ),
                            SizedBox(width: 4),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _reverbEnabled
                                    ? Colors.blueAccent
                                    : Colors.blueGrey[700],
                                padding: EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
                                minimumSize: Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: Icon(Icons.graphic_eq,
                                  color: Colors.white, size: 16),
                              label: Text('Reverb',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11)),
                              onPressed: () {
                                setState(
                                    () => _reverbEnabled = !_reverbEnabled);
                                _saveEffectPreferences();
                              },
                            ),
                            SizedBox(width: 4),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _delayEnabled
                                    ? Colors.blueAccent
                                    : Colors.blueGrey[700],
                                padding: EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
                                minimumSize: Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: Icon(Icons.timer,
                                  color: Colors.white, size: 16),
                              label: Text('Delay',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11)),
                              onPressed: () {
                                setState(() => _delayEnabled = !_delayEnabled);
                                _saveEffectPreferences();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Ecualizador funcional de 7 bandas tipo Winamp
                SizedBox(height: 4),
                WinampEqualizer(
                  onBandValuesChanged: (values) {
                    _updateEqualizer(values);
                  },
                  initialBandValues: _equalizerValues,
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
                    onReorderItem: (oldIndex, newIndex) {
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
  final List<double> initialBandValues;

  const WinampEqualizer({
    Key? key,
    this.onBandValuesChanged,
    this.initialBandValues = const [0, 0, 0, 0, 0, 0, 0],
  }) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    if (widget.initialBandValues.length == 7) {
      _bandValues = List<double>.from(widget.initialBandValues);
    }
  }

  @override
  void didUpdateWidget(WinampEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialBandValues != widget.initialBandValues &&
        widget.initialBandValues.length == 7) {
      setState(() {
        _bandValues = List<double>.from(widget.initialBandValues);
      });
    }
  }

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
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isEnabled ? Colors.green[700] : Colors.red[700],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        iconSize: 14,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 38,
                          height: 38,
                        ),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _isEnabled
                              ? Icons.power_settings_new
                              : Icons.power_off,
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
          height: 104,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(14),
          ),
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6.0,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6.0,
                ),
              ),
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
