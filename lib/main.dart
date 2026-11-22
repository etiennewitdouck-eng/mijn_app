import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

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

class YouTubeLinkItem {
  final String title;
  final String url;
  final String folderName;

  YouTubeLinkItem({
    required this.title,
    required this.url,
    required this.folderName,
  });
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
    try {
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
    } catch (e) {
      debugPrint("Fout bij afspelen van playlist: $e");
    }
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
  final String? videoPath;
  final String? vttPath;
  final String? vttNlPath;
  final String folderName;
  final List<String> slideshowPhotos;

  SongItem({
    required this.path,
    required this.title,
    required this.artist,
    this.imagePath,
    this.videoPath,
    this.vttPath,
    this.vttNlPath,
    required this.folderName,
    this.slideshowPhotos = const [],
  });
}

class _SubfolderData {
  final List<SongItem> songs;
  final List<YouTubeLinkItem> links;
  final List<String> photos;
  final bool isPhotoFolder;

  _SubfolderData({
    required this.songs,
    required this.links,
    required this.photos,
    required this.isPhotoFolder,
  });
}

class _FolderGroup {
  final String name;
  final List<SongItem> directSongs;
  final List<YouTubeLinkItem> directLinks;
  final List<String> directPhotos;
  final bool isPhotoFolder;
  final Map<String, _SubfolderData> subfolders;

  _FolderGroup({
    required this.name,
    required this.directSongs,
    required this.directLinks,
    required this.directPhotos,
    required this.isPhotoFolder,
    required this.subfolders,
  });

  List<String> get allGroupPhotos {
    return [
      ...directPhotos,
      for (final sub in subfolders.values) ...sub.photos,
    ];
  }

  List<SongItem> get allSongsInGroup {
    final groupPhotos = allGroupPhotos;
    return [
      ...directSongs.map((s) => _withSlideshow(s, groupPhotos)),
      for (final sub in subfolders.values)
        ...sub.songs.map(
          (s) => _withSlideshow(s, sub.photos.isNotEmpty ? sub.photos : groupPhotos),
        ),
    ];
  }

  static SongItem _withSlideshow(SongItem song, List<String> photos) {
    if (photos.isEmpty) return song;
    return SongItem(
      path: song.path,
      title: song.title,
      artist: song.artist,
      imagePath: song.imagePath,
      videoPath: song.videoPath,
      vttPath: song.vttPath,
      vttNlPath: song.vttNlPath,
      folderName: song.folderName,
      slideshowPhotos: photos,
    );
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
  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
  };

