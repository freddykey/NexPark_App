import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pago_webview.dart';


import 'login_page.dart';
import 'recarga_page.dart';
import 'user_account.dart';


class Estacionamiento {
  final int id;
  final String nombre;
  final int totalCajones;
  final int niveles;
  final double precioHora;

  Estacionamiento({
    required this.id,
    required this.nombre,
    required this.totalCajones,
    required this.niveles,
    required this.precioHora
  });

  factory Estacionamiento.fromJson(Map<String, dynamic> json) {
    return Estacionamiento(
      id: int.tryParse(json['id']?.toString() ?? json['id_estacionamiento']?.toString() ?? '0') ?? 0,
      nombre: json['nombre']?.toString() ?? "Sin nombre",
      totalCajones: int.tryParse(json['totalCajones']?.toString() ?? json['total_cajones']?.toString() ?? '0') ?? 0,
      niveles: int.tryParse(json['niveles']?.toString() ?? '1') ?? 1,
      precioHora: double.tryParse(json['precio_hora']?.toString() ?? '10.0') ?? 10.0,
    );
  }
}

// MODELO VEHÍCULO
class Vehiculo {
  final int id;
  final String placa;
  final String modelo;

  Vehiculo({required this.id, required this.placa, required this.modelo});

  factory Vehiculo.fromJson(Map<String, dynamic> json) {
    return Vehiculo(
      id: int.tryParse(json['id_vehiculo']?.toString() ?? '0') ?? 0,
      placa: json['placa']?.toString() ?? "---",
      modelo: json['modelo']?.toString() ?? "Auto",
    );
  }

  @override
  String toString() => '$modelo [$placa]';
}


class ParkingState {
  static List<bool> ocupados = [];
  static List<int> tiempos = [];
  static List<Timer?> timers = [];
  static Timer? globalTimer;
  static final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

  static void prepararCajones(int cantidad) {
    if (ocupados.length != cantidad) {
      ocupados = List.generate(cantidad, (_) => false);
      tiempos = List.generate(cantidad, (_) => 0);
      timers = List.generate(cantidad, (_) => null);
    }
  }

  static Future<void> initNotificaciones() async {
    await Permission.notification.request();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await notifications.initialize(const InitializationSettings(android: androidSettings));
  }

  static void iniciarGlobal(VoidCallback updateUI) {
    globalTimer?.cancel();
    globalTimer = Timer.periodic(const Duration(seconds: 1), (_) => updateUI());
  }

  static Future<void> notificar(String mensaje) async {
    const androidDetails = AndroidNotificationDetails('canal_nexpark', 'NexPark Alerts',
        importance: Importance.max, priority: Priority.high);
    await notifications.show(0, 'NexPark', mensaje, const NotificationDetails(android: androidDetails));
  }


  static String formatearTiempo(int segundosTotales) {
    int horas = segundosTotales ~/ 3600;
    int minutos = (segundosTotales % 3600) ~/ 60;
    int segundos = segundosTotales % 60;
    return "${horas.toString().padLeft(2, '0')}:${minutos.toString().padLeft(2, '0')}:${segundos.toString().padLeft(2, '0')}";
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String nombre = "Cargando...";
  String correo = "...";
  String foto = "";
  String saldo = "0";
  int idUsuario = 0;

  Estacionamiento? seleccionado;
  int pisoSeleccionado = 1;
  List<Estacionamiento> misEstacionamientos = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    ParkingState.initNotificaciones();
    _inicializarApp();
  }


  void actualizarSaldo(String nuevoSaldo) {
    setState(() {
      saldo = nuevoSaldo;
    });
  }

