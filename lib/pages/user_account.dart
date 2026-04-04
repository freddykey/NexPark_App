import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';

class UserAccount extends StatefulWidget {
  const UserAccount({super.key});

  @override
  State<UserAccount> createState() => _UserAccountState();
}

class _UserAccountState extends State<UserAccount> {
  // --- VARIABLES DE LÓGICA ---
  String nombre = "Cargando...";
  String correo = "...";
  String foto = "";
  String apellidoP = "";
  String apellidoM = "";
  String telefono = "";
  String saldo = "0";
  String fecha = ""; // Se guardará el formato legible aquí
  String vehiculos = "0";
  int idUsuario = 0;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  // --- CARGAR DATOS DESDE LOCAL Y API ---
  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    idUsuario = prefs.getInt('id_usuario') ?? 0;

    setState(() {
      nombre = prefs.getString('nombre_usuario') ?? "Usuario NexPark";
      correo = prefs.getString('correo_usuario') ?? "usuario@correo.com";
      foto = prefs.getString('foto_usuario') ?? "";
    });

    try {
      var url = Uri.parse('http://carlossalinas.webpro1213.com/api/get_user_data.php');
      var response = await http.post(url, body: {
        'id_usuario': idUsuario.toString(),
      });

      var res = json.decode(response.body);

      if (res['status'] == 'success') {
        // Formatear fecha de YYYY-MM-DD HH:MM:SS a DD/MM/YYYY
        String rawFecha = res['user']['fecha_registro'] ?? "";
        String fechaFormateada = "...";

        if (rawFecha.isNotEmpty && rawFecha.contains(" ")) {
          List<String> partes = rawFecha.split(" ")[0].split("-");
          if (partes.length == 3) {
            fechaFormateada = "${partes[2]}/${partes[1]}/${partes[0]}";
          }
        }

        setState(() {
          apellidoP = res['user']['apellido_p'] ?? "";
          apellidoM = res['user']['apellido_m'] ?? "";
          telefono = res['user']['telefono'] ?? "";
          saldo = res['user']['saldo'] ?? "0";
          fecha = fechaFormateada;
          vehiculos = res['vehiculos']?.toString() ?? "0";
          foto = res['user']['foto'] ?? foto;
        });
      }
    } catch (e) {
      debugPrint("Error al conectar con la API: $e");
    }
  }

  // --- FUNCIÓN PARA SUBIR FOTO ---
  Future<void> _cambiarFoto() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

    if (image != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Actualizando foto...")));

      try {
        var request = http.MultipartRequest('POST',
            Uri.parse('http://carlossalinas.webpro1213.com/api/update_photo.php'));

        request.fields['id_usuario'] = idUsuario.toString();
        request.files.add(await http.MultipartFile.fromPath('image', image.path));

        var response = await request.send();

        if (response.statusCode == 200) {
          var resData = await response.stream.bytesToString();
          var res = json.decode(resData);

          if (res['status'] == 'success') {
            setState(() {
              // Agregamos timestamp para evitar caché de imagen
              foto = "${res['new_url']}?t=${DateTime.now().millisecondsSinceEpoch}";
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('foto_usuario', foto);

            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Foto de perfil actualizada")));
          }
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error al subir imagen")));
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  void _editarUsuario() {
    final nombreCtrl = TextEditingController(text: nombre);
    final apCtrl = TextEditingController(text: apellidoP);
    final amCtrl = TextEditingController(text: apellidoM);
    final telCtrl = TextEditingController(text: telefono);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Editar datos"),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: "Nombre")),
              TextField(controller: apCtrl, decoration: const InputDecoration(labelText: "Apellido Paterno")),
              TextField(controller: amCtrl, decoration: const InputDecoration(labelText: "Apellido Materno")),
              TextField(controller: telCtrl, decoration: const InputDecoration(labelText: "Teléfono")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              var url = Uri.parse('http://carlossalinas.webpro1213.com/api/update_user.php');
              await http.post(url, body: {
                'id_usuario': idUsuario.toString(),
                'nombre': nombreCtrl.text,
                'apellido_p': apCtrl.text,
                'apellido_m': amCtrl.text,
                'telefono': telCtrl.text,
              });
              _cargarDatos();
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  void _cambiarPassword() {
    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Cambiar contraseña"),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: "Nueva contraseña"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              var url = Uri.parse('http://carlossalinas.webpro1213.com/api/update_password.php');
              await http.post(url, body: {
                'id_usuario': idUsuario.toString(),
                'password': passCtrl.text,
              });
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Contraseña actualizada")));
            },
            child: const Text("Guardar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text("Mi Cuenta", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF166088),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF166088)),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                child: foto.isEmpty ? Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : "U", style: const TextStyle(fontSize: 40, color: Color(0xFF166088))) : null,
              ),
              accountName: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: Text(correo),
            ),
            ListTile(
              leading: const Icon(Icons.home, color: Color(0xFF166088)),
              title: const Text("Inicio"),
              onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage())),
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Color(0xFF166088)),
              title: const Text("Cuenta"),
              onTap: () => Navigator.pop(context),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Cerrar sesión", style: TextStyle(color: Colors.red)),
              onTap: _logout,
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 100,
                  decoration: const BoxDecoration(
                    color: Color(0xFF166088),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
                  ),
                ),
                Positioned(
                  top: 30,
                  child: GestureDetector(
                    onTap: _cambiarFoto,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.white,
                          child: CircleAvatar(
                            radius: 55,
                            backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                            backgroundColor: Colors.grey[200],
                            child: foto.isEmpty ? const Icon(Icons.person, size: 70, color: Color(0xFF166088)) : null,
                          ),
                        ),
                        const Positioned(
                          bottom: 5,
                          right: 5,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: Color(0xFF166088),
                            child: Icon(Icons.camera_alt, size: 18, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 100),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                children: [
                  Text(
                    "$nombre $apellidoP $apellidoM",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF166088)),
                  ),
                  Text("Saldo Actual: \$ $saldo", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),

                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5)),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildInfoTile(Icons.email_outlined, "Correo", correo),
                        const Divider(),
                        _buildInfoTile(Icons.phone_android_outlined, "Teléfono", telefono.isEmpty ? "No registrado" : telefono),
                        const Divider(),
                        _buildInfoTile(Icons.directions_car_outlined, "Vehículos", "$vehiculos Registrados"),
                        const Divider(),
                        // AQUÍ SE MUESTRA LA FECHA FORMATEADA
                        _buildInfoTile(Icons.calendar_today_outlined, "Miembro desde", fecha),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _editarUsuario,
                      icon: const Icon(Icons.edit, size: 20),
                      label: const Text("Editar Información"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF166088),
                        side: const BorderSide(color: Color(0xFF166088)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: TextButton.icon(
                      onPressed: _cambiarPassword,
                      icon: const Icon(Icons.lock_outline, size: 20, color: Colors.red),
                      label: const Text("Cambiar Contraseña", style: TextStyle(color: Colors.red)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF166088)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}