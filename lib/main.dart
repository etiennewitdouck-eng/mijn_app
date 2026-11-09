import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';

late MyAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  List<String> playlist = [];
  Map<String, String> localImagePaths = {};
  int currentIndex = 0;

  MyAudioHandler() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    
    // Automatisch naar het volgende liedje gaan als de huidige afgelopen is
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        skipToNext();
      }
    });
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
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
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

  // Methode om een specifiek liedje direct te laden en te spelen met playlist-beheer
  Future<void> playSongAtIndex(int index, List<String> newPlaylist, Map<String, String> newImages) async {
    playlist = newPlaylist;
    localImagePaths = newImages;
    currentIndex = index;

    final songPath = playlist[currentIndex];
    final baseName = songPath.split('/').last.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
    final localImagePath = localImagePaths[songPath];

    Uri? artUri;
    if (localImagePath != null) {
      final imageFile = File(localImagePath);
      if (await imageFile.exists()) {
        artUri = Uri.parse('file://${imageFile.path}');
      }
    }

    mediaItem.add(
      MediaItem(
        id: songPath,
        album: 'Mijn MP3 Map',
        title: baseName,
        artist: 'Onbekende Artiest',
        artUri: artUri,
      ),
    );

    await _player.setAudioSource(AudioSource.asset(songPath));
    await _player.play();
  }

  @override
  Future<void> skipToNext() async {
    if (playlist.isEmpty) return;
    currentIndex = (currentIndex + 1) % playlist.length; // Ga naar volgende, cirkel terug naar begin als je bij de laatste bent
    await playSongAtIndex(currentIndex, playlist, localImagePaths);
  }

  @override
  Future<void> skipToPrevious() async {
    if (playlist.isEmpty) return;
    currentIndex = (currentIndex - 1 + playlist.length) % playlist.length; // Ga naar vorige, cirkel door naar achteren als je bij de eerste bent
    await playSongAtIndex(currentIndex, playlist, localImagePaths);
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
  MediaItem? _currentMediaItem;

  @override
  void initState() {
    super.initState();
    _loadSongsFromAssets();

    audioHandler.playbackState.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
    });

    audioHandler.mediaItem.listen((item) {
      setState(() {
        _currentMediaItem = item;
        if (item != null) {
          // Zoek de index op basis van het id (songPath)
          _currentIndex = _playlist.indexOf(item.id);
        }
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

  @override
  Widget build(BuildContext context) {
    final currentImagePath = _currentIndex != null && _currentIndex! < _playlist.length
        ? _localImagePaths[_playlist[_currentIndex!]]
        : null;

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
                    final songPath = _playlist[index];
                    final fileName = songPath.split('/').last;
                    final isSelected = _currentIndex == index;
                    final imagePath = _localImagePaths[songPath];

                    return ListTile(
                      leading: imagePath != null && File(imagePath).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(File(imagePath), width: 45, height: 45, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.music_note),
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
                      onTap: () {
                        audioHandler.playSongAtIndex(index, _playlist, _localImagePaths);
                      },
                    );
                  },
                ),
      
      // UITGEBREIDE SPELERBALK ONDERAAN MET PREVIOUS, PLAY/PAUSE EN NEXT
      bottomNavigationBar: _currentIndex != null
          ? Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Albumhoes
                  if (currentImagePath != null && File(currentImagePath).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(currentImagePath),
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: 50,
                      height: 50,
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.white),
                    ),
                  const SizedBox(width: 10),
                  
                  // Titel
                  Expanded(
                    child: Text(
                      _currentMediaItem?.title ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Vorige knop
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    iconSize: 32,
                    color: Colors.white,
                    onPressed: () => audioHandler.skipToPrevious(),
                  ),

                  // Play / Pause knop
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                    iconSize: 42,
                    color: Colors.green,
                    onPressed: () async {
                      if (_isPlaying) {
                        await audioHandler.pause();
                      } else {
                        await audioHandler.play();
                      }
                    },
                  ),

                  // Volgende knop
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    iconSize: 32,
                    color: Colors.white,
                    onPressed: () => audioHandler.skipToNext(),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
