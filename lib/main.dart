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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_playlist.isEmpty)
              Text('No se encontraron canciones en Music/Cristiana'),
            if (_playlist.isNotEmpty)
              Text('Canción actual: ' +
                  _playlist[_currentIndex].split('/').last),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isPlaying || _playlist.isEmpty ? null : _playAudio,
              child: Text('Reproducir canción'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isPlaying ? _stopAudio : null,
              child: Text('Detener canción'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _currentIndex < _playlist.length - 1 && _isPlaying
                  ? _playNextWithFade
                  : null,
              child: Text('Siguiente canción'),
            ),
          ],
        ),
      ),
    );
  }
}
