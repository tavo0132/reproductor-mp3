import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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
    // Solicitar permisos de almacenamiento
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isGranted == false) {
        var status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          // Si el permiso no se concede, abrir la configuración
          await openAppSettings();
          setState(() {
            _playlist = [];
          });
          return;
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
      setState(() {
        _playlist = files;
      });
    } else {
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
    // Aquí se implementará el fade-out y fade-in en el siguiente paso
    if (_currentIndex < _playlist.length - 1) {
      setState(() => _currentIndex++);
      await _playAudio();
    } else {
      setState(() => _isPlaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reproductor MP3'),
      ),
      body: _playlist.isEmpty
          ? Center(
              child: Text('No se encontraron canciones en Music/Cristiana'))
          : Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TurntableWidget(
                        isPlaying: _isPlaying, label: 'turntable_1'),
                    TurntableWidget(
                        isPlaying: _isPlaying, label: 'turntable_2'),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Lista de reproducción',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ReorderableListView(
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
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
                        ListTile(
                          key: ValueKey(_playlist[index]),
                          leading: Icon(
                            index == _currentIndex
                                ? Icons.play_arrow
                                : Icons.music_note,
                            color: index == _currentIndex ? Colors.blue : null,
                          ),
                          title: Text(_playlist[index].split('/').last),
                          selected: index == _currentIndex,
                          onTap: () async {
                            setState(() {
                              _currentIndex = index;
                            });
                            await _playAudio();
                          },
                        ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(
                      'Canción actual: ' +
                          (_playlist.isNotEmpty
                              ? _playlist[_currentIndex].split('/').last
                              : 'N/A'),
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    StreamBuilder<Duration?>(
                      stream: _audioPlayer.durationStream,
                      builder: (context, snapshot) {
                        final duration = snapshot.data ?? Duration.zero;
                        return Text(
                            'Duración: ${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}');
                      },
                    ),
                    StreamBuilder<Duration>(
                      stream: _audioPlayer.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? Duration.zero;
                        return Text(
                            'Progreso: ${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}');
                      },
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed:
                          _isPlaying || _playlist.isEmpty ? null : _playAudio,
                      child: Text('Reproducir'),
                    ),
                    SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: _isPlaying ? _stopAudio : null,
                      child: Text('Detener'),
                    ),
                    SizedBox(width: 20),
                    ElevatedButton(
                      onPressed:
                          _currentIndex < _playlist.length - 1 && _isPlaying
                              ? _playNextWithFade
                              : null,
                      child: Text('Siguiente'),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _currentIndex > 0
                          ? () {
                              setState(() {
                                _currentIndex--;
                              });
                              _playAudio();
                            }
                          : null,
                      child: Text('Anterior'),
                    ),
                    SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: _currentIndex < _playlist.length - 1
                          ? () {
                              setState(() {
                                _currentIndex++;
                              });
                              _playAudio();
                            }
                          : null,
                      child: Text('Siguiente'),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Volumen'),
                    Slider(
                      value: _audioPlayer.volume,
                      onChanged: (value) {
                        setState(() {
                          _audioPlayer.setVolume(value);
                        });
                      },
                      min: 0.0,
                      max: 1.0,
                    ),
                  ],
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
