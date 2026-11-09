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
    
    // Luister naar index-veranderingen vanuit de playlist van just_audio om de UI te synchroniseren
    _player.currentIndexStream.listen((index) {
      if (index != null && index < playlist.length) {
        currentIndex = index;
        _updateMediaItemForCurrentIndex();
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

  // Initialiseer de volledige playlist in just_audio (zodat automatisch doorspelen werkt)
  Future<void> setPlaylist(List<String> newPlaylist, Map<String, String> newImages, int initialIndex) async {
    playlist = newPlaylist;
    localImagePaths = newImages;
    currentIndex = initialIndex;

    // Maak een ConcatenatingAudioSource aan zodat de speler automatisch doorgaat naar het volgende lied
    final sources = playlist.map((songPath) {
      final baseName = songPath.split('/').last.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
      final localImagePath = localImagePaths[songPath];

      Uri? artUri;
      if (localImagePath != null) {
        final imageFile = File(localImagePath);
        if (imageFile.existsSync()) {
          artUri = Uri.parse('file://${imageFile.path}');
        }
      }

      return AudioSource.asset(
        songPath,
        tag: MediaItem(
          id: songPath,
          album: 'Mijn MP3 Map',
          title: baseName,
          artist: 'Onbekende Artiest',
          artUri: artUri,
        ),
      );
    }).toList();

    await _player.setAudioSource(ConcatenatingAudioSource(children: sources), initialIndex: currentIndex);
    _updateMediaItemForCurrentIndex();
    await _player.play();
  }

  void _updateMediaItemForCurrentIndex() {
    if (playlist.isEmpty || currentIndex >= playlist.length) return;
    final songPath = playlist[currentIndex];
    final baseName = songPath.split('/').last.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
    final localImagePath = localImagePaths[songPath];

    Uri? artUri;
    if (localImagePath != null) {
      final imageFile = File(localImagePath);
      if (imageFile.existsSync()) {
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
  }

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      await _player.seek(Duration.zero, index: 0); // Terug naar het begin van de lijst
    }
    await _player.play();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero, index: playlist.length - 1); // Naar het laatste lied
    }
    await _player.play();
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

  void _openNowPlayingModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateModal) {
            // Zorg dat de modal ook update als de mediaItem wijzigt
            audioHandler.mediaItem.listen((_) {
              if (mounted) setStateModal(() {});
            });

            final currentImagePath = _currentIndex != null && _currentIndex! < _playlist.length
                ? _localImagePaths[_playlist[_currentIndex!]]
                : null;

            return FractionallySizedBox(
              heightFactor: 0.85,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(),
                    if (currentImagePath != null && File(currentImagePath).existsSync())
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          File(currentImagePath),
                          width: 280,
                          height: 280,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.music_note, size: 80, color: Colors.white),
                      ),
                    const SizedBox(height: 32),
                    Text(
                      _currentMediaItem?.title ?? '',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Onbekende Artiest',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous),
                          iconSize: 48,
                          color: Colors.white,
                          onPressed: () => audioHandler.skipToPrevious(),
                        ),
                        const SizedBox(width: 24),
                        IconButton(
                          icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                          iconSize: 72,
                          color: Colors.green,
                          onPressed: () async {
                            if (_isPlaying) {
                              await audioHandler.pause();
                            } else {
                              await audioHandler.play();
                            }
                            setStateModal(() {});
                          },
                        ),
                        const SizedBox(width: 24),
                        IconButton(
                          icon: const Icon(Icons.skip_next),
                          iconSize: 48,
                          color: Colors.white,
                          onPressed: () => audioHandler.skipToNext(),
                        ),
                      ],
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
                        // Start de complete afspeellijst in just_audio
                        audioHandler.setPlaylist(_playlist, _localImagePaths, index);
                      },
                    );
                  },
                ),
      
      bottomNavigationBar: _currentIndex != null
          ? GestureDetector(
              onTap: _openNowPlayingModal,
              child: Container(
                color: Colors.grey[900],
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
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
                    
                    Expanded(
                      child: Text(
                        _currentMediaItem?.title ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      iconSize: 32,
                      color: Colors.white,
                      onPressed: () => audioHandler.skipToPrevious(),
                    ),

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

                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      iconSize: 32,
                      color: Colors.white,
                      onPressed: () => audioHandler.skipToNext(),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
