import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_carplay/flutter_carplay.dart';

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

  FlutterCarplay.setRootTemplate(
    rootTemplate: CPListTemplate(
      title: 'Kia Ceed Mappen',
      sections: [
        CPListSection(
          items: [
            CPListItem(
              text: 'Mappen laden...',
              detailText: 'Even geduld a.u.b.',
              onPress: (complete, self) {
                complete();
              },
            ),
          ],
        ),
      ],
    ),
    animated: false,
  );

  runApp(const MyApp());
}

class SubtitleItem {
  final Duration start;
  final Duration end;
  final String text;

  SubtitleItem({required this.start, required this.end, required this.text});
}

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  List<SongItem> playlist = [];
  int currentIndex = 0;
  bool isShuffled = false;
  List<SongItem> _unshuffledPlaylist = [];

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

  Future<void> setPlaylist(List<SongItem> newPlaylist, int initialIndex, {bool keepOriginalOrder = false}) async {
    playlist = newPlaylist;
    if (!keepOriginalOrder) {
      _unshuffledPlaylist = List.from(newPlaylist);
    }
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
        album: song.folderName,
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

  Future<void> playFolderShuffled(List<SongItem> folderSongs) async {
    List<SongItem> shuffled = List.from(folderSongs);
    shuffled.shuffle(Random());
    await setPlaylist(shuffled, 0);
  }

  Future<void> restoreOriginalOrder(List<SongItem> originalSongs, {int initialIndex = 0}) async {
    await setPlaylist(originalSongs, initialIndex, keepOriginalOrder: true);
  }

  Future<void> toggleShuffle() async {
    isShuffled = !isShuffled;
    
    if (isShuffled) {
      final currentSong = playlist.isNotEmpty && currentIndex < playlist.length ? playlist[currentIndex] : null;
      List<SongItem> shuffled = List.from(playlist);
      shuffled.shuffle(Random());
      
      if (currentSong != null) {
        shuffled.remove(currentSong);
        shuffled.insert(0, currentSong);
      }
      
      await setPlaylist(shuffled, 0, keepOriginalOrder: true);
    } else {
      final currentSong = playlist.isNotEmpty && currentIndex < playlist.length ? playlist[currentIndex] : null;
      int newIndex = 0;
      if (currentSong != null) {
        newIndex = _unshuffledPlaylist.indexWhere((s) => s.path == currentSong.path);
        if (newIndex == -1) newIndex = 0;
      }
      await setPlaylist(_unshuffledPlaylist, newIndex, keepOriginalOrder: true);
    }
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
        album: song.folderName,
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
  final String? vttPath;
  final String folderName;

  SongItem({
    required this.path,
    required this.title,
    required this.artist,
    this.imagePath,
    this.vttPath,
    required this.folderName,
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
  Map<String, List<SongItem>> _folders = {};
  bool _isLoading = true;
  int? _currentIndex;
  bool _isPlaying = false;
  bool _isShuffled = false;
  String? _activeShuffledFolder;
  MediaItem? _currentMediaItem;

  @override
  void initState() {
    super.initState();
    _loadSongsFromFolders();

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
            final allSongs = _folders.values.expand((x) => x).toList();
            _currentIndex = allSongs.indexWhere((song) => song.path == item.id);
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

  Future<void> _loadSongsFromFolders() async {
    try {
      Map<String, List<SongItem>> loadedFolders = {};
      final appDocDir = await getApplicationDocumentsDirectory();

      final entities = appDocDir.listSync();
      for (var entity in entities) {
        if (entity is Directory) {
          final folderName = entity.path.split('/').last;
          if (folderName.startsWith('.')) continue;

          List<SongItem> folderSongs = [];
          try {
            final subFiles = entity.listSync();
            for (var subEntity in subFiles) {
              if (subEntity is File && subEntity.path.toLowerCase().endsWith('.mp3')) {
                final fileNameWithExt = subEntity.path.split('/').last;
                final baseName = fileNameWithExt.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
                
                final (artist, title) = _parseSongName(baseName);
                
                final potentialImage = File('${entity.path}/$baseName.jpg');
                String? imgPath = potentialImage.existsSync() ? potentialImage.path : null;

                final potentialVtt = File('${entity.path}/$baseName.vtt');
                String? vttPath = potentialVtt.existsSync() ? potentialVtt.path : null;

                folderSongs.add(SongItem(
                  path: subEntity.path,
                  title: title,
                  artist: artist,
                  imagePath: imgPath,
                  vttPath: vttPath,
                  folderName: folderName,
                ));
              }
            }
          } catch (e) {
            debugPrint("Fout bij lezen map $folderName: $e");
          }

          if (folderSongs.isNotEmpty) {
            folderSongs.sort((a, b) {
              int artistComp = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
              if (artistComp != 0) return artistComp;
              return a.title.toLowerCase().compareTo(b.title.toLowerCase());
            });
            loadedFolders[folderName] = folderSongs;
          }
        }
      }

      setState(() {
        _folders = loadedFolders;
        audioHandler.playlist = _folders.values.expand((x) => x).toList();
        audioHandler._unshuffledPlaylist = List.from(audioHandler.playlist);
        _isLoading = false;
      });

      _updateCarPlayTemplate();

    } catch (e) {
      debugPrint("Fout bij algemeen laden: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateCarPlayTemplate() {
    if (_folders.isEmpty) return;

    final List<CPListItem> folderItems = _folders.entries.map((entry) {
      final folderName = entry.key;
      final songsInFolder = entry.value;

      return CPListItem(
        text: folderName,
        detailText: '${songsInFolder.length} nummers (Tik om af te spelen)',
        onPress: (complete, self) async {
          final allSongs = _folders.values.expand((x) => x).toList();
          final firstSongInFolderIndex = allSongs.indexWhere((s) => s.path == songsInFolder.first.path);
          
          if (firstSongInFolderIndex != -1) {
            await audioHandler.setPlaylist(allSongs, firstSongInFolderIndex);
          }
          complete();
        },
      );
    }).toList();

    FlutterCarplay.setRootTemplate(
      rootTemplate: CPListTemplate(
        title: 'Muziek Mappen',
        sections: [
          CPListSection(
            items: folderItems,
          ),
        ],
      ),
      animated: true,
    );
  }

  void _toggleShuffle() async {
    await audioHandler.toggleShuffle();
    setState(() {
      _isShuffled = audioHandler.isShuffled;
      if (_isShuffled) {
        _activeShuffledFolder = null;
      }
    });
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
    final allSongs = _folders.values.expand((x) => x).toList();
    final currentSong = _currentIndex != null && _currentIndex! < allSongs.length
        ? allSongs[_currentIndex!]
        : null;
    final currentImagePath = currentSong?.imagePath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mijn MP3 Mappen'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.shuffle,
              color: _isShuffled ? Colors.green : Colors.white,
            ),
            onPressed: _toggleShuffle,
            tooltip: 'Algemene Shuffle (alle mappen)',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSongsFromFolders,
            tooltip: 'Vernieuw mappen',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
              ? const Center(child: Text('Geen mappen gevonden in de Documenten-map!'))
              : ListView.builder(
                  itemCount: _folders.keys.length,
                  itemBuilder: (context, index) {
                    final folderName = _folders.keys.elementAt(index);
                    final songs = _folders[folderName]!;
                    final isThisFolderShuffled = _activeShuffledFolder == folderName;

                    return ExpansionTile(
                      leading: const Icon(Icons.folder, color: Colors.amber),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              folderName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.shuffle,
                              size: 20,
                              color: isThisFolderShuffled ? Colors.green : Colors.grey,
                            ),
                            tooltip: isThisFolderShuffled ? 'Zet map shuffle uit' : 'Shuffle alleen deze map',
                            onPressed: () async {
                              if (isThisFolderShuffled) {
                                setState(() {
                                  _activeShuffledFolder = null;
                                });
                                await audioHandler.restoreOriginalOrder(songs);
                              } else {
                                await audioHandler.playFolderShuffled(songs);
                                setState(() {
                                  _activeShuffledFolder = folderName;
                                  _isShuffled = false;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      subtitle: Text('${songs.length} nummers', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      children: songs.map((song) {
                        final globalIndex = allSongs.indexWhere((s) => s.path == song.path);
                        final isSelected = _currentIndex == globalIndex;

                        return ListTile(
                          contentPadding: const EdgeInsets.only(left: 32, right: 16),
                          leading: song.imagePath != null && File(song.imagePath!).existsSync()
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.file(File(song.imagePath!), width: 40, height: 40, fit: BoxFit.cover),
                                )
                              : const Icon(Icons.music_note, size: 30),
                          title: Text(
                            song.title,
                            style: TextStyle(
                              color: isSelected ? Colors.green : Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(song.artist, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          trailing: isSelected && _isPlaying
                              ? const Icon(Icons.volume_up, color: Colors.green)
                              : null,
                          onTap: () {
                            audioHandler.setPlaylist(allSongs, globalIndex);
                          },
                        );
                      }).toList(),
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

// ** Grotere & Duidelijkere Equalizer / Waveform Animated Widget **
class EqualizerBars extends StatefulWidget {
  final bool isPlaying;
  const EqualizerBars({super.key, required this.isPlaying});

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPlaying) {
      return SizedBox(
        height: 28,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(8, (index) => Container(
            width: 4,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2),
            ),
          )),
        ),
      );
    }

    return SizedBox(
      height: 28,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(9, (index) {
              // Iets wildere en dynamische golfbeweging
              final val = sin((_controller.value * 2 * pi) + (index * 0.5)).abs();
              final height = 6.0 + (val * 20.0);
              return Container(
                width: 4,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  color: Colors.greenAccent,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
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
  List<SubtitleItem> _subtitles = [];

  @override
  void initState() {
    super.initState();
    _isPlaying = audioHandler._player.playing;
    _currentMediaItem = audioHandler.mediaItem.value;
    _loadSubtitles();

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
          _loadSubtitles();
        });
      }
    });
  }

  void _loadSubtitles() {
    _subtitles = [];
    final currentPath = _currentMediaItem?.id;
    if (currentPath == null) return;

    final allSongs = audioHandler.playlist;
    final currentSong = allSongs.firstWhere(
      (s) => s.path == currentPath,
      orElse: () => SongItem(path: '', title: '', artist: '', folderName: ''),
    );

    if (currentSong.vttPath != null) {
      final file = File(currentSong.vttPath!);
      if (file.existsSync()) {
        try {
          final lines = file.readAsLinesSync();
          _subtitles = _parseVtt(lines);
        } catch (e) {
          debugPrint("Fout bij inlezen VTT: $e");
        }
      }
    }
  }

  List<SubtitleItem> _parseVtt(List<String> lines) {
    List<SubtitleItem> subs = [];
    Duration? start;
    Duration? end;
    String textBuffer = "";

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.toUpperCase() == "WEBVTT" || line.startsWith("NOTE")) {
        continue;
      }

      if (line.contains("-->")) {
        final parts = line.split("-->");
        start = _parseDuration(parts[0].trim());
        end = _parseDuration(parts[1].trim().split(" ").first);
        textBuffer = "";
      } else {
        if (start != null && end != null) {
          if (textBuffer.isNotEmpty) textBuffer += "\n";
          textBuffer += line;
          
          if (!subs.any((s) => s.start == start)) {
            subs.add(SubtitleItem(start: start!, end: end!, text: textBuffer));
          } else {
            subs.last = SubtitleItem(start: start, end: end, text: textBuffer);
          }
        }
      }
    }
    return subs;
  }

  Duration _parseDuration(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final secParts = parts[2].split('.');
        final seconds = int.parse(secParts[0]);
        final milliseconds = secParts.length > 1 ? int.parse(secParts[1].padRight(3, '0').substring(0, 3)) : 0;
        return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: milliseconds);
      } else if (parts.length == 2) {
        final minutes = int.parse(parts[0]);
        final secParts = parts[1].split('.');
        final seconds = int.parse(secParts[0]);
        final milliseconds = secParts.length > 1 ? int.parse(secParts[1].padRight(3, '0').substring(0, 3)) : 0;
        return Duration(minutes: minutes, seconds: seconds, milliseconds: milliseconds);
      }
    } catch (_) {}
    return Duration.zero;
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
    final allSongs = audioHandler.playlist;
    final currentSong = allSongs.firstWhere(
      (s) => s.path == currentPath,
      orElse: () => SongItem(path: '', title: '', artist: '', folderName: ''),
    );
    final currentImagePath = currentSong.imagePath;

    // Controleer of de telefoon horizontaal (landscape) staat
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

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
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: isLandscape ? 4.0 : 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ** LANDSCAPE LAYOUT: Maximale foto links (flex 5), rechts alle controls (flex 6) **
            if (isLandscape) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Nog grotere albumcover links voor maximale grootte
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: currentImagePath != null && File(currentImagePath).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.file(
                                File(currentImagePath),
                                width: 250,
                                height: 250,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Container(
                              width: 250,
                              height: 250,
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.music_note, size: 80, color: Colors.white),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Rechter kolom
                  Expanded(
                    flex: 6,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Knoppen bovenaan rechts
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous),
                              iconSize: 38,
                              color: Colors.white,
                              onPressed: () => audioHandler.skipToPrevious(),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                              iconSize: 56,
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
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.skip_next),
                              iconSize: 38,
                              color: Colors.white,
                              onPressed: () => audioHandler.skipToNext(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Grotere Equalizer wave voorstelling
                        EqualizerBars(isPlaying: _isPlaying),
                        const SizedBox(height: 4),

                        // Titel & Artiest
                        Text(
                          _currentMediaItem?.title ?? '',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _currentMediaItem?.artist ?? 'Onbekende Artiest',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),

                        // VTT Ondertiteling / Songtekst Box
                        Container(
                          constraints: const BoxConstraints(minHeight: 25, maxHeight: 45),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: StreamBuilder<Duration>(
                            stream: audioHandler.positionStream,
                            builder: (context, snapshot) {
                              final position = snapshot.data ?? Duration.zero;
                              final activeSub = _subtitles.firstWhere(
                                (sub) => position >= sub.start && position <= sub.end,
                                orElse: () => SubtitleItem(start: Duration.zero, end: Duration.zero, text: ''),
                              );

                              return Text(
                                activeSub.text,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 2),

                        // Voortgangsbalk (Slider)
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
                                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(_formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                          Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              // ** PORTRAIT LAYOUT: Standaard onder elkaar **
              if (currentImagePath != null && File(currentImagePath).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(currentImagePath),
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.music_note, size: 70, color: Colors.white),
                ),
              const SizedBox(height: 14),

              // Grotere Equalizer in Portrait
              EqualizerBars(isPlaying: _isPlaying),
              const SizedBox(height: 14),

              Text(
                _currentMediaItem?.title ?? '',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _currentMediaItem?.artist ?? 'Onbekende Artiest',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // ** VTT Ondertiteling / Songtekst Box **
              Container(
                constraints: const BoxConstraints(minHeight: 30, maxHeight: 60),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: StreamBuilder<Duration>(
                  stream: audioHandler.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final activeSub = _subtitles.firstWhere(
                      (sub) => position >= sub.start && position <= sub.end,
                      orElse: () => SubtitleItem(start: Duration.zero, end: Duration.zero, text: ''),
                    );

                    return Text(
                      activeSub.text,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),
              
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
                                Text(_formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              
              const SizedBox(height: 16),
              
              // Knoppen onderaan in portrait
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
            ],
          ],
        ),
      ),
    );
  }
}

