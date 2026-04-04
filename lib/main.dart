import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';

void main() async {
  // WIDGET PARA QUE CARGUE LOS DATOS ANTES DE LEER SHAREDPREFERENCES
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  // ABRE LA LIBRERIA DE NOTAS DEL CELULAR
  SharedPreferences prefs = await SharedPreferences.getInstance();

  // SE REVISA SI EL USUARIO YA INICIO SESION PREVIAMENTE

  bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;//POR DEFECTO ESTA EN FALSE, POR SI NO EXISTE EL DATO


  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;

  // CONSTRUCTOR QUE RECIBE SI EL USUARIO YA INGRESO O NO
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NexPark',
      // DEFINE EL INICIO
      home: isLoggedIn ? const HomePage() : const LoginPage(),//SI ES TRUE VA DIRECTAMENTE A LA PAGE HomePage, SI NO VA A LoginPage
    );
  }
}