  Future<void> _inicializarApp() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      idUsuario = prefs.getInt('id_usuario') ?? 0;
      nombre = prefs.getString('nombre_usuario') ?? "Usuario";
      correo = prefs.getString('correo_usuario') ?? "Sin correo";
      foto = prefs.getString('foto_usuario') ?? "";
      saldo = prefs.getString('saldo_usuario') ?? "0";
    });

    if (idUsuario != 0) _cargarDatosUsuarioServidor();
    await _obtenerEstacionamientosReal();

    int? idGuardado = prefs.getInt('estacionamiento_id');
    if (idGuardado != null && misEstacionamientos.isNotEmpty) {
      setState(() {
        seleccionado = misEstacionamientos.firstWhere((e) => e.id == idGuardado,
            orElse: () => misEstacionamientos.first);
        ParkingState.prepararCajones(seleccionado!.totalCajones);
      });
    } else if (misEstacionamientos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _mostrarDialogoSeleccion());
    }
  }

  Future<void> _cargarDatosUsuarioServidor() async {
    try {
      var response = await http.post(
        Uri.parse('https://carlossalinas.webpro1213.com/api/get_user_data.php'),
        body: {'id_usuario': idUsuario.toString()},
      );
      var res = json.decode(response.body);
      if (res['status'] == 'success' && res['user'] != null) {
        var userData = res['user'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saldo_usuario', userData['saldo']?.toString() ?? "0");
        if (mounted) {
          setState(() {
            nombre = userData['nombre']?.toString() ?? nombre;
            saldo = userData['saldo']?.toString() ?? "0";
            foto = userData['foto']?.toString() ?? foto;
          });
        }
      }
    } catch (e) { debugPrint("Error usuario: $e"); }
  }

  Future<void> _obtenerEstacionamientosReal() async {
    try {
      final response = await http.get(Uri.parse("https://carlossalinas.webpro1213.com/api/get_estacionamientos.php")).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        setState(() {
          misEstacionamientos = data.map((e) => Estacionamiento.fromJson(e)).toList();
          cargando = false;
        });
      }
    } catch (e) { setState(() => cargando = false); }
  }

  void _mostrarDialogoSeleccion() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Selecciona una sucursal", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ...misEstacionamientos.map((est) => ListTile(
              leading: const Icon(Icons.business, color: Color(0xFF166088)),
              title: Text(est.nombre),
              subtitle: Text("${est.totalCajones} cajones • ${est.niveles} niveles"),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('estacionamiento_id', est.id);
                setState(() {
                  seleccionado = est;
                  pisoSeleccionado = 1;
                  ParkingState.prepararCajones(est.totalCajones);
                });
                Navigator.pop(context);
              },
            )).toList(),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Image.asset('assets/logowhite.png', height: 40, fit: BoxFit.contain),
          centerTitle: true,
          backgroundColor: const Color(0xFF166088),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.local_parking), text: "Cajones"),
              Tab(icon: Icon(Icons.map), text: "Mapa"),
              Tab(icon: Icon(Icons.qr_code), text: "QR"),
            ],
          ),
        ),
        drawer: _buildDrawer(),
        body: cargando
            ? const Center(child: CircularProgressIndicator())
            : seleccionado == null
            ? const Center(child: Text("No hay estacionamiento seleccionado"))
            : Column(
          children: [
            _buildInfoBanner(),
            Expanded(
              child: TabBarView(
                children: [
                  _buildParkingGrid(),
                  const MapPage(),
                  const QRPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF166088)),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
              child: foto.isEmpty ? Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : "U",
                  style: const TextStyle(fontSize: 40, color: Color(0xFF166088))) : null,
            ),
            accountName: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(correo),
          ),
          ListTile(
            leading: const Icon(Icons.home, color: Color(0xFF166088)),
            title: const Text("Inicio"),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Color(0xFF166088)),
            title: const Text("Cuenta"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const UserAccount()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_card, color: Color(0xFF166088)),
            title: const Text("Recargar Saldo"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const RecargaPage()));
            },
          ),
          const Spacer(),
          const Divider(indent: 20, endIndent: 20),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Color(0xFFEB5757)),
            title: const Text("Cerrar sesión", style: TextStyle(color: Color(0xFFEB5757), fontWeight: FontWeight.bold)),
            onTap: _logout,
          ),
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text("NexPark alpha-v0.4.2", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 2)]),
      child: Wrap(
        spacing: 30,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ActionChip(
            avatar: const Icon(Icons.business, size: 16),
            label: Text(seleccionado!.nombre, overflow: TextOverflow.ellipsis),
            onPressed: _mostrarDialogoSeleccion,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Chip(
                backgroundColor: Colors.green.shade50,
                label: Text("\$$saldo", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              if (seleccionado!.niveles > 1)
                DropdownButton<int>(
                  value: pisoSeleccionado,
                  underline: const SizedBox(),
                  items: List.generate(seleccionado!.niveles, (i) => i + 1)
                      .map((p) => DropdownMenuItem(value: p, child: Text("Piso $p  "))).toList(),
                  onChanged: (v) => setState(() => pisoSeleccionado = v!),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParkingGrid() {
    int cajonesPorPiso = (seleccionado!.totalCajones / seleccionado!.niveles).ceil();
    int inicio = (pisoSeleccionado - 1) * cajonesPorPiso;
    int fin = (inicio + cajonesPorPiso > seleccionado!.totalCajones) ? seleccionado!.totalCajones : inicio + cajonesPorPiso;
    return GridView.builder(
      padding: const EdgeInsets.all(15),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15),
      itemCount: fin - inicio,
      itemBuilder: (context, index) => ParkingSlotItem(index: inicio + index),
    );
  }
}


class ParkingSlotItem extends StatefulWidget {
  final int index;
  const ParkingSlotItem({super.key, required this.index});
  @override
  State<ParkingSlotItem> createState() => _ParkingSlotItemState();
}

class _ParkingSlotItemState extends State<ParkingSlotItem> {
  List<Vehiculo> misVehiculos = [];
  Vehiculo? vehiculoSeleccionado;
  String vehiculoEscrito = "";

  @override
  void initState() {
    super.initState();
    ParkingState.iniciarGlobal(() { if (mounted) setState(() {}); });
  }

  Future<void> _obtenerVehiculos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int idU = prefs.getInt('id_usuario') ?? 0;
      final response = await http.post(
        Uri.parse('https://carlossalinas.webpro1213.com/api/get_vehiculos.php'),
        body: {'id_usuario': idU.toString()},
      );
      if (response.statusCode == 200) {
        List data = json.decode(response.body);
        if (mounted) setState(() { misVehiculos = data.map((v) => Vehiculo.fromJson(v)).toList(); });
      }
    } catch (e) { debugPrint("Error vehiculos: $e"); }
  }

  void iniciarTimer(int index, int segundos) {
    ParkingState.tiempos[index] = segundos;
    ParkingState.timers[index]?.cancel();


    ParkingState.timers[index] = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) {
        setState(() {
          if (ParkingState.tiempos[index] > 0) {
            ParkingState.tiempos[index]--;
          } else {
            t.cancel();
            ParkingState.ocupados[index] = false;
            ParkingState.notificar("El Cajón C${index + 1} se ha liberado.");
          }
        });
      }
    });
  }

  void _confirmarReserva(int index) async {
    final homeState = context.findAncestorStateOfType<_HomePageState>();
    final est = homeState?.seleccionado;
    if (est == null) return;

    await _obtenerVehiculos();

    int horasLocal = 1;
    String metodoPago = "Mercado Pago"; // Default
    vehiculoSeleccionado = null;
    vehiculoEscrito = "";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Reservar Cajón C${index + 1}"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Vehículo (Selecciona o escribe):", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Autocomplete<Vehiculo>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) return const Iterable<Vehiculo>.empty();
                    return misVehiculos.where((v) =>
                    v.modelo.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                        v.placa.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                  },
                  displayStringForOption: (Vehiculo v) => "${v.modelo} [${v.placa}]",
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        hintText: "Ej: Versa ABC-123",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          vehiculoEscrito = val;
                          vehiculoSeleccionado = null;
                        });
                      },
                    );
                  },
                  onSelected: (Vehiculo v) {
                    setDialogState(() {
                      vehiculoSeleccionado = v;
                      vehiculoEscrito = "";
                    });
                  },
                ),
                const SizedBox(height: 15),
                const Text("Tiempo (horas):", style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () { if(horasLocal > 1) setDialogState(() => horasLocal--); }),
                    Text("$horasLocal hr(s)", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => setDialogState(() => horasLocal++)),
                  ],
                ),
                const SizedBox(height: 15),
                const Text("Método de Pago:", style: TextStyle(fontWeight: FontWeight.bold)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Mercado Pago", style: TextStyle(fontSize: 14)),
                  leading: Radio<String>(
                    value: "Mercado Pago",
                    groupValue: metodoPago,
                    onChanged: (v) => setDialogState(() => metodoPago = v!),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text("Saldo NexPark (\$${homeState?.saldo})", style: const TextStyle(fontSize: 14)),
                  leading: Radio<String>(
                    value: "Saldo",
                    groupValue: metodoPago,
                    onChanged: (v) => setDialogState(() => metodoPago = v!),
                  ),
                ),
                const Divider(),
                Text("Total: \$${(est.precioHora * horasLocal + 5.0).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: (vehiculoSeleccionado == null && vehiculoEscrito.isEmpty) ? null : () {
                double total = (est.precioHora * horasLocal + 5.0);
                if (metodoPago == "Saldo" && double.parse(homeState!.saldo) < total) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saldo insuficiente en NexPark")));
                  return;
                }
                Navigator.pop(context);
                _procesarPago(index, est, horasLocal, metodoPago);
              },
              child: const Text("Pagar"),
            ),
          ],
        ),
      ),
    );
  }

  void _procesarPago(int index, Estacionamiento est, int horas, String metodo) async {
    DateTime inicio = DateTime.now();
    DateTime fin = inicio.add(Duration(hours: horas));
    String idV = vehiculoSeleccionado != null ? vehiculoSeleccionado!.id.toString() : "0";

    try {
      // Obtenemos la referencia al estado del HomePage para actualizar su UI
      final homeState = context.findAncestorStateOfType<_HomePageState>();
      final prefs = await SharedPreferences.getInstance();
      int idU = prefs.getInt('id_usuario') ?? 0;

      final response = await http.post(
        Uri.parse('https://carlossalinas.webpro1213.com/api/crear_preferencia.php'),
        body: {
          'id_usuario': idU.toString(),
          'id_espacio': (index + 1).toString(),
          'monto': (est.precioHora * horas + 5.0).toString(),
          'fecha_inicio': inicio.toString().split('.')[0],
          'fecha_fin': fin.toString().split('.')[0],
          'id_vehiculo': idV,
          'nuevo_vehiculo': vehiculoEscrito,
          'metodo': metodo,
          'tipo_flujo': 'reserva',
        },
      ).timeout(const Duration(seconds: 15));

      final res = json.decode(response.body);

      if (res['status'] == 'success') {
        if (!mounted) return;

        if (metodo == "Saldo") {

          String nuevoSaldoStr = res['nuevo_saldo'].toString();


          await prefs.setString('saldo_usuario', nuevoSaldoStr);


          homeState?.setState(() {
            homeState.saldo = nuevoSaldoStr;
          });


          setState(() {
            ParkingState.ocupados[index] = true;
          });
          iniciarTimer(index, horas * 3600);

          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Reserva exitosa"), backgroundColor: Colors.green)
          );
        } else {

          final resultado = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => PagoWebView(url: res['url_pago'])),
          );

          if (resultado == "success") {

            homeState?._cargarDatosUsuarioServidor();
            setState(() => ParkingState.ocupados[index] = true);
            iniciarTimer(index, horas * 3600);
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: ${res['message']}")));
      }
    } catch (e) {
      debugPrint("Error pago: $e");

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error al confirmar reserva")));
    }
  }

  @override
  Widget build(BuildContext context) {
    int i = widget.index;
    bool ocupado = ParkingState.ocupados[i];
    return GestureDetector(
      onTap: () => ocupado ? null : _confirmarReserva(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
            color: ocupado ? Colors.red.shade400 : Colors.green.shade400,
            borderRadius: BorderRadius.circular(20)
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_parking, color: Colors.white, size: 40),
            Text("C${i + 1}", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),

            if (ocupado)
              Text(
                  ParkingState.formatearTiempo(ParkingState.tiempos[i]),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)
              ),
          ],
        ),
      ),
    );
  }
}

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {

    return Stack(
      children: [
        // MAPA
        Container(
          color: Colors.grey[300],
          child: const Center(child: Text("Mapa")),
        ),

        // INFO DEL CAJÓN
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: ListTile(
              title: const Text("Cajón reservado"),
              subtitle: const Text("Sigue la ruta"),
              trailing: ElevatedButton(
                onPressed: () {},
                child: const Text("Ir"),
              ),
            ),
          ),
        )
      ],
    );
  }
}

class QRPage extends StatelessWidget {
  const QRPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Icon(Icons.qr_code, size: 200, color: Color(0xFF166088)));
}