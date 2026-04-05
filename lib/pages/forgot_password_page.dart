import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'reset_password_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController correoController = TextEditingController();
  bool cargando = false;

  Future<void> enviarRecuperacion() async {
    String email = correoController.text.trim();
    if (email.isEmpty) {
      _mensaje("Por favor, ingresa tu correo", Colors.orange);
      return;
    }

    setState(() => cargando = true);

    try {
      var url = Uri.parse('https://carlossalinas.webpro1213.com/api/recuperar.php');

      // Enviamos la petición
      var response = await http.post(url, body: {
        'correo': email
      }).timeout(const Duration(seconds: 12));

      // DEBUG: Esto es vital para saber qué está pasando
      print("Status Code: ${response.statusCode}");
      print("Respuesta Raw: ${response.body}");

      // Intentamos decodificar el JSON
      final res = json.decode(response.body);

      if (res['status'] == 'success') {
        _mensaje("Código enviado con éxito", Colors.green);

        // Pequeña espera para que el usuario vea el mensaje verde
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResetPasswordPage(email: email),
            ),
          );
        });
      } else {
        _mensaje(res['message'] ?? "Error desconocido", Colors.red);
      }
    } catch (e) {
      print("Error detectado: $e");
      _mensaje("Error: El servidor no respondió correctamente", Colors.red);
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  void _mensaje(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2))
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("Recuperar Cuenta"),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black)
      ),
      backgroundColor: const Color(0xFFF2F2F2),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Icon(Icons.lock_reset, size: 100, color: Color(0xFF166088)),
            const SizedBox(height: 20),
            const Text("¿Olvidaste tu contraseña?",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text(
              "Enviaremos un correo con un código para restablecer tu acceso.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            TextField(
              controller: correoController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: "Tu correo electrónico",
                prefixIcon: const Icon(Icons.email),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none
                ),
              ),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: cargando ? null : enviarRecuperacion,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF166088),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                ),
                child: cargando
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Enviar Instrucciones", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}