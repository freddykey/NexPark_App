import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ResetPasswordPage extends StatefulWidget {
  final String email;
  const ResetPasswordPage({super.key, required this.email});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final TextEditingController codeController = TextEditingController();
  final TextEditingController passController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();
  bool cargando = false;

  Future<void> procesarCambio() async {
    if (codeController.text.length < 6) {
      _notificacion("Ingresa el código de 6 dígitos", Colors.orange);
      return;
    }
    if (passController.text != confirmController.text) {
      _notificacion("Las contraseñas no coinciden", Colors.red);
      return;
    }

    setState(() => cargando = true);

    try {

      var url = Uri.parse('https://carlossalinas.webpro1213.com/api/resetear_password.php');


      var response = await http.post(url, body: {
        'correo': widget.email,
        'codigo': codeController.text.trim(),
        'password': passController.text, // El PHP recibirá esto y lo guardará en 'contrasena'
      }).timeout(const Duration(seconds: 10));

      // DEBUG: Para ver qué dice el servidor exactamente
      print("Respuesta: ${response.body}");

      var res = json.decode(response.body);

      if (res['status'] == 'success') {
        _notificacion("¡Contraseña actualizada con éxito!", Colors.green);
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          // Regresa al login
          Navigator.of(context).popUntil((route) => route.isFirst);
        });
      } else {
        _notificacion(res['message'], Colors.red);
      }
    } catch (e) {
      print("Error en Flutter: $e");
      _notificacion("Error de conexión al procesar el cambio", Colors.red);
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  void _notificacion(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nueva Contraseña")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            const Text("Ingresa el código enviado a tu correo y tu nueva clave."),
            const SizedBox(height: 25),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30, letterSpacing: 8, fontWeight: FontWeight.bold),
              decoration: InputDecoration(hintText: "000000", counterText: "", filled: true, fillColor: Colors.white),
            ),
            const SizedBox(height: 20),
            _buildInput("Nueva Contraseña", Icons.lock, passController),
            const SizedBox(height: 15),
            _buildInput("Confirmar Contraseña", Icons.lock_outline, confirmController),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                onPressed: cargando ? null : procesarCambio,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF166088), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: cargando ? const CircularProgressIndicator() : const Text("Restablecer", style: TextStyle(color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInput(String hint, IconData icon, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
    );
  }
}