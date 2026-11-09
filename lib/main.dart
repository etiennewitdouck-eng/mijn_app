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
  List<SongItem> playlist = [];
  int currentIndex = 0;

  MyAudioHandler() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    
    _player.currentIndexStream.listen((index) {
      if (index != null && index < playlist.length) {
        currentIndex = index;
        _updateMediaItemForCurrentIndex();
      }
    });
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

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

  Future<void> setPlaylist(List<SongItem> newPlaylist, int initialIndex) async {
    playlist = newPlaylist;
    currentIndex = initialIndex;

    final List<AudioSource> sources = playlist.map((song) {
      Uri? artUri;
      if (song.imagePath != null) {
        final imageFile = File(song.imagePath!);
        if (imageFile.existsSync()) {
          artUri = Uri.parse('file://${imageFile.path}');
        }
      }

      final mediaItemTag = MediaItem(
        id: song.path,
        album: 'Mijn MP3 Map',
        title: song.title,
        artist: song.artist,
        artUri: artUri,
      );

      return AudioSource.file(song.path, tag: mediaItemTag);
    }).toList();

    await _player.setAudioSource(ConcatenatingAudioSource(children: sources), initialIndex: currentIndex);
    _updateMediaItemForCurrentIndex();
    await _player.play();
  }

  void _updateMediaItemForCurrentIndex() {
    if (playlist.isEmpty || currentIndex >= playlist.length) return;
    final song = playlist[currentIndex];

    Uri? artUri;
    if (song.imagePath != null) {
      final imageFile = File(song.imagePath!);
      if (imageFile.existsSync()) {
        artUri = Uri.parse('file://${imageFile.path}');
      }
    }

    mediaItem.add(
      MediaItem(
        id: song.path,
        album: 'Mijn MP3 Map',
        title: song.title,
        artist: song.artist,
        artUri: artUri,
      ),
    );
  }

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      await _player.seek(Duration.zero, index: 0);
    }
    await _player.play();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero, index: playlist.length - 1);
    }
    await _player.play();
  }
}

class SongItem {
  final String path;
  final String title;
  final String artist;
  final String? imagePath;

  SongItem({
    required this.path,
    required this.title,
    required this.artist,
    this.imagePath,
  });
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
  List<SongItem> _playlist = [];
  bool _isLoading = true;
  int? _currentIndex;
  bool _isPlaying = false;
  MediaItem? _currentMediaItem;

  @override
  void initState() {
    super.initState();
    _loadSongs();

    audioHandler.playbackState.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });

    audioHandler.mediaItem.listen((item) {
      if (mounted) {
        setState(() {
          _currentMediaItem = item;
          if (item != null) {
            _currentIndex = _playlist.indexWhere((song) => song.path == item.id);
          }
        });
      }
    });
  }

  (String artist, String title) _parseSongName(String fileNameWithoutExt) {
    String artist = 'Onbekende Artiest';
    String title = fileNameWithoutExt;

    final dashIndex = fileNameWithoutExt.indexOf('-');
    if (dashIndex != -1) {
      artist = fileNameWithoutExt.substring(0, dashIndex).trim();
      title = fileNameWithoutExt.substring(dashIndex + 1).trim().replaceAll('-', ' ');
    }
    return (artist, title);
  }

  Future<void> _loadSongs() async {
    try {
      List<SongItem> loadedSongs = [];
      final appDocDir = await getApplicationDocumentsDirectory();

      try {
        final dirFiles = appDocDir.listSync();
        for (var entity in dirFiles) {
          if (entity is File && entity.path.toLowerCase().endsWith('.mp3')) {
            final fileNameWithExt = entity.path.split('/').last;
            final baseName = fileNameWithExt.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
            
            final (artist, title) = _parseSongName(baseName);

            final potentialImage = File('${appDocDir.path}/$baseName.jpg');
            String? imgPath = potentialImage.existsSync() ? potentialImage.path : null;

            loadedSongs.add(SongItem(
              path: entity.path,
              title: title,
              artist: artist,
              imagePath: imgPath,
            ));
          }
        }
      } catch (e) {
        debugPrint("Fout bij scannen Documenten-map: $e");
      }

      setState(() {
        _playlist = loadedSongs;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Fout bij algemeen laden: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openNowPlayingScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NowPlayingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = _currentIndex != null && _currentIndex! < _playlist.length
        ? _playlist[_currentIndex!]
        : null;
    final currentImagePath = currentSong?.imagePath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mijn MP3 Auto Speler'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSongs,
            tooltip: 'Vernieuw liedjes',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlist.isEmpty
              ? const Center(child: Text('Geen liedjes gevonden in de Documenten-map!'))
              : ListView.builder(
                  itemCount: _playlist.length,
                  itemBuilder: (context, index) {
                    final song = _playlist[index];
                    final isSelected = _currentIndex == index;

                    return ListTile(
                      leading: song.imagePath != null && File(song.imagePath!).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(File(song.imagePath!), width: 45, height: 45, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.music_note),
                      title: Text(
                        song.title,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.green : Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        song.artist,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      trailing: isSelected && _isPlaying
                          ? const Icon(Icons.volume_up, color: Colors.green)
                          : null,
                      onTap: () {
                        audioHandler.setPlaylist(_playlist, index);
                      },
                    );
                  },
                ),
      
      bottomNavigationBar: _currentIndex != null
          ? GestureDetector(
              onTap: _openNowPlayingScreen,
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentMediaItem?.title ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _currentMediaItem?.artist ?? '',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _isPlaying = false;
  MediaItem? _currentMediaItem;

  @override
  void initState() {
    super.initState();
    _isPlaying = audioHandler._player.playing;
    _currentMediaItem = audioHandler.mediaItem.value;

    audioHandler.playbackState.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });

    audioHandler.mediaItem.listen((item) {
      if (mounted) {
        setState(() {
          _currentMediaItem = item;
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = _currentMediaItem?.id;
    final currentSong = audioHandler.playlist.firstWhere(
      (s) => s.path == currentPath,
      orElse: () => SongItem(path: '', title: '', artist: ''),
    );
    final currentImagePath = currentSong.imagePath;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Now Playing', style: TextStyle(fontSize: 16)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
            Text(
              _currentMediaItem?.artist ?? 'Onbekende Artiest',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            
            StreamBuilder<Duration>(
              stream: audioHandler.positionStream,
              builder: (context, snapshotPosition) {
                final position = snapshotPosition.data ?? Duration.zero;
                return StreamBuilder<Duration?>(
                  stream: audioHandler.durationStream,
                  builder: (context, snapshotDuration) {
                    final duration = snapshotDuration.data ?? Duration.zero;
                    
                    double maxVal = duration.inMilliseconds.toDouble();
                    double currentVal = position.inMilliseconds.toDouble();
                    if (maxVal <= 0) maxVal = 1.0;
                    if (currentVal > maxVal) currentVal = maxVal;

                    return Column(
                      children: [
                        Slider(
                          min: 0.0,
                          max: maxVal,
                          value: currentVal,
                          activeColor: Colors.green,
                          inactiveColor: Colors.grey[700],
                          onChanged: (value) {
                            audioHandler.seek(Duration(milliseconds: value.toInt()));
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
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
                    setState(() {});
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
  }
}
