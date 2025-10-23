import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

void main() {
  runApp(MyApp());
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

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _playNextWithFade();
      }
    });
    _loadMusicFromDevice();
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
      await _audioPlayer.setFilePath(_playlist[_currentIndex]);
      setState(() => _isPlaying = true);
      _audioPlayer.play();
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
      for (double v = _audioPlayer.volume; v > 0.0; v -= 0.1) {
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
    await _audioPlayer.setFilePath(_playlist[_currentIndex]);
    if (_fadeEnabled) {
      // Fade-in
      await _audioPlayer.setVolume(0.0);
      _audioPlayer.play();
      for (double v = 0.0; v <= 1.0; v += 0.1) {
        await _audioPlayer.setVolume(v);
        await Future.delayed(Duration(milliseconds: 50));
      }
    } else {
      _audioPlayer.play();
    }
    setState(() => _isPlaying = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.blue[900],
        title: Text('Reproductor MP3', style: TextStyle(color: Colors.white)),
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
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.music_note, color: Colors.white),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _playlist.isNotEmpty
                              ? _playlist[_currentIndex].split('/').last
                              : 'N/A',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      StreamBuilder<Duration?>(
                        stream: _audioPlayer.durationStream,
                        builder: (context, snapshot) {
                          final duration = snapshot.data ?? Duration.zero;
                          return Text(
                            '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                            style: TextStyle(color: Colors.white70),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // Barra de progreso
                StreamBuilder<Duration>(
                  stream: _audioPlayer.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    return LinearProgressIndicator(
                      value: (_audioPlayer.duration != null &&
                              _audioPlayer.duration!.inMilliseconds > 0)
                          ? position.inMilliseconds /
                              _audioPlayer.duration!.inMilliseconds
                          : 0.0,
                      backgroundColor: Colors.blueGrey[800],
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                      minHeight: 6,
                    );
                  },
                ),
                // Panel de controles
                Container(
                  color: Colors.blueGrey[900],
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Column(
                    children: [
                      Column(
                        children: [
                          // Fila de controles principales
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Botón Anterior - Tamaño: 32px
                              IconButton(
                                icon: Icon(Icons.skip_previous,
                                    color: Colors.white),
                                iconSize: 32,
                                onPressed: _currentIndex > 0
                                    ? () {
                                        setState(() {
                                          _currentIndex--;
                                        });
                                        _playAudio();
                                      }
                                    : null,
                              ),
                              // Separación uniforme entre botones principales (ajustar aquí)
                              SizedBox(
                                  width:
                                      12), // <-- Separación entre botones principales
                              // Botón Play/Pausa - Tamaño: 48px
                              IconButton(
                                icon: Icon(
                                    _isPlaying
                                        ? Icons.pause_circle
                                        : Icons.play_circle,
                                    color: Colors.white),
                                iconSize: 48,
                                onPressed: _playlist.isEmpty
                                    ? null
                                    : () {
                                        if (_isPlaying) {
                                          _audioPlayer.pause();
                                          setState(() => _isPlaying = false);
                                        } else {
                                          _audioPlayer.play();
                                          setState(() => _isPlaying = true);
                                        }
                                      },
                              ),
                              SizedBox(
                                  width:
                                      12), // <-- Separación entre botones principales
                              // Botón Stop - Tamaño: 40px
                              IconButton(
                                icon: Icon(Icons.stop_circle,
                                    color: Colors.white),
                                iconSize: 40,
                                onPressed: _isPlaying ? _stopAudio : null,
                              ),
                              SizedBox(
                                  width:
                                      12), // <-- Separación entre botones principales
                              // Botón Siguiente - Tamaño: 32px
                              IconButton(
                                icon:
                                    Icon(Icons.skip_next, color: Colors.white),
                                iconSize: 32,
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
                                          await _audioPlayer.setFilePath(
                                              _playlist[_currentIndex]);
                                          _audioPlayer.play();
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
                              SizedBox(
                                  width:
                                      12), // <-- Separación entre botones principales
                              // Botón Mute - Tamaño: 32px
                              IconButton(
                                icon: Icon(
                                  _isMuted ? Icons.volume_off : Icons.volume_up,
                                  color: _isMuted
                                      ? Colors.redAccent
                                      : Colors.white,
                                ),
                                iconSize: 32,
                                onPressed: () {
                                  setState(() {
                                    if (_isMuted) {
                                      _audioPlayer.setVolume(_lastVolume);
                                      _isMuted = false;
                                    } else {
                                      _lastVolume = _audioPlayer.volume;
                                      _audioPlayer.setVolume(0.0);
                                      _isMuted = true;
                                    }
                                  });
                                },
                              ),
                              SizedBox(
                                  width:
                                      12), // <-- Separación entre botones principales
                              // Slider Volumen - Ancho: 70px
                              Container(
                                width: 70,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3.0,
                                    thumbShape: RoundSliderThumbShape(
                                        enabledThumbRadius: 6.0),
                                    overlayShape: RoundSliderOverlayShape(
                                        overlayRadius: 12.0),
                                  ),
                                  child: Slider(
                                    value: _audioPlayer.volume,
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
                      SizedBox(height: 8),
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
                            ),
                            icon: Icon(Icons.format_list_numbered,
                                color: Colors.white),
                            label: Text('Secuencial',
                                style: TextStyle(color: Colors.white)),
                            onPressed: () {
                              setState(() {
                                _isRandom = false;
                              });
                            },
                          ),
                          SizedBox(width: 8),
                          // Botón Aleatorio
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isRandom
                                  ? Colors.blueAccent
                                  : Colors.blueGrey[700],
                            ),
                            icon: Icon(Icons.shuffle, color: Colors.white),
                            label: Text('Aleatorio',
                                style: TextStyle(color: Colors.white)),
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
                // Ecualizador decorativo (no funcional por ahora)
                Container(
                  color: Colors.blueGrey[800],
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(10, (i) {
                      return Container(
                        width: 10,
                        height: 40 + (i % 2 == 0 ? 10 : 0),
                        decoration: BoxDecoration(
                          color: Colors.blue[900],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),
                // Lista de reproducción
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Lista de reproducción',
                    style: TextStyle(
                        fontSize: 18,
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
