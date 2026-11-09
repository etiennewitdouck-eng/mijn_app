import 'dart:io'; // Nodig voor de 'File' klasse
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart'; // Nodig voor getTemporaryDirectory()

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
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
  late final AudioPlayer _audioPlayer;
  List<String> _playlist = [];
  
  // HIER IS DE ONTBRAKENDE VARIABELE TOEGEVOEGD:
  final Map<String, String> _localImagePaths = {};
  
  bool _isLoading = true;
  int? _currentIndex;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _loadSongsFromAssets();

    _audioPlayer.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadSongsFromAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets();

      // Filter alle MP3's
      final mp3Files = assets
          .where((String key) => key.startsWith('assets/mijnliedjes/') && key.toLowerCase().endsWith('.mp3'))
          .toList();

      final tempDir = await getTemporaryDirectory();
      for (var songPath in mp3Files) {
        final baseName = songPath.split('/').last.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
        final imageAssetPath = 'assets/mijnliedjes/$baseName.jpg';

        try {
          final byteData = await rootBundle.load(imageAssetPath);
          final file = File('${tempDir.path}/$baseName.jpg');
          await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
          
          _localImagePaths[songPath] = file.path;
          debugPrint("SUCCES: Afbeelding gekopieerd voor $baseName -> ${file.path}");
        } catch (e) {
          debugPrint("FOUT: Kon afbeelding niet vinden voor $imageAssetPath ($e)");
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
      
      // Bepaal de bestandsnaam zonder extensie (bijv. "liedje1" uit "assets/mijnliedjes/liedje1.mp3")
      final baseName = songPath.split('/').last.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
      final imagePath = 'assets/mijnliedjes/$baseName.jpg';

      // Laad en speel het liedje af met metadata voor CarPlay
      await _audioPlayer.setAudioSource(
        AudioSource.asset(
          songPath,
          tag: MediaItem(
            id: songPath,
            album: 'Mijn MP3 Map',
            title: baseName,
            artist: 'Onbekende Artiest',
            // Hier koppelen we de afbeelding voor CarPlay / het scherm
            artUri: Uri.parse('asset:///$imagePath'),
          ),
        ),
      );

      await _audioPlayer.play();
      setState(() {
        _currentIndex = index;
      });
    } catch (e) {
      debugPrint("Fout bij afspelen: $e");
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

