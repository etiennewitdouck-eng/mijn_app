import 'dart:io'; // Nodig voor de 'File' klasse
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart'; // Nodig voor getApplicationDocumentsDirectory()

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
  
  // Opslagplaats voor de gekopieerde lokale afbeeldingspaden (voor CarPlay/posters)
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

      // Filter alle MP3's uit assets/mijnliedjes/
      final mp3Files = assets
          .where((String key) => key.startsWith('assets/mijnliedjes/') && key.toLowerCase().endsWith('.mp3'))
          .toList();

      // Opslaan in de Documenten-map zodat CarPlay en het systeem erbij kunnen
      final appDocDir = await getApplicationDocumentsDirectory();
      
      for (var songPath in mp3Files) {
        final baseName = songPath.split('/').last.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
        final imageAssetPath = 'assets/mijnliedjes/$baseName.jpg';

        try {
          final byteData = await rootBundle.load(imageAssetPath);
          final file = File('${appDocDir.path}/$baseName.jpg');
          await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
          
          _localImagePaths[songPath] = file.path;
          debugPrint("SUCCES: Afbeelding opgeslagen voor $baseName -> ${file.path}");
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
      final baseName = songPath.split('/').last.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
      
      // Haal het lokale pad op uit onze opgeslagen lijst
      final localImagePath = _localImagePaths[songPath];
      
      // VEILIGHEIDSCHECK OP SCHERM: Dit toont direct een melding op je iPhone
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Afspelen: $baseName | Afbeelding bekend: ${localImagePath != null}'),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.blueGrey,
          ),
        );
      }

      Uri? artUri;
      if (localImagePath != null) {
        final imageFile = File(localImagePath);
        if (await imageFile.exists()) {
          artUri = imageFile.uri; // Dit is de meest betrouwbare manier voor iOS en CarPlay
          debugPrint("KARAKTER CHECK: Gelukt om file uri te maken: $artUri");
        }
      }

      // Laad het liedje met de metadata
      await _audioPlayer.setAudioSource(
        AudioSource.asset(
          songPath,
          tag: MediaItem(
            id: songPath,
            album: 'Mijn MP3 Map',
            title: baseName,
            artist: 'Onbekende Artiest',
            artUri: artUri,
          ),
        ),
      );

      await _audioPlayer.play();
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
