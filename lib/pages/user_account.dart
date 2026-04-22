import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'recarga_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';

class UserAccount extends StatefulWidget {
  const UserAccount({super.key});

  @override
  State<UserAccount> createState() => _UserAccountState();
}

class _UserAccountState extends State<UserAccount> {
  String nombre = "Cargando...";
  String correo = "...";
  String foto = "";
  String apellidoP = "";
  String apellidoM = "";
  String telefono = "";
  String saldo = "0";
  String fecha = "--/--/----";
  String vehiculos = "0";
  int idUsuario = 0;

  @override
  void initState() {
    super.initState();
    _inicializarDatos();
  }


  Future<void> _inicializarDatos() async {
    final prefs = await SharedPreferences.getInstance();

    if (mounted) {
      setState(() {
        idUsuario = prefs.getInt('id_usuario') ?? 0;
        nombre = prefs.getString('nombre_usuario') ?? "Usuario NexPark";
        correo = prefs.getString('correo_usuario') ?? "usuario@correo.com";
        foto = prefs.getString('foto_usuario') ?? "";


        apellidoP = prefs.getString('apellido_paterno') ?? "";
        apellidoM = prefs.getString('apellido_materno') ?? "";
        telefono = prefs.getString('telefono_usuario') ?? "";
        saldo = prefs.getString('saldo_usuario') ?? "0";
        fecha = prefs.getString('fecha_registro') ?? "--/--/----";

        vehiculos = prefs.getString('cantidad_vehiculos') ?? "0";
      });
    }

    if (idUsuario != 0) {
      _cargarDatosServidor();
    }
  }


  Future<void> _cargarDatosServidor() async {
    try {

      var url = Uri.parse('https://carlossalinas.webpro1213.com/api/get_user_data.php');
      var response = await http.post(url, body: {
        'id_usuario': idUsuario.toString(),
      });

      var res = json.decode(response.body);

      if (res['status'] == 'success' && res['user'] != null) {
        var userData = res['user'];
        final prefs = await SharedPreferences.getInstance();

        String rawFecha = userData['fecha_registro']?.toString() ?? "";
        String fechaNueva = "--/--/----";

        if (rawFecha.isNotEmpty && rawFecha != "null") {
          List<String> partes = rawFecha.split("-");
          if (partes.length == 3) {
            fechaNueva = "${partes[2]}/${partes[1]}/${partes[0]}";
          } else {
            fechaNueva = rawFecha;
          }
        }


        await prefs.setString('apellido_paterno', _limpiarNulo(userData['apellido_paterno']));
        await prefs.setString('apellido_materno', _limpiarNulo(userData['apellido_materno']));
        await prefs.setString('telefono_usuario', _limpiarNulo(userData['telefono']));
        await prefs.setString('saldo_usuario', userData['saldo']?.toString() ?? "0");


        await prefs.setString('fecha_registro', fechaNueva);

        if (mounted) {
          setState(() {
            nombre = userData['nombre']?.toString() ?? nombre;
            apellidoP = _limpiarNulo(userData['apellido_paterno']);
            apellidoM = _limpiarNulo(userData['apellido_materno']);
            telefono = _limpiarNulo(userData['telefono']);
            saldo = userData['saldo']?.toString() ?? "0";
            vehiculos = res['vehiculos']?.toString() ?? "0";
            prefs.setString('cantidad_vehiculos', vehiculos);


            String fotoServidor = userData['foto']?.toString() ?? "";
            if (fotoServidor.isNotEmpty) {
              foto = fotoServidor;
              prefs.setString('foto_usuario', fotoServidor); // Esto la mantiene grabada
            }

            fecha = fechaNueva;
          });
        }
      }
    } catch (e) {
      debugPrint("Error al sincronizar: $e");
    }
  }

  String _limpiarNulo(dynamic valor) {
    if (valor == null || valor.toString() == "null") return "";
    return valor.toString();
  }

