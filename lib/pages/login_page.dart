import 'package:flutter/material.dart';
import 'home_page.dart';
import 'register_page.dart';
import 'forgot_password_page.dart'; // <--- 1. AGREGADO
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController correoController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '568559107230-guucpilvpiobkunpt41sohm1imrklec1.apps.googleusercontent.com',
    scopes: ['email'],
  );

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> loginConGoogle() async {
    try {
      await _googleSignIn.signOut();
      final GoogleSignInAccount? account = await _googleSignIn.signIn();

      if (account != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        var url = Uri.parse('https://carlossalinas.webpro1213.com/api/login_google.php');

        var response = await http.post(url, body: {
          'email': account.email,
          'nombre': account.displayName ?? "Usuario NexPark",
          'google_id': account.id,
        }).timeout(const Duration(seconds: 10));

        if (!mounted) return;
        Navigator.pop(context);

        if (response.body.trim().isEmpty) {
          _mostrarError("El servidor respondió vacío.");
          return;
        }

        try {
          var res = json.decode(response.body);
          if (res['status'] == 'success') {
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setBool('isLoggedIn', true);

            var u = res['user'];
            // --- CORRECCIÓN AQUÍ: Captura dinámica del ID ---
            var idRaw = u['id'] ?? u['id_usuario'];
            await prefs.setInt('id_usuario', int.parse(idRaw.toString()));

            await prefs.setString('nombre_usuario', u['nombre']);
            await prefs.setString('correo_usuario', account.email);
            await prefs.setString('foto_usuario', account.photoUrl ?? "");

            // --- AGREGADO: Guardar datos extra para persistencia ---
            await prefs.setString('apellido_paterno', u['apellido_paterno']?.toString() ?? "");
            await prefs.setString('apellido_materno', u['apellido_materno']?.toString() ?? "");
            await prefs.setString('telefono_usuario', u['telefono']?.toString() ?? "");
            await prefs.setString('saldo_usuario', u['saldo']?.toString() ?? "0");
            await prefs.setString('fecha_registro', u['fecha_registro']?.toString() ?? "");

            if (!mounted) return;
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
          } else {
            _mostrarError(res['message'] ?? "Error en el servidor");
          }
        } catch (e) {
          _mostrarError("Error de formato: ${response.body}");
        }
      }
    } catch (error) {
      _mostrarError("Error de conexión con Google: $error");
    }
  }

  Future<void> validarLogin() async {
    String correo = correoController.text.trim();
    String pass = passwordController.text.trim();

    if (correo.isEmpty || pass.isEmpty) {
      _mostrarError("Por favor, llena todos los campos");
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      var url = Uri.parse('https://carlossalinas.webpro1213.com/api/login.php');
      var response = await http.post(url, body: {
        'correo': correo,
        'password': pass,
      }).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      Navigator.pop(context);

      if (response.body.isEmpty) {
        _mostrarError("Respuesta vacía del servidor.");
        return;
      }

      var res = json.decode(response.body);
      if (res['status'] == 'success') {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);

        var u = res['user'];
        // --- CORRECCIÓN AQUÍ: Captura dinámica del ID ---
        var idRaw = u['id'] ?? u['id_usuario'];
        await prefs.setInt('id_usuario', int.parse(idRaw.toString()));

        await prefs.setString('nombre_usuario', u['nombre']);
        await prefs.setString('correo_usuario', correo);

        // --- AGREGADO: Guardar datos extra para persistencia ---
        await prefs.setString('apellido_paterno', u['apellido_paterno']?.toString() ?? "");
        await prefs.setString('apellido_materno', u['apellido_materno']?.toString() ?? "");
        await prefs.setString('telefono_usuario', u['telefono']?.toString() ?? "");
        await prefs.setString('saldo_usuario', u['saldo']?.toString() ?? "0");
        await prefs.setString('fecha_registro', u['fecha_registro']?.toString() ?? "");

        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
      } else {
        _mostrarError(res['message'] ?? "Correo o contraseña incorrectos");
      }
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      _mostrarError("Error de conexión: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(25.0),
            child: Column(
              children: [
                Image.asset('assets/logo.png', height: 150),
                const Text("Encuentra. Reserva. Aparca.", style: TextStyle(color: Color(0xFF828282))),
                const SizedBox(height: 40),
                const Text("Bienvenido", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF166088))),
                const SizedBox(height: 10),
                const Text("Inicia sesión para continuar", style: TextStyle(color: Color(0xFF828282))),
                const SizedBox(height: 30),

                TextField(
                  controller: correoController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: "Correo",
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Contraseña",
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.lock),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),

                // --- 2. BOTÓN AGREGADO AQUÍ ---
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordPage())),
                    child: const Text("¿Olvidaste tu contraseña?", style: TextStyle(color: Color(0xFF166088), fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: validarLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF166088),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text("Iniciar Sesión", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 15),
                const Text("O inicia con", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 15),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: loginConGoogle,
                    icon: Image.network(
                      'https://pngimg.com/uploads/google/google_PNG19635.png',
                      height: 24,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.account_circle),
                    ),
                    label: const Text("Continuar con Google", style: TextStyle(color: Colors.black87)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterPage())),
                  child: const Text("¿No tienes cuenta? Regístrate", style: TextStyle(color: Color(0xFF4A6FA5))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}