import 'package:flutter/material.dart';
import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Let op de kleine 'p': FlutterCarplay i.p.v. FlutterCarPlay
  FlutterCarplay.setRootTemplate(
    rootTemplate: CPListTemplate(
      title: 'MP3 Player',
      sections: [
        CPListSection(
          items: [
            CPListItem(
              text: 'Mijn Muzieklijst',
              detailText: 'Tik om nummers te bekijken',
              onPress: (complete, self) async {
                complete();
              },
            ),
          ],
        ),
      ],
    ),
    animated: true,
  );

  runApp(const MyApp());
}



class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP3 Player CarPlay',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MP3 Player - CarPlay actief'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.directions_car, size: 80, color: Colors.blue),
              SizedBox(height: 20),
              Text(
                'Klaar voor Apple CarPlay!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'Verbind je iPhone met de Kia Ceed.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

