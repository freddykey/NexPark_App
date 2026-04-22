import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MisVehiculos extends StatefulWidget {
  const MisVehiculos({super.key});

  @override
  State<MisVehiculos> createState() => _MisVehiculosState();
}

class _MisVehiculosState extends State<MisVehiculos> {
  List<dynamic> vehiculos = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _obtenerVehiculos();
  }

  Future<void> _obtenerVehiculos() async {
    setState(() => cargando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      int idUser = prefs.getInt('id_usuario') ?? 0;

      // RECUERDA: Debes crear este PHP en tu servidor para que retorne el JSON de la tabla vehiculos
      final response = await http.get(Uri.parse(
          "https://carlossalinas.webpro1213.com/api/get_vehiculos.php?id_usuario=$idUser"));

      if (response.statusCode == 200) {
        setState(() {
          vehiculos = json.decode(response.body);
        });
      }
    } catch (e) {
      debugPrint("Error obteniendo vehículos: $e");
    } finally {
      setState(() => cargando = false);
    }
  }

  void _mostrarFormularioAgregar() {
    final placaCtrl = TextEditingController();
    final modeloCtrl = TextEditingController();
    final colorCtrl = TextEditingController();
    bool guardandoInterno = false; // Para el estado del botón

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder( // Agregamos esto para que el botón cambie de estado
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 25,
              right: 25,
              top: 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Registrar Vehículo",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF166088))),
              const SizedBox(height: 15),
              TextField(
                controller: placaCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: "Placa *",
                  prefixIcon: const Icon(Icons.badge),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: modeloCtrl,
                decoration: InputDecoration(
                  labelText: "Modelo / Marca *",
                  prefixIcon: const Icon(Icons.directions_car),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: colorCtrl,
                decoration: InputDecoration(
                  labelText: "Color (Opcional)", // Marcado como opcional
                  prefixIcon: const Icon(Icons.palette),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF166088),
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: guardandoInterno ? null : () async {
                  // VALIDACIÓN: Solo placa y modelo son obligatorios
                  if (placaCtrl.text.trim().isEmpty || modeloCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Placa y Modelo son obligatorios"))
                    );
                    return;
                  }

                  setModalState(() => guardandoInterno = true);

                  // El color ahora es opcional: si está vacío mandamos "N/A" o lo que prefieras
                  String colorEnviar = colorCtrl.text.trim().isEmpty ? "No especificado" : colorCtrl.text.trim();

                  await _guardarVehiculo(
                      placaCtrl.text.trim(),
                      modeloCtrl.text.trim(),
                      colorEnviar
                  );

                  if(mounted) Navigator.pop(context);
                },
                child: guardandoInterno
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("GUARDAR VEHÍCULO",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _guardarVehiculo(String p, String m, String c) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int idUser = prefs.getInt('id_usuario') ?? 0;

      final response = await http.post(
          Uri.parse("https://carlossalinas.webpro1213.com/api/agregar_vehiculo.php"),
          body: {
            'id_usuario': idUser.toString(),
            'placa': p,
            'modelo': m,
            'color': c
          }).timeout(const Duration(seconds: 10)); // Timeout por si el server no responde

      final res = json.decode(response.body);
      if (res['status'] == 'success') {
        _obtenerVehiculos(); // Recarga la lista
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Vehículo guardado correctamente"), backgroundColor: Colors.green));
      } else {
        _mostrarError("Error del servidor: ${res['message']}");
      }
    } catch (e) {
      debugPrint("Error al guardar: $e");
      _mostrarError("Error de conexión. Inténtalo de nuevo.");
    }
  }

  void _mostrarError(String msg) {
    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red)
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Vehículos"),
        backgroundColor: const Color(0xFF166088),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _construirCuerpo(),
      floatingActionButton: vehiculos.isNotEmpty
          ? FloatingActionButton(
        backgroundColor: const Color(0xFF166088),
        onPressed: _mostrarFormularioAgregar,
        child: const Icon(Icons.add, color: Colors.white),
      )
          : null,
    );
  }

  Widget _construirCuerpo() {
    if (cargando) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF166088)));
    }

    if (vehiculos.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.directions_car_filled_outlined,
                    size: 100, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 30),
              const Text("¡Garaje Vacío!",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF166088))),
              const SizedBox(height: 12),
              const Text(
                "Registra tus vehículos para seleccionarlos rápidamente al realizar una reserva.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey, height: 1.4),
              ),
              const SizedBox(height: 35),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF166088),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: _mostrarFormularioAgregar,
                icon: const Icon(Icons.add),
                label: const Text("AGREGAR MI PRIMER AUTO"),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: vehiculos.length,
      itemBuilder: (context, i) => Card(
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF166088).withOpacity(0.1),
            child: const Icon(Icons.directions_car, color: Color(0xFF166088)),
          ),
          title: Text(vehiculos[i]['modelo'] ?? "Sin modelo",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: Text("Placas: ${vehiculos[i]['placa']}\nColor: ${vehiculos[i]['color']}"),
          isThreeLine: true,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () {
              // Aquí podrías agregar una confirmación para borrar
            },
          ),
        ),
      ),
    );
  }
}