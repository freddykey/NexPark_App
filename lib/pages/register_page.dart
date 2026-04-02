import 'package:flutter/material.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

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

              // Campo Nombre
              _buildTextField("Nombre completo", Icons.person),
              const SizedBox(height: 15),

              // Campo Correo
              _buildTextField("Correo electrónico", Icons.email),
              const SizedBox(height: 15),

              // Campo Contraseña
              _buildTextField("Contraseña", Icons.lock, obscure: true),
              const SizedBox(height: 15),
              // Campo Numero de telefonoo
              _buildTextField("Número de Teléfono", Icons.phone, keyboardType: TextInputType.phone ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    // Lógica para registrar usuario
                    Navigator.pop(context); // Regresa al login tras registrarse
                  },
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

  // PARA GLOBALIZAR LA FORMA PARA INGRESAR DATOS
  Widget _buildTextField(String hint, IconData icon, {bool obscure = false, TextInputType keyboardType = TextInputType.text}) {
    return TextField(
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