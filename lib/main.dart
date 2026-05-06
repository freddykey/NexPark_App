import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // IMPORTANTE
import 'pages/login_page.dart';
import 'pages/home_page.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // 1. INICIALIZAMOS LAS NOTIFICACIONES LOCALES DESDE EL ARRANQUE
  await HomePage.initNotificaciones();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  SharedPreferences prefs = await SharedPreferences.getInstance();
  bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NexPark',
      home: MainWrapper(isLoggedIn: isLoggedIn),
    );
  }
}

class MainWrapper extends StatefulWidget {
  final bool isLoggedIn;
  const MainWrapper({super.key, required this.isLoggedIn});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  String? miUsuarioId; // Variable para guardar tu ID

  @override
  void initState() {
    super.initState();
    _cargarUsuarioYConfigurarNotificaciones();
  }

  void _cargarUsuarioYConfigurarNotificaciones() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // Usamos la clave 'id_usuario_str' que acabamos de crear
    miUsuarioId = prefs.getString('id_usuario_str');

    FirebaseMessaging.instance.subscribeToTopic('nexpark_disponibilidad');

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // ID que viene desde el PHP (id_emisor)
      String? idEmisor = message.data['id_emisor'];

      // Si yo soy el emisor, ignoro la notificación
      if (idEmisor != null && idEmisor == miUsuarioId) {
        print("DEBUG: Notificación propia bloqueada (ID: $idEmisor)");
        return;
      }

      if (message.notification != null) {
        HomePage.notificar(message.notification!.body ?? "Aviso de NexPark");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.isLoggedIn ? const HomePage() : const LoginPage();
  }
}