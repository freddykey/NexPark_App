import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'home_page.dart';
import 'user_account.dart';
import 'login_page.dart';
import 'pago_webview.dart';

class RecargaPage extends StatefulWidget {
  const RecargaPage({super.key});

  @override
  State<RecargaPage> createState() => _RecargaPageState();
}

class _RecargaPageState extends State<RecargaPage> {
  final TextEditingController montoController = TextEditingController();
  bool cargando = false;

  // Variables para el Drawer
  String nombre = "Cargando...";
  String correo = "...";
  String foto = "";

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
  }

  // Cargar datos para que el Drawer no salga vacío
  Future<void> _cargarDatosUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      nombre = prefs.getString('nombre_usuario') ?? "Usuario NexPark";
      correo = prefs.getString('correo_usuario') ?? "usuario@correo.com";
      foto = prefs.getString('foto_usuario') ?? "";
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false
    );
  }

  void seleccionarMonto(String valor) {
    setState(() {
      montoController.text = valor;
    });
  }

  Future<void> iniciarPago() async {
    if (montoController.text.isEmpty || double.parse(montoController.text) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ingresa un monto válido")));
      return;
    }

    setState(() => cargando = true);
    final prefs = await SharedPreferences.getInstance();
    int idUsuario = prefs.getInt('id_usuario') ?? 0;

    try {
      var response = await http.post(
        Uri.parse('https://carlossalinas.webpro1213.com/api/crear_preferencia.php'),
        body: {
          'id_usuario': idUsuario.toString(),
          'monto': montoController.text,
          'tipo_flujo': 'recarga', // <--- ESTA LÍNEA ES LA CLAVE
        },
      );

      var res = json.decode(response.body);
      if (res['status'] == 'success') {
        if (!mounted) return;

        final resultado = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PagoWebView(url: res['url_pago']),
          ),
        );

        if (resultado == "success") {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("¡Recarga procesada! Tu saldo se actualizará en breve."), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error al conectar con la pasarela")));
    } finally {
      setState(() => cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text("Recargar Saldo", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF166088),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // --- DRAWER AGREGADO ---
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF166088)),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                child: foto.isEmpty
                    ? Text(nombre[0].toUpperCase(), style: const TextStyle(fontSize: 40, color: Color(0xFF166088)))
                    : null,
              ),
              accountName: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: Text(correo),
            ),
            ListTile(leading: const Icon(Icons.home, color: Color(0xFF166088)), title: const Text("Inicio"), onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()))),
            ListTile(leading: const Icon(Icons.person, color: Color(0xFF166088)), title: const Text("Cuenta"), onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UserAccount()))),
            ListTile(leading: const Icon(Icons.add_card, color: Color(0xFF166088)), title: const Text("Recargar Saldo"), onTap: () => Navigator.pop(context)),
            const Spacer(),
            const Divider(indent: 20, endIndent: 20),
            ListTile(leading: const Icon(Icons.logout_rounded, color: Color(0xFFEB5757)), title: const Text("Cerrar sesión", style: TextStyle(color: Color(0xFFEB5757), fontWeight: FontWeight.bold),), onTap: _logout,),

            const Padding(padding: EdgeInsets.all(20.0), child: Text("NexPark alpha-v0.4.2", style: TextStyle(color: Colors.grey, fontSize: 12),),),
            const SizedBox(height: 10),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 80, color: Color(0xFF166088)),
            const SizedBox(height: 10),
            const Text("¿Cuánto deseas recargar?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF166088))),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _montoBoton("50"),
                _montoBoton("100"),
                _montoBoton("200"),
              ],
            ),
            const SizedBox(height: 25),
            TextField(
              controller: montoController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Monto personalizado",
                prefixIcon: const Icon(Icons.attach_money),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: cargando ? null : iniciarPago,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27AE60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: cargando
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Continuar al Pago", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            const Text("Seguro con Mercado Pago", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _montoBoton(String valor) {
    return ActionChip(
      label: Text("\$ $valor", style: const TextStyle(fontWeight: FontWeight.bold)),
      onPressed: () => seleccionarMonto(valor),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFF166088))),
    );
  }
}