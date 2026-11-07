import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const DynamicPlaylistApp());
}

class DynamicPlaylistApp extends StatelessWidget {
  const DynamicPlaylistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const DynamicPlaylistScreen(),
    );
  }
}

class DynamicPlaylistScreen extends StatefulWidget {
  const DynamicPlaylistScreen({super.key});

  @override
  State<DynamicPlaylistScreen> createState() => _DynamicPlaylistScreenState();
}

class _DynamicPlaylistScreenState extends State<DynamicPlaylistScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  List<String> _playlist = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadSongsFromAssets();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // Automatisch alle .mp3 bestanden uit de assets/mijnliedjes/ map ophalen
  Future<void> _loadSongsFromAssets() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      // Filter bestanden die in de map assets/mijnliedjes/ staan en eindigen op .mp3
      final mp3Files = manifestMap.keys
          .where((String key) => key.startsWith('assets/mijnliedjes/') && key.toLowerCase().endsWith('.mp3'))
          .toList();

      setState(() {
        _playlist = mp3Files;
        _isLoading = false;
      });

      if (_playlist.isNotEmpty) {
        debugPrint("Gevonden liedjes: $_playlist");
      }
    } catch (e) {
      debugPrint("Fout bij laden van assets: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Speel een specifiek nummer af op basis van de index
  Future<void> _playSong(int index) async {
    if (_playlist.isEmpty) return;
    try {
      String fullPath = _playlist[index];
      // Haal de bestandsnaam op (bijv. 'assets/mijnliedjes/liedje.mp3' -> 'mijnliedjes/liedje.mp3' voor AssetSource)
      String relativePath = fullPath.replaceFirst('assets/', '');

      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(relativePath));
      
      setState(() {
        _currentIndex = index;
        _isPlaying = true;
      });
    } catch (e) {
      debugPrint("Fout bij afspelen: $e");
    }
  }

  // Pauzeer of hervat
  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      setState(() => _isPlaying = false);
    } else {
      if (_audioPlayer.state == PlayerState.paused) {
        await _audioPlayer.resume();
        setState(() => _isPlaying = true);
      } else {
        if (_playlist.isNotEmpty) {
          await _playSong(_currentIndex);
        }
      }
    }
  }

  // Volgend liedje
  void _nextSong() {
    if (_playlist.isEmpty) return;
    int nextIndex = (_currentIndex + 1) % _playlist.length;
    _playSong(nextIndex);
  }

  // Vorig liedje
  void _prevSong() {
    if (_playlist.isEmpty) return;
    int prevIndex = (_currentIndex - 1 < 0) ? _playlist.length - 1 : _currentIndex - 1;
    _playSong(prevIndex);
  }

  @override
  Widget build(BuildContext context) {
    // Schone weergave van de songtitel (zonder pad en .mp3 extensie)
    String currentDisplayName = _playlist.isNotEmpty 
        ? _playlist[_currentIndex].split('/').last.replaceAll('.mp3', '') 
        : "Geen muziek gevonden";

    return Scaffold(
      appBar: AppBar(title: const Text('Mijn MP3 Afspeellijst')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlist.isEmpty
              ? const Center(child: Text("Geen MP3-bestanden gevonden in assets/mijnliedjes/!"))
              : Column(
                  children: [
                    // Bovenkant: Huidig nummer info
                    Container(
                      padding: const EdgeInsets.all(20),
                      color: Colors.blue.shade50,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.music_note, size: 40, color: Colors.blue),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Text(
                              currentDisplayName,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Midden: Afspeelbediening knoppen
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous, size: 40),
                            onPressed: _prevSong,
                          ),
                          const SizedBox(width: 20),
                          IconButton(
                            icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 64),
                            color: Colors.blue,
                            onPressed: _togglePlayPause,
                          ),
                          const SizedBox(width: 20),
                          IconButton(
                            icon: const Icon(Icons.skip_next, size: 40),
                            onPressed: _nextSong,
                          ),
                        ],
                      ),
                    ),
                    
                    const Divider(),

                    // Onderkant: Automatisch gegenereerde afspeellijst uit de map
                    Expanded(
                      child: ListView.builder(
                        itemCount: _playlist.length,
                        itemBuilder: (context, index) {
                          bool isSelected = index == _currentIndex;
                          String songTitle = _playlist[index].split('/').last.replaceAll('.mp3', '');
                          
                          return ListTile(
                            leading: Icon(
                              isSelected ? Icons.play_arrow : Icons.audiotrack,
                              color: isSelected ? Colors.blue : Colors.grey,
                            ),
                            title: Text(
                              songTitle,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Colors.blue : Colors.black,
                              ),
                            ),
                            onTap: () => _playSong(index),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
