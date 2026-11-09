import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';

// Globale AudioHandler zodat de app en CarPlay ermee kunnen communiceren
late AudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialiseer AudioService zodat CarPlay en Lock Screen de metadata oppikken
  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.mijnapp.mp3.channel.audio',
      androidNotificationChannelName: 'Mijn MP3 Speler',
      androidNotificationOngoing: true,
    ),
  );

  runApp(const MyApp());
}

/// Specifieke AudioHandler om liedjes en metadata (zoals artUri) door te sturen naar iOS/CarPlay
class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  MyAudioHandler() {
    // Koppel de spelerstatus aan audio_service
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
      },
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  // Methode om audio én de MediaItem (met artUri voor CarPlay) in te stellen
  Future<void> loadSongWithMediaItem(AudioSource source, MediaItem item) async {
    mediaItem.add(item); // Dit stuurt de metadata en poster naar CarPlay / iOS!
    await _player.setAudioSource(source);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mijn MP3 Speler',
      theme: ThemeData.dark(),
      home: const MusicPlayerPage(),
    );
  }
}

class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key});

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  List<String> _playlist = [];
  final Map<String, String> _localImagePaths = {};
  bool _isLoading = true;
  int? _currentIndex;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadSongsFromAssets();

    // Luister naar speelstatus om de UI te updaten
    audioHandler.playbackState.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
    });
  }

  Future<void> _loadSongsFromAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets();

      final mp3Files = assets
          .where((String key) => key.startsWith('assets/mijnliedjes/') && key.toLowerCase().endsWith('.mp3'))
          .toList();

      final appDocDir = await getApplicationDocumentsDirectory();
      
      for (var songPath in mp3Files) {
        final baseName = songPath.split('/').last.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
        final imageAssetPath = 'assets/mijnliedjes/$baseName.jpg';

        try {
          final byteData = await rootBundle.load(imageAssetPath);
          final file = File('${appDocDir.path}/$baseName.jpg');
          await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
          
          _localImagePaths[songPath] = file.path;
        } catch (e) {
          debugPrint("Geen afbeelding gevonden voor $baseName ($e)");
        }
      }

      setState(() {
        _playlist = mp3Files;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Fout bij laden van assets: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _playSong(int index) async {
    try {
      final songPath = _playlist[index];
      final baseName = songPath.split('/').last.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
      
      final localImagePath = _localImagePaths[songPath];
      
      Uri? artUri;
      if (localImagePath != null) {
        final imageFile = File(localImagePath);
        if (await imageFile.exists()) {
          artUri = Uri.parse('file://$localImagePath');
        }
      }

      // Visuele melding op je iPhone-scherm zodat je direct ziet wat er gebeurt
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Speelt: $baseName | Poster Uri: ${artUri != null ? "Gekoppeld" : "Ontbreekt"}'),
            duration: const Duration(seconds: 4),
            backgroundColor: artUri != null ? Colors.green[800] : Colors.red[800],
          ),
        );
      }

      // Geef de audiobron en de MediaItem mee aan onze AudioHandler
      await (audioHandler as MyAudioHandler).loadSongWithMediaItem(
        AudioSource.asset(songPath),
        MediaItem(
          id: songPath,
          album: 'Mijn MP3 Map',
          title: baseName,
          artist: 'Onbekende Artiest',
          artUri: artUri,
        ),
      );

      await audioHandler.play();
      setState(() {
        _currentIndex = index;
      });
    } catch (e) {
      debugPrint("Fout bij afspelen: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout bij afspelen: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mijn MP3 Auto Speler'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlist.isEmpty
              ? const Center(child: Text('Geen liedjes gevonden in assets/mijnliedjes/'))
              : ListView.builder(
                  itemCount: _playlist.length,
                  itemBuilder: (context, index) {
                    final fileName = _playlist[index].split('/').last;
                    final isSelected = _currentIndex == index;

                    return ListTile(
                      leading: Icon(
                        isSelected && _isPlaying ? Icons.pause_circle : Icons.music_note,
                        color: isSelected ? Colors.green : Colors.white,
                      ),
                      title: Text(
                        fileName,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.green : Colors.white,
                        ),
                      ),
                      trailing: isSelected && _isPlaying
                          ? const Icon(Icons.volume_up, color: Colors.green)
                          : null,
                      onTap: () => _playSong(index),
                    );
                  },
                ),
    );
  }
}
