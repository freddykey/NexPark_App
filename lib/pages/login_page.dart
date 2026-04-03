import 'package:flutter/material.dart';
import 'home_page.dart';
import 'register_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {

  final TextEditingController correoController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // FUNCIÓN AUXILIAR PARA MOSTRAR ERRORES (Evita que la pantalla se ponga negra al fallar)
  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // FUNCION PARA VALIDAR LA CONTRA EN EL SERVIDOR
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
      // RECUERDA: Usar la URL pública de tu dominio, no la del administrador de archivos
      var url = Uri.parse('https://carlossalinas.webpro1213.com/api/login.php');

      var response = await http.post(url, body: {
        'correo': correo,
        'password': pass,
      }).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      Navigator.pop(context);

      // VALIDACIÓN DE RESPUESTA EXITOSA DEL SERVIDOR
      if (response.statusCode == 200) {
        var res = json.decode(response.body);

        if (res['status'] == 'success') {
          // SE USA ESTE IMPORT PARA QUE LA APP RECUERDE INGRESOS FUTUROS MEDIANTE LA ID DEL USUARIO
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isLoggedIn', true);
          await prefs.setInt('id_usuario', int.parse(res['user']['id'].toString()));
          await prefs.setString('nombre_usuario', res['user']['nombre']);

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        } else {
          // ERROR SI LA CREDENCIALES NO EXISTEN O ESTAN MAL
          _mostrarError(res['message'] ?? "Correo o contraseña incorrectos");
        }
      } else {
        // ERROR SI EL ARCHIVO PHP FALLO O NO SE ENCONTRO
        _mostrarError("Error en el servidor: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _mostrarError("Error de conexión con el servidor");
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

                const Text(
                  "Encuentra. Reserva. Aparca.",
                  style: TextStyle(color: Color(0xFF828282)),
                ),

                const SizedBox(height: 40),

                const Text(
                  "Bienvenido",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF166088),
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  "Inicia sesión para continuar",
                  style: TextStyle(color: Color(0xFF828282)),
                ),

                const SizedBox(height: 30),

                // CAMPO CORREO
                TextField(
                  controller: correoController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: "Correo",
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                // CAMPO CONTRASEÑA
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Contraseña",
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.lock),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: validarLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEB5757),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                        "Iniciar Sesión",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const RegisterPage()),
                    );
                  },
                  child: const Text(
                    "¿No tienes cuenta? Regístrate",
                    style: TextStyle(color: Color(0xFF4A6FA5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}