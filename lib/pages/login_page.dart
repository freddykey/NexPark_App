import 'package:flutter/material.dart';
import 'home_page.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {

  final TextEditingController correoController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  void validarLogin() {
    String correo = correoController.text;
    String pass = passwordController.text;

    if (correo == "bjmc879@gmail.com" && pass == "1987") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Correo o contraseña incorrectos"),
          backgroundColor: Colors.red,
        ),
      );
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

                Image.asset('assets/logo.png', height: 300),

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

                TextField(
                  controller: correoController,
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
                    child: const Text("Iniciar sesión"),
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