  String _validar(String? valor) {
    if (valor == null || valor.trim().isEmpty || valor == "null") {
      return "--";
    }
    return valor;
  }


  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
  }

  Future<void> _cambiarFoto() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50
    );

    if (image != null) {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator())
      );

      try {
        var request = http.MultipartRequest(
            'POST',
            Uri.parse('https://carlossalinas.webpro1213.com/api/actualizar_foto.php')
        );


        request.fields['id_usuario'] = idUsuario.toString();


        request.files.add(await http.MultipartFile.fromPath('foto', image.path));

        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (!mounted) return;
        Navigator.pop(context);

        var res = json.decode(response.body);

        if (res['status'] == 'success') {
          String nuevaUrl = res['url'];


          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('foto_usuario', nuevaUrl);

          setState(() {
            foto = nuevaUrl;
          });

          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("¡Foto actualizada!"), backgroundColor: Colors.green)
          );
        } else {
          _mostrarError("Servidor: ${res['message']}");
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        debugPrint("Error conexión: $e");
        _mostrarError("No se pudo conectar con el servidor");
      }
    }
  }

  void _editarUsuario() {
    final nombreCtrl = TextEditingController(text: nombre);
    final apCtrl = TextEditingController(text: apellidoP);
    final amCtrl = TextEditingController(text: apellidoM);
    final telCtrl = TextEditingController(text: telefono);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Editar mis datos"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: "Nombre", prefixIcon: Icon(Icons.person))),
              TextField(controller: apCtrl, decoration: const InputDecoration(labelText: "Apellido Paterno")),
              TextField(controller: amCtrl, decoration: const InputDecoration(labelText: "Apellido Materno")),
              TextField(controller: telCtrl, decoration: const InputDecoration(labelText: "Teléfono", prefixIcon: Icon(Icons.phone))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF166088), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator()),
              );

              try {
                var url = Uri.parse('https://carlossalinas.webpro1213.com/api/update_user.php');
                var response = await http.post(url, body: {
                  'id_usuario': idUsuario.toString(),
                  'nombre': nombreCtrl.text.trim(),
                  'apellido_paterno': apCtrl.text.trim(),
                  'apellido_materno': amCtrl.text.trim(),
                  'telefono': telCtrl.text.trim(),
                });

                var res = json.decode(response.body);

                if (res['status'] == 'success') {

                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('nombre_usuario', nombreCtrl.text.trim());
                  await prefs.setString('apellido_paterno', apCtrl.text.trim());
                  await prefs.setString('apellido_materno', amCtrl.text.trim());
                  await prefs.setString('telefono_usuario', telCtrl.text.trim());


                  if (mounted) {
                    setState(() {
                      nombre = nombreCtrl.text.trim();
                      apellidoP = apCtrl.text.trim();
                      apellidoM = amCtrl.text.trim();
                      telefono = telCtrl.text.trim();
                    });
                  }

                  if (!mounted) return;
                  Navigator.pop(context);
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Datos actualizados correctamente"), backgroundColor: Colors.green)
                  );
                } else {
                  if (!mounted) return;
                  Navigator.pop(context);
                  _mostrarError("Error al actualizar: ${res['message']}");
                }
              } catch (e) {
                if (!mounted) return;
                Navigator.pop(context);
                _mostrarError("Error de conexión: $e");
              }
            },
            child: const Text("Guardar cambios", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }


  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _cambiarPassword() async {
    final passCtrl = TextEditingController();
    final prefs = await SharedPreferences.getInstance();

    int idReal = prefs.getInt('id_usuario') ?? 0;

    if (idReal == 0) {
      _mostrarError("Error: No se encontró tu sesión. Reingresa a la app.");
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Nueva Contraseña"),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: "Nueva clave", prefixIcon: Icon(Icons.lock)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (passCtrl.text.trim().isEmpty) return;

              showDialog(context: context, builder: (_) => const Center(child: CircularProgressIndicator()));

              try {
                var response = await http.post(
                  Uri.parse('https://carlossalinas.webpro1213.com/api/actualizar_password.php'),
                  body: {
                    'id_usuario': idReal.toString(),
                    'password': passCtrl.text.trim(),
                  },
                );

                var res = json.decode(response.body);
                Navigator.pop(context);

                if (res['status'] == 'success') {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("¡Contraseña Actualizada!."), backgroundColor: Colors.green)
                  );
                } else {
                  _mostrarError(res['message']);
                }
              } catch (e) {
                Navigator.pop(context);
                _mostrarError("Error de conexión");
              }
            },
            child: const Text("Guardar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // DISEÑO
  @override
  Widget build(BuildContext context) {
    String fullApellidos = "${_validar(apellidoP)} ${_validar(apellidoM)}".replaceAll("-- --", "").trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text("Mi Cuenta", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF166088),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: _buildDrawerInterno(),

      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
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
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30))
                      )
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
                                  child: foto.isEmpty ? const Icon(Icons.person, size: 70, color: Color(0xFF166088)) : null
                              )
                          ),
                          const Positioned(
                              bottom: 5,
                              right: 5,
                              child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Color(0xFF166088),
                                  child: Icon(Icons.camera_alt, size: 18, color: Colors.white)
                              )
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 80),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  children: [
                    Text(
                        "$nombre $fullApellidos",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF166088))
                    ),
                    const SizedBox(height: 5),
                    Text(
                        "Saldo Actual: \$ $saldo",
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)
                    ),
                    const SizedBox(height: 25),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                          ]
                      ),
                      child: Column(
                        children: [
                          _buildInfoTile(Icons.person_outline, "Apellido Paterno", _validar(apellidoP)),
                          const Divider(),
                          _buildInfoTile(Icons.person_outline, "Apellido Materno", _validar(apellidoM)),
                          const Divider(),
                          _buildInfoTile(Icons.email_outlined, "Correo", correo),
                          const Divider(),
                          _buildInfoTile(Icons.phone_android_outlined, "Teléfono", _validar(telefono)),
                          const Divider(),
                          _buildInfoTile(Icons.directions_car_outlined, "Vehículos", "$vehiculos Registrados"),
                          const Divider(),
                          _buildInfoTile(Icons.calendar_today_outlined, "Miembro desde", fecha),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),

                    // BOTONES PRINCIPALES
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: TextButton.icon(
                          onPressed: _cambiarPassword,
                          icon: const Icon(Icons.lock_outline, size: 20, color: Colors.red),
                          label: const Text("Cambiar Contraseña", style: TextStyle(color: Colors.red))
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper para el Drawer si lo necesitas dentro del mismo archivo
  Widget _buildDrawerInterno() {
    return Drawer(
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
          ListTile(leading: const Icon(Icons.home, color: Color(0xFF166088)), title: const Text("Inicio"), onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()))),
          ListTile(leading: const Icon(Icons.person, color: Color(0xFF166088)), title: const Text("Cuenta"), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.add_card, color: Color(0xFF166088)), title: const Text("Recargar Saldo"), onTap: () {Navigator.pop(context);Navigator.push(context, MaterialPageRoute(builder: (context) => const RecargaPage()),);},),
          const Spacer(),
          const Divider(indent: 20, endIndent: 20),
          ListTile(leading: const Icon(Icons.logout_rounded, color: Color(0xFFEB5757)), title: const Text("Cerrar sesión", style: TextStyle(color: Color(0xFFEB5757), fontWeight: FontWeight.bold),), onTap: _logout,),
          const Padding(padding: EdgeInsets.all(20.0), child: Text("NexPark alpha-v0.5.0", style: TextStyle(color: Colors.grey, fontSize: 12),),),
          const SizedBox(height: 10),
        ],
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
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)), Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))])),
        ],
      ),
    );
  }
}