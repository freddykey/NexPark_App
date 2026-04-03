import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // DEFINIR CONTROLADORES PARA CAPTURAR EL TEXTO
  final TextEditingController nombreController = TextEditingController();
  final TextEditingController paternoController = TextEditingController();
  final TextEditingController maternoController = TextEditingController();
  final TextEditingController correoController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController telefonoController = TextEditingController();

  // FUNCION PARA ENVIAR LOS DATOS AL HOSTING
  Future<void> registrarUsuario() async {
    // VALIDACIÓN
    if (nombreController.text.isEmpty || correoController.text.isEmpty || paternoController.text.isEmpty ||
        maternoController.text.isEmpty || passwordController.text.isEmpty || telefonoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor rellena todos los campos")),
      );
      return;
    }

    // METODO DE CARGA
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {

      var url = Uri.parse('https://carlossalinas.webpro1213.com/api/registrar.php');

      var response = await http.post(url, body: {
        'nombre': nombreController.text,
        'paterno': paternoController.text,
        'materno': maternoController.text,
        'correo': correoController.text,
        'telefono': telefonoController.text,
        'password': passwordController.text,
      });

      if (!mounted) return;
      Navigator.pop(context); // TERMINA DE CARGAR QUITANDO LA VISUALIZACION PARA EL USUARIO QUE ESTA CARGANDO

      var res = json.decode(response.body);

      if (res['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("¡Registro exitoso! Ya puedes iniciar sesión")),
        );
        Navigator.pop(context); // REGRESA AL LOGIN
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${res['message']}")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error de conexión con el servidor")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Crear Cuenta"),
        backgroundColor: const Color(0xFFF2F2F2),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF166088)),
      ),
      backgroundColor: const Color(0xFFF2F2F2),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            children: [
              const Icon(Icons.person_add, size: 100, color: Color(0xFF166088)),
              const SizedBox(height: 20),
              const Text(
                "Registro NexPark",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF166088),
                ),
              ),
              const SizedBox(height: 30),

              // CAMPO NOMBRE
              _buildTextField("Nombre completo", Icons.person, controller: nombreController),
              const SizedBox(height: 15),

              // CAMPOS APELLIDOS
              Row(
                children: [
                  Expanded(
                    child: _buildTextField("A. Paterno", Icons.person_outline, controller: paternoController),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField("A. Materno", Icons.person_outline, controller: maternoController),
                  ),
                ],
              ),

              const SizedBox(height: 15),
              // CAMPO CORREO
              _buildTextField("Correo electrónico", Icons.email, controller: correoController),
              const SizedBox(height: 15),

              // CAMPO CONTRASEÑA
              _buildTextField("Contraseña", Icons.lock, obscure: true, controller: passwordController),
              const SizedBox(height: 15),

              // CAMPO NUMERO DE TELEFONO
              _buildTextField(
                "Número de Teléfono",
                Icons.phone,
                keyboardType: TextInputType.phone,
                controller: telefonoController,
              ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: registrarUsuario,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEB5757),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text("Registrarse", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildTextField(String hint, IconData icon, {
    required TextEditingController controller,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}