import 'package:flutter/material.dart';
import 'login_page.dart';

class UserAccount extends StatelessWidget {
  const UserAccount({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mi Cuenta"),
        centerTitle: true,
        // ESTO QUITA LA FLECHA DE REGRESO
        automaticallyImplyLeading: false,
        // ESTO AGREGA EL BOTÓN DEL MENÚ (HAMBURGUESA) MANUALMENTE
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),

      // DEBES AGREGAR EL MISMO DRAWER QUE TIENES EN HOMEPAGE
      drawer: Drawer(
        child: ListView(
          children: [
            Container(
              height: 120,
              color: Colors.black26,
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Image.asset('assets/logo.png', height: 80),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text("Inicio"),
              onTap: () {
                // Para volver al inicio sin acumular pantallas
                Navigator.pushReplacementNamed(context, '/');
                // O simplemente:
                Navigator.pop(context); // Si vienes de un push simple
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text("Cuenta"),
              onTap: () {
                Navigator.pop(context); // Solo cierra el drawer porque ya estás aquí
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text("Cerrar sesión"),
              onTap: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false,
                );
              },
            ),
          ],
        ),
      ),

      body: const Center(
        child: Text("Información del Usuario de NexPark"),
      ),
    );
  }
}