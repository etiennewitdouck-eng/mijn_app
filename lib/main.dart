import 'package:flutter/material.dart';
import 'package:flutter_carplay/flutter_carplay.io.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP3 Player CarPlay',
      theme: ThemeData(primarySwatch: BlueThemeColor),
      home: const MainScreen(),
    );
  }
}

// Een eenvoudige kleurdefinitie om fouten te voorkomen
const MaterialColor BlueThemeColor = MaterialColor(
  0xFF2196F3,
  <int, Color>{
    50: Color(0xFFE3F2FD),
    100: Color(0xFFBBDEFB),
    200: Color(0xFF90CAF9),
    300: Color(0xFF64B5F6),
    400: Color(0xFF42A5F5),
    500: Color(0xFF2196F3),
    600: Color(0xFF1E88E5),
    700: Color(0xFF1976D2),
    800: Color(0xFF1565C0),
    900: Color(0xFF0D47A1),
  },
);

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  void initState() {
    super.initState();
    // Initialiseer CarPlay direct bij het starten van het scherm
    _setupCarPlayRootTemplate();
  }

  void _setupCarPlayRootTemplate() {
    // Bouw de lijst met items voor het autoscherm van de Kia Ceed
    final CPListSection section = CPListSection(
      items: [
        CPListItem(
          text: 'Mijn Muzieklijst',
          detailText: 'Tik om nummers te bekijken',
          onPress: (complete, self) {
            // Actie wanneer er op het autoscherm geklikt wordt
            debugPrint("CarPlay item geklikt!");
            // Belangrijk: roep altijd complete() aan om de laadstaat te stoppen
            complete();
          },
        ),
      ],
    );

    final CPListTemplate carPlayTemplate = CPListTemplate(
      title: 'MP3 Player',
      sections: [section],
    );

    // Stel de root template in via de juiste FLTCarPlay interface
    FLTCarPlay.setRootTemplate(
      rootTemplate: carPlayTemplate,
      animated: true,
    );
  }

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
                'Verbind je iPhone met de Kia Ceed. Het CarPlay-scherm laadt automatisch de muziekinterface.',
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