  Map<String, _FolderGroup> _folderGroups = {};
  bool _isLoading = true;
  int? _currentIndex;
  bool _isPlaying = false;
  bool _isShuffled = false;
  String? _activeShuffledKey;
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
            final allSongs = _getAllSongs();
            _currentIndex = allSongs.indexWhere((song) => song.path == item.id);
          }
        });
      }
    });
  }

  bool _isPhotoFolderName(String name) => name.toLowerCase() == '_foto';

  bool _isSupportedImagePath(String path) {
    final lower = path.toLowerCase();
    return _imageExtensions.any((ext) => lower.endsWith(ext));
  }

  String? _findCoverImagePath(String parentPath, String baseName) {
    for (final ext in _imageExtensions) {
      final candidate = File('$parentPath/$baseName$ext');
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
    return null;
  }

  List<SongItem> _getAllSongs() {
    return [
      for (final group in _folderGroups.values) ...group.allSongsInGroup,
    ];
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

  void _sortSongs(List<SongItem> songs) {
    songs.sort((a, b) {
      int artistComp = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      if (artistComp != 0) return artistComp;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  }

  List<YouTubeLinkItem> _parseLinksFromTxtFile(File txtFile, String folderLabel) {
    final List<YouTubeLinkItem> found = [];
    try {
      final lines = txtFile.readAsLinesSync();
      final urlRegex = RegExp(r'(https?://\S+)');

      for (var rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        final match = urlRegex.firstMatch(line);
        if (match == null) continue;

        final url = match.group(1)!.trim();
        String titlePart = line.substring(0, match.start).trim();
        titlePart = titlePart.replaceAll(RegExp(r'[:|\-–—]+$'), '').trim();

        if (titlePart.isEmpty) {
          titlePart = txtFile.path.split('/').last.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
        }

        found.add(
          YouTubeLinkItem(
            title: titlePart,
            url: url,
            folderName: folderLabel,
          ),
        );
      }
    } catch (e) {
      debugPrint("Fout bij inlezen tekstbestand ${txtFile.path}: $e");
    }
    return found;
  }

  void _collectFolderContentsRecursive(
    Directory dir,
    String labelName,
    List<SongItem> targetSongs,
    List<YouTubeLinkItem> targetLinks,
    List<String> targetPhotos,
    Set<String> seenPhotoPaths, {
    required bool insidePhotoTree,
  }) {
    try {
      final subEntities = dir.listSync();
      for (var subEntity in subEntities) {
        final name = subEntity.path.split('/').last;
        if (name.startsWith('.')) continue;

        if (subEntity is File && subEntity.path.toLowerCase().endsWith('.mp3')) {
          final baseName = name.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
          final parentPath = subEntity.parent.path;

          final (artist, title) = _parseSongName(baseName);
          final String? imgPath = _findCoverImagePath(parentPath, baseName);

          final potentialVideo = File('$parentPath/$baseName.mp4');
          String? videoPath = potentialVideo.existsSync() ? potentialVideo.path : null;

          final potentialVtt = File('$parentPath/$baseName.vtt');
          String? vttPath = potentialVtt.existsSync() ? potentialVtt.path : null;

          final potentialVttNl = File('$parentPath/$baseName.nl.vtt');
          String? vttNlPath = potentialVttNl.existsSync() ? potentialVttNl.path : null;

          targetSongs.add(SongItem(
            path: subEntity.path,
            title: title,
            artist: artist,
            imagePath: imgPath,
            videoPath: videoPath,
            vttPath: vttPath,
            vttNlPath: vttNlPath,
            folderName: labelName,
          ));
        } else if (subEntity is File && subEntity.path.toLowerCase().endsWith('.txt')) {
          targetLinks.addAll(_parseLinksFromTxtFile(subEntity, labelName));
        } else if (subEntity is File && _isSupportedImagePath(subEntity.path)) {
          if (insidePhotoTree && seenPhotoPaths.add(subEntity.path)) {
            targetPhotos.add(subEntity.path);
          }
        } else if (subEntity is Directory) {
          final nextPhotoTree = insidePhotoTree || _isPhotoFolderName(name);
          _collectFolderContentsRecursive(
            subEntity,
            '$labelName / $name',
            targetSongs,
            targetLinks,
            targetPhotos,
            seenPhotoPaths,
            insidePhotoTree: nextPhotoTree,
          );
        }
      }
    } catch (e) {
      debugPrint("Fout bij lezen map ${dir.path}: $e");
    }
  }

  Future<void> _loadSongsFromFolders() async {
    try {
      Map<String, _FolderGroup> loadedGroups = {};
      final appDocDir = await getApplicationDocumentsDirectory();

      final entities = appDocDir.listSync();
      for (var entity in entities) {
        if (entity is Directory) {
          final folderName = entity.path.split('/').last;
          if (folderName.startsWith('.')) continue;

          final isPhotoMainFolder = _isPhotoFolderName(folderName);
          List<SongItem> directSongs = [];
          List<YouTubeLinkItem> directLinks = [];
          List<String> directPhotos = [];
          Map<String, _SubfolderData> subfolders = {};
          final Set<String> seenPhotoPaths = <String>{};

          try {
            final subEntities = entity.listSync();
            for (var subEntity in subEntities) {
              final name = subEntity.path.split('/').last;
              if (name.startsWith('.')) continue;

              if (subEntity is File && subEntity.path.toLowerCase().endsWith('.mp3')) {
                final baseName = name.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
                final parentPath = subEntity.parent.path;
                final (artist, title) = _parseSongName(baseName);
                final String? imgPath = _findCoverImagePath(parentPath, baseName);

                final potentialVideo = File('$parentPath/$baseName.mp4');
                String? videoPath = potentialVideo.existsSync() ? potentialVideo.path : null;

                final potentialVtt = File('$parentPath/$baseName.vtt');
                String? vttPath = potentialVtt.existsSync() ? potentialVtt.path : null;

                final potentialVttNl = File('$parentPath/$baseName.nl.vtt');
                String? vttNlPath = potentialVttNl.existsSync() ? potentialVttNl.path : null;

                directSongs.add(SongItem(
                  path: subEntity.path,
                  title: title,
                  artist: artist,
                  imagePath: imgPath,
                  videoPath: videoPath,
                  vttPath: vttPath,
                  vttNlPath: vttNlPath,
                  folderName: folderName,
                ));
              } else if (subEntity is File && subEntity.path.toLowerCase().endsWith('.txt')) {
                directLinks.addAll(_parseLinksFromTxtFile(subEntity, folderName));
              } else if (subEntity is File && _isSupportedImagePath(subEntity.path)) {
                if (isPhotoMainFolder && seenPhotoPaths.add(subEntity.path)) {
                  directPhotos.add(subEntity.path);
                }
              } else if (subEntity is Directory) {
                final isPhotoSub = isPhotoMainFolder || _isPhotoFolderName(name);
                List<SongItem> subSongs = [];
                List<YouTubeLinkItem> subLinks = [];
                List<String> subPhotos = [];
                _collectFolderContentsRecursive(
                  subEntity,
                  '$folderName / $name',
                  subSongs,
                  subLinks,
                  subPhotos,
                  seenPhotoPaths,
                  insidePhotoTree: isPhotoSub,
                );
                _sortSongs(subSongs);
                subPhotos.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                if (subSongs.isNotEmpty || subLinks.isNotEmpty || subPhotos.isNotEmpty) {
                  subfolders[name] = _SubfolderData(
                    songs: subSongs,
                    links: subLinks,
                    photos: subPhotos,
                    isPhotoFolder: isPhotoSub,
                  );
                }
              }
            }
          } catch (e) {
            debugPrint("Fout bij lezen hoofdmap $folderName: $e");
          }

          _sortSongs(directSongs);
          directPhotos.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          final sortedSubfolderKeys = subfolders.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          final sortedSubfolders = {
            for (final key in sortedSubfolderKeys) key: subfolders[key]!,
          };

          if (directSongs.isNotEmpty ||
              directLinks.isNotEmpty ||
              directPhotos.isNotEmpty ||
              sortedSubfolders.isNotEmpty) {
            loadedGroups[folderName] = _FolderGroup(
              name: folderName,
              directSongs: directSongs,
              directLinks: directLinks,
              directPhotos: directPhotos,
              isPhotoFolder: isPhotoMainFolder,
              subfolders: sortedSubfolders,
            );
          }
        }
      }

      setState(() {
        _folderGroups = loadedGroups;
        audioHandler.playlist = _getAllSongs();
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

  Uri _normalizeToMobileYouTubeUri(String urlString) {
    final parsed = Uri.parse(urlString.trim());

    if (parsed.host == 'youtu.be') {
      final videoId = parsed.pathSegments.isNotEmpty ? parsed.pathSegments.first : '';
      final queryParams = Map<String, String>.from(parsed.queryParameters);
      if (videoId.isNotEmpty && !queryParams.containsKey('v')) {
        queryParams['v'] = videoId;
      }
      return Uri(
        scheme: 'https',
        host: 'm.youtube.com',
        path: '/watch',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
    }

    if (parsed.host == 'www.youtube.com' || parsed.host == 'youtube.com') {
      return parsed.replace(
        scheme: 'https',
        host: 'm.youtube.com',
      );
    }

    return parsed;
  }

  Future<void> _openYouTubeUrl(String urlString) async {
    Uri uri;
    try {
      uri = _normalizeToMobileYouTubeUri(urlString);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ongeldige link')),
        );
      }
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kon link niet openen: $urlString')),
      );
    }
  }

  void _updateCarPlayTemplate() {
    if (_folderGroups.isEmpty) return;

    final allSongs = _getAllSongs();
    final List<CPListItem> folderItems = [];

    for (final group in _folderGroups.values) {
      if (group.directSongs.isNotEmpty) {
        folderItems.add(
          CPListItem(
            text: group.name,
            detailText: '${group.directSongs.length} nummers (Tik om af te spelen)',
            onPress: (complete, self) async {
              final firstIndex = allSongs.indexWhere((s) => s.path == group.directSongs.first.path);
              if (firstIndex != -1) {
                await audioHandler.setPlaylist(allSongs, firstIndex);
              }
              complete();
            },
          ),
        );
      }

      for (final subEntry in group.subfolders.entries) {
        final subName = subEntry.key;
        final subSongs = subEntry.value.songs;
        if (subSongs.isNotEmpty) {
          folderItems.add(
            CPListItem(
              text: '${group.name} / $subName',
              detailText: '${subSongs.length} nummers (Tik om af te spelen)',
              onPress: (complete, self) async {
                final firstIndex = allSongs.indexWhere((s) => s.path == subSongs.first.path);
                if (firstIndex != -1) {
                  await audioHandler.setPlaylist(allSongs, firstIndex);
                }
                complete();
              },
            ),
          );
        }
      }
    }

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
        _activeShuffledKey = null;
      }
    });
  }

  void _openNowPlayingScreen({
    List<String> slideshowPhotos = const [],
    String? slideshowTitle,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NowPlayingScreen(
          initialSlideshowPhotos: slideshowPhotos,
          slideshowTitle: slideshowTitle,
        ),
      ),
    );
  }

  Widget _buildSlideshowLaunchTile({
    required String title,
    required List<String> photos,
    required List<SongItem> songs,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 36, right: 16),
      leading: const Icon(Icons.photo_library, color: Colors.cyanAccent, size: 30),
      title: Text(
        'Diashow: $title',
        style: const TextStyle(
          color: Colors.cyanAccent,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${photos.length} foto(s)${songs.isNotEmpty ? ' · ${songs.length} mp3 beschikbaar' : ' · zonder mp3'}',
        style: const TextStyle(color: Colors.grey, fontSize: 11),
      ),
      trailing: const Icon(Icons.slideshow, color: Colors.cyanAccent, size: 22),
      onTap: () {
        if (songs.isNotEmpty) {
          final allSongs = _getAllSongs();
          final firstIndex = allSongs.indexWhere((s) => s.path == songs.first.path);
          if (firstIndex != -1) {
            audioHandler.setPlaylist(allSongs, firstIndex);
          }
        }
        _openNowPlayingScreen(
          slideshowPhotos: photos,
          slideshowTitle: title,
        );
      },
    );
  }

  Widget _buildLinkTile(YouTubeLinkItem link) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 36, right: 16),
      leading: const Icon(Icons.ondemand_video, color: Colors.redAccent, size: 30),
      title: Text(
        link.title,
        style: const TextStyle(
          color: Colors.amberAccent,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        link.url,
        style: const TextStyle(color: Colors.grey, fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.open_in_new, color: Colors.grey, size: 18),
      onTap: () => _openYouTubeUrl(link.url),
    );
  }

  Widget _buildSongTile(SongItem song, List<SongItem> allSongs) {
    final globalIndex = allSongs.indexWhere((s) => s.path == song.path);
    final isSelected = _currentIndex == globalIndex;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 36, right: 16),
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
        if (globalIndex != -1) {
          audioHandler.setPlaylist(allSongs, globalIndex);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSongs = _getAllSongs();
    final currentSong = _currentIndex != null && _currentIndex! < allSongs.length
        ? allSongs[_currentIndex!]
        : null;
    final currentImagePath = currentSong?.imagePath;
    final groupKeys = _folderGroups.keys.toList();

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
          : groupKeys.isEmpty
              ? const Center(child: Text('Geen mappen gevonden in de Documenten-map!'))
              : ListView.builder(
                  itemCount: groupKeys.length,
                  itemBuilder: (context, index) {
                    final folderName = groupKeys[index];
                    final group = _folderGroups[folderName]!;
                    final totalSongsInGroup = group.allSongsInGroup.length;
                    final totalPhotosInGroup = group.allGroupPhotos.length;
                    final groupShuffleKey = 'main:$folderName';
                    final isGroupShuffled = _activeShuffledKey == groupShuffleKey;

                    return ExpansionTile(
                      leading: Icon(
                        group.isPhotoFolder ? Icons.photo_library : Icons.folder,
                        color: group.isPhotoFolder ? Colors.cyanAccent : Colors.amber,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              folderName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (totalPhotosInGroup > 0)
                            IconButton(
                              icon: const Icon(
                                Icons.slideshow,
                                size: 20,
                                color: Colors.cyanAccent,
                              ),
                              tooltip: 'Start _foto diashow',
                              onPressed: () {
                                if (group.allSongsInGroup.isNotEmpty) {
                                  final firstIdx = allSongs.indexWhere(
                                    (s) => s.path == group.allSongsInGroup.first.path,
                                  );
                                  if (firstIdx != -1) {
                                    audioHandler.setPlaylist(allSongs, firstIdx);
                                  }
                                }
                                _openNowPlayingScreen(
                                  slideshowPhotos: group.allGroupPhotos,
                                  slideshowTitle: folderName,
                                );
                              },
                            ),
                          if (group.allSongsInGroup.isNotEmpty)
                            IconButton(
                              icon: Icon(
                                Icons.shuffle,
                                size: 20,
                                color: isGroupShuffled ? Colors.green : Colors.grey,
                              ),
                              tooltip: isGroupShuffled ? 'Zet map shuffle uit' : 'Shuffle deze map',
                              onPressed: () async {
                                if (isGroupShuffled) {
                                  setState(() {
                                    _activeShuffledKey = null;
                                  });
                                  await audioHandler.restoreOriginalOrder(group.allSongsInGroup);
                                } else {
                                  await audioHandler.playFolderShuffled(group.allSongsInGroup);
                                  setState(() {
                                    _activeShuffledKey = groupShuffleKey;
                                    _isShuffled = false;
                                  });
                                }
                              },
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '$totalSongsInGroup nummers'
                        '${totalPhotosInGroup > 0 ? ' · $totalPhotosInGroup foto(s)' : ''}'
                        '${group.subfolders.isNotEmpty ? ' · ${group.subfolders.length} submap(pen)' : ''}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      children: [
                        ...group.subfolders.entries.map((subEntry) {
                          final subName = subEntry.key;
                          final subData = subEntry.value;
                          final subSongs = subData.songs;
                          final subLinks = subData.links;
                          final subPhotos = subData.photos;
                          final subShuffleKey = 'sub:$folderName/$subName';
                          final isSubShuffled = _activeShuffledKey == subShuffleKey;

                          return Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: ExpansionTile(
                              leading: Icon(
                                subData.isPhotoFolder ? Icons.photo_library : Icons.folder_open,
                                color: subData.isPhotoFolder ? Colors.cyanAccent : Colors.amberAccent,
                                size: 22,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      subName,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                  ),
                                  if (subPhotos.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.slideshow,
                                        size: 18,
                                        color: Colors.cyanAccent,
                                      ),
                                      tooltip: 'Start diashow voor $subName',
                                      onPressed: () {
                                        if (subSongs.isNotEmpty) {
                                          final firstIdx = allSongs.indexWhere(
                                            (s) => s.path == subSongs.first.path,
                                          );
                                          if (firstIdx != -1) {
                                            audioHandler.setPlaylist(allSongs, firstIdx);
                                          }
                                        }
                                        _openNowPlayingScreen(
                                          slideshowPhotos: subPhotos,
                                          slideshowTitle: '$folderName / $subName',
                                        );
                                      },
                                    ),
                                  if (subSongs.isNotEmpty)
                                    IconButton(
                                      icon: Icon(
                                        Icons.shuffle,
                                        size: 18,
                                        color: isSubShuffled ? Colors.green : Colors.grey,
                                      ),
                                      tooltip: isSubShuffled ? 'Zet submap shuffle uit' : 'Shuffle alleen deze submap',
                                      onPressed: () async {
                                        if (isSubShuffled) {
                                          setState(() {
                                            _activeShuffledKey = null;
                                          });
                                          await audioHandler.restoreOriginalOrder(subSongs);
                                        } else {
                                          await audioHandler.playFolderShuffled(subSongs);
                                          setState(() {
                                            _activeShuffledKey = subShuffleKey;
                                            _isShuffled = false;
                                          });
                                        }
                                      },
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                '${subSongs.length} nummers'
                                '${subPhotos.isNotEmpty ? ' · ${subPhotos.length} foto(s)' : ''}'
                                '${subLinks.isNotEmpty ? ' · ${subLinks.length} link(s)' : ''}',
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                              children: [
                                if (subPhotos.isNotEmpty)
                                  _buildSlideshowLaunchTile(
                                    title: '$folderName / $subName',
                                    photos: subPhotos,
                                    songs: subSongs,
                                  ),
                                ...subLinks.map((link) => _buildLinkTile(link)),
                                ...subSongs.map((song) => _buildSongTile(song, allSongs)),
                              ],
                            ),
                          );
                        }),
                        if (group.directPhotos.isNotEmpty)
                          _buildSlideshowLaunchTile(
                            title: folderName,
                            photos: group.directPhotos,
                            songs: group.directSongs,
                          ),
                        ...group.directLinks.map((link) => _buildLinkTile(link)),
                        ...group.directSongs.map((song) => _buildSongTile(song, allSongs)),
                      ],
                    );
                  },
                ),
      bottomNavigationBar: _currentIndex != null
          ? GestureDetector(
              onTap: () => _openNowPlayingScreen(),
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

class SpectrumVisualizer extends StatelessWidget {
  final bool isPlaying;
  final Stream<Duration> positionStream;

  const SpectrumVisualizer({
    super.key,
    required this.isPlaying,
    required this.positionStream,
  });

  @override
  Widget build(BuildContext context) {
    const int barCount = 16;

    if (!isPlaying) {
      return SizedBox(
        height: 32,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(
            barCount,
            (index) => Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
    }

    return StreamBuilder<Duration>(
      stream: positionStream,
      builder: (context, snapshot) {
        final positionMs = (snapshot.data ?? Duration.zero).inMilliseconds.toDouble();

        return SizedBox(
          height: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(barCount, (index) {
              final timeFactor = positionMs / 180.0;
              final wave = sin(timeFactor + (index * 0.4));
              final cosWave = cos(timeFactor * 0.7 + (index * 0.3));

              final multiplier = (index < 5) ? 24.0 : (index < 11 ? 18.0 : 12.0);
              final height = 6.0 + ((wave.abs() * 0.6 + cosWave.abs() * 0.4) * multiplier);

              return Container(
                width: 4,
                height: height,
                decoration: BoxDecoration(
                  color: index < 5 ? Colors.green : (index < 11 ? Colors.greenAccent : Colors.lightGreenAccent),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class NowPlayingScreen extends StatefulWidget {
  final List<String> initialSlideshowPhotos;
  final String? slideshowTitle;

  const NowPlayingScreen({
    super.key,
    this.initialSlideshowPhotos = const [],
    this.slideshowTitle,
  });

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _isPlaying = false;
  MediaItem? _currentMediaItem;
  List<SubtitleItem> _subtitles = [];
  List<SubtitleItem> _subtitlesNl = [];
  bool _showNlSubtitles = false;
  bool _isFullscreen = false;
  bool _fitCoverImages = false;

  // Schakelaar voor video aan/uit (Aan = MiraScreen / lokaal, Uit = AirPin Lite poster modus)
  bool _enableVideoPlayback = true;

  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  // Diashow state voor _foto mappen
  List<String> _slideshowPhotos = [];
  int _photoIndex = 0;
  bool _slideshowRunning = true;
  Timer? _slideshowTimer;

  @override
  void initState() {
    super.initState();
    _isPlaying = audioHandler._player.playing;
    _currentMediaItem = audioHandler.mediaItem.value;
    _slideshowPhotos = List.from(widget.initialSlideshowPhotos);
    _loadSongDetails();
    _startSlideshowTimerIfNeeded();

    audioHandler.playbackState.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (_videoController != null && _isVideoInitialized) {
            if (_isPlaying && !_videoController!.value.isPlaying) {
              _videoController!.play();
            } else if (!_isPlaying && _videoController!.value.isPlaying) {
              _videoController!.pause();
            }
          }
        });
      }
    });

    audioHandler.mediaItem.listen((item) {
      if (mounted) {
        setState(() {
          _currentMediaItem = item;
          _loadSongDetails();
        });
      }
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _slideshowTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  void _setFullscreen(bool fullscreen) {
    setState(() {
      _isFullscreen = fullscreen;
    });
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _startSlideshowTimerIfNeeded() {
    _slideshowTimer?.cancel();
    if (_slideshowPhotos.length > 1 && _slideshowRunning) {
      _slideshowTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted || !_slideshowRunning || _slideshowPhotos.isEmpty) return;
        setState(() {
          _photoIndex = (_photoIndex + 1) % _slideshowPhotos.length;
        });
      });
    }
  }

  void _toggleSlideshowRunning() {
    setState(() {
      _slideshowRunning = !_slideshowRunning;
    });
    _startSlideshowTimerIfNeeded();
  }

  void _stepPhoto(int delta) {
    if (_slideshowPhotos.isEmpty) return;
    setState(() {
      _photoIndex = (_photoIndex + delta) % _slideshowPhotos.length;
      if (_photoIndex < 0) {
        _photoIndex += _slideshowPhotos.length;
      }
    });
  }

  void _syncVideoToPosition(Duration position) {
    final controller = _videoController;
    if (controller == null || !_isVideoInitialized) return;

    final videoDuration = controller.value.duration;
    if (videoDuration <= Duration.zero) {
      controller.seekTo(position);
      return;
    }

    final targetMs = position.inMilliseconds % videoDuration.inMilliseconds;
    controller.seekTo(Duration(milliseconds: targetMs));
  }

  void _loadSongDetails() {
    _subtitles = [];
    _subtitlesNl = [];

    final oldController = _videoController;
    _videoController = null;
    _isVideoInitialized = false;
    oldController?.dispose();

    final currentPath = _currentMediaItem?.id;
    if (currentPath == null) return;

    final allSongs = audioHandler.playlist;
    final currentSong = allSongs.firstWhere(
      (s) => s.path == currentPath,
      orElse: () => SongItem(path: '', title: '', artist: '', folderName: ''),
    );

    if (currentSong.slideshowPhotos.isNotEmpty) {
      final listChanged = _slideshowPhotos.length != currentSong.slideshowPhotos.length ||
          _slideshowPhotos.first != currentSong.slideshowPhotos.first;
      if (listChanged) {
        _slideshowPhotos = List.from(currentSong.slideshowPhotos);
        _photoIndex = 0;
        _startSlideshowTimerIfNeeded();
      }
    } else if (widget.initialSlideshowPhotos.isEmpty) {
      _slideshowPhotos = [];
      _photoIndex = 0;
      _slideshowTimer?.cancel();
    }

    if (_enableVideoPlayback && currentSong.videoPath != null) {
      final videoFile = File(currentSong.videoPath!);
      if (videoFile.existsSync()) {
        final controller = VideoPlayerController.file(
          videoFile,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        _videoController = controller;

        controller.initialize().then((_) {
          if (mounted && _videoController == controller) {
            setState(() {
              _isVideoInitialized = true;
              controller.setLooping(true);
              controller.setVolume(0.0);
              _syncVideoToPosition(audioHandler._player.position);
              if (_isPlaying) {
                controller.play();
              }
            });
          }
        }).catchError((error) {
          debugPrint("Fout bij video initialiseren: $error");
        });
      }
    }

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

    if (currentSong.vttNlPath != null) {
      final fileNl = File(currentSong.vttNlPath!);
      if (fileNl.existsSync()) {
        try {
          final linesNl = fileNl.readAsLinesSync();
          _subtitlesNl = _parseVtt(linesNl);
        } catch (e) {
          debugPrint("Fout bij inlezen NL VTT: $e");
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
            subs.add(SubtitleItem(start: start, end: end, text: textBuffer));
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

  Widget _buildSubtitleOverlay({
    required bool hasAnySubtitle,
    required double fontSize,
    double borderRadius = 14,
  }) {
    if (!hasAnySubtitle) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: StreamBuilder<Duration>(
        stream: audioHandler.positionStream,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          final activeList = (_showNlSubtitles && _subtitlesNl.isNotEmpty)
              ? _subtitlesNl
              : (_subtitles.isNotEmpty ? _subtitles : _subtitlesNl);
          final activeSub = activeList.firstWhere(
            (sub) => position >= sub.start && position <= sub.end,
            orElse: () => SubtitleItem(start: Duration.zero, end: Duration.zero, text: ''),
          );

          if (activeSub.text.trim().isEmpty) {
            return const SizedBox.shrink();
          }

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(borderRadius)),
            ),
            child: Text(
              activeSub.text,
              style: TextStyle(
                fontSize: fontSize,
                color: Colors.yellow,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(blurRadius: 3, color: Colors.black, offset: Offset(1, 1)),
                ],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }

  Widget _buildPositionSlider({
    required double horizontalPadding,
    required double labelFontSize,
  }) {
    return StreamBuilder<Duration>(
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
                    final target = Duration(milliseconds: value.toInt());
                    audioHandler.seek(target);
                    _syncVideoToPosition(target);
                  },
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(position), style: TextStyle(color: Colors.grey, fontSize: labelFontSize)),
                      Text(_formatDuration(duration), style: TextStyle(color: Colors.grey, fontSize: labelFontSize)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMediaBox({
    required double width,
    required double height,
    required double subtitleFontSize,
    required bool hasAnySubtitle,
    String? currentImagePath,
    double borderRadius = 14,
  }) {
    final hasSlideshow = _slideshowPhotos.isNotEmpty;
    final safePhotoIndex = hasSlideshow ? (_photoIndex % _slideshowPhotos.length) : 0;
    final activePhotoPath = hasSlideshow ? _slideshowPhotos[safePhotoIndex] : null;
    final BoxFit imageFit = _fitCoverImages ? BoxFit.cover : BoxFit.contain;

    Widget mediaChild;
    if (hasSlideshow && activePhotoPath != null && File(activePhotoPath).existsSync()) {
      mediaChild = Container(
        color: Colors.black,
        child: Image.file(
          File(activePhotoPath),
          key: ValueKey(activePhotoPath),
          width: width,
          height: height,
          fit: imageFit,
        ),
      );
    } else if (_enableVideoPlayback && _videoController != null && _isVideoInitialized) {
      mediaChild = SizedBox(
        width: width,
        height: height,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        ),
      );
    } else if (currentImagePath != null && File(currentImagePath).existsSync()) {
      mediaChild = Container(
        color: Colors.black,
        child: Image.file(
          File(currentImagePath),
          width: width,
          height: height,
          fit: imageFit,
        ),
      );
    } else {
      mediaChild = Container(
        width: width,
        height: height,
        color: Colors.grey[800],
        child: const Icon(Icons.music_note, size: 70, color: Colors.white),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            mediaChild,
            if (hasSlideshow)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Foto ${safePhotoIndex + 1}/${_slideshowPhotos.length}',
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            _buildSubtitleOverlay(
              hasAnySubtitle: hasAnySubtitle,
              fontSize: subtitleFontSize,
              borderRadius: borderRadius,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFitToggleButton({bool compact = false}) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        backgroundColor: _fitCoverImages ? Colors.cyan.withValues(alpha: 0.25) : Colors.black54,
        foregroundColor: Colors.cyanAccent,
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
      ),
      icon: Icon(_fitCoverImages ? Icons.crop : Icons.fit_screen, size: compact ? 14 : 16),
      label: Text(
        _fitCoverImages ? 'Vullend' : 'Passend',
        style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.bold),
      ),
      onPressed: () {
        setState(() {
          _fitCoverImages = !_fitCoverImages;
        });
      },
    );
  }

  Widget _buildSlideshowControls() {
    if (_slideshowPhotos.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.cyanAccent),
          tooltip: 'Vorige foto',
          onPressed: () => _stepPhoto(-1),
        ),
        TextButton.icon(
          icon: Icon(
            _slideshowRunning ? Icons.pause : Icons.play_arrow,
            color: Colors.cyanAccent,
            size: 18,
          ),
          label: Text(
            _slideshowRunning ? 'Diashow pauzeren' : 'Diashow starten',
            style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
          ),
          onPressed: _toggleSlideshowRunning,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.cyanAccent),
          tooltip: 'Volgende foto',
          onPressed: () => _stepPhoto(1),
        ),
      ],
    );
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

    final hasAnySubtitle = currentSong.vttPath != null || currentSong.vttNlPath != null;
    final hasBothSubtitles = currentSong.vttPath != null && currentSong.vttNlPath != null;
    final hasSlideshow = _slideshowPhotos.isNotEmpty;

    final mediaTitle = _currentMediaItem?.title;
    final mediaArtist = _currentMediaItem?.artist;

    final String displayTitle = (mediaTitle != null && mediaTitle.isNotEmpty)
        ? mediaTitle
        : (widget.slideshowTitle ?? (hasSlideshow ? 'Diashow (_foto)' : ''));
    final String displayArtist = (mediaArtist != null && mediaArtist.isNotEmpty)
        ? mediaArtist
        : (hasSlideshow ? '${_slideshowPhotos.length} foto(s)' : 'Onbekende Artiest');

    if (_isFullscreen) {
      final screenSize = MediaQuery.of(context).size;
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: _buildMediaBox(
                  width: screenSize.width,
                  height: screenSize.height,
                  subtitleFontSize: 18,
                  hasAnySubtitle: hasAnySubtitle,
                  currentImagePath: currentImagePath,
                  borderRadius: 0,
                ),
              ),
              if (hasSlideshow)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: _buildSlideshowControls(),
                  ),
                ),
              Positioned(
                top: 16,
                right: 16,
                child: Row(
                  children: [
                    _buildFitToggleButton(),
                    const SizedBox(width: 8),
                    if (hasBothSubtitles)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            backgroundColor: _showNlSubtitles ? Colors.green : Colors.black54,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          icon: const Icon(Icons.translate, size: 15),
                          label: Text(
                            _showNlSubtitles ? 'NL' : 'Orig',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            setState(() {
                              _showNlSubtitles = !_showNlSubtitles;
                            });
                          },
                        ),
                      ),
                    CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                        tooltip: 'Sluit fullscreen',
                        onPressed: () => _setFullscreen(false),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
        actions: [
          _buildFitToggleButton(compact: true),
          IconButton(
            icon: Icon(
              _enableVideoPlayback ? Icons.videocam : Icons.videocam_off,
              color: _enableVideoPlayback ? Colors.green : Colors.grey,
            ),
            tooltip: _enableVideoPlayback ? 'Video Aan (MiraScreen)' : 'Poster Modus (AirPin Lite)',
            onPressed: () {
              setState(() {
                _enableVideoPlayback = !_enableVideoPlayback;
                _loadSongDetails();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Fullscreen poster / video / diashow',
            onPressed: () => _setFullscreen(true),
          ),
          if (hasBothSubtitles)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: _showNlSubtitles ? Colors.green : Colors.grey[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                icon: const Icon(Icons.translate, size: 14),
                label: Text(
                  _showNlSubtitles ? 'NL' : 'Orig',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  setState(() {
                    _showNlSubtitles = !_showNlSubtitles;
                  });
                },
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: isLandscape ? 4.0 : 12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLandscape) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 7,
                    child: Center(
                      child: _buildMediaBox(
                        width: 400,
                        height: 320,
                        subtitleFontSize: 14,
                        hasAnySubtitle: hasAnySubtitle,
                        currentImagePath: currentImagePath,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous),
                              iconSize: 36,
                              color: Colors.white,
                              onPressed: () => audioHandler.skipToPrevious(),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                              iconSize: 52,
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
                              iconSize: 36,
                              color: Colors.white,
                              onPressed: () => audioHandler.skipToNext(),
                            ),
                          ],
                        ),
                        if (hasSlideshow) _buildSlideshowControls(),
                        const SizedBox(height: 4),
                        SpectrumVisualizer(
                          isPlaying: _isPlaying,
                          positionStream: audioHandler.positionStream,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          displayTitle,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayArtist,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        _buildPositionSlider(horizontalPadding: 8.0, labelFontSize: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  return _buildMediaBox(
                    width: constraints.maxWidth,
                    height: 330,
                    subtitleFontSize: 15,
                    hasAnySubtitle: hasAnySubtitle,
                    currentImagePath: currentImagePath,
                  );
                },
              ),
              if (hasSlideshow) ...[
                const SizedBox(height: 6),
                _buildSlideshowControls(),
              ],
              const SizedBox(height: 12),
              SpectrumVisualizer(
                isPlaying: _isPlaying,
                positionStream: audioHandler.positionStream,
              ),
              const SizedBox(height: 12),
              Text(
                displayTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                displayArtist,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              _buildPositionSlider(horizontalPadding: 16.0, labelFontSize: 11),
              const SizedBox(height: 12),
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

