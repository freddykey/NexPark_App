import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

// Importaciones de tus otros archivos
import 'pago_webview.dart';
import 'login_page.dart';
import 'recarga_page.dart';
import 'user_account.dart';

// --- MODELOS DE DATOS ---

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
    required this.precioHora,
  });

  factory Estacionamiento.fromJson(Map<String, dynamic> json) {
    return Estacionamiento(
      id: int.tryParse(json['id']?.toString() ?? json['id_estacionamiento']?.toString() ?? '0') ?? 0,
      nombre: json['nombre']?.toString() ?? "Sin nombre",
      totalCajones: int.tryParse(json['totalCajones']?.toString() ?? json['total_cajones']?.toString() ?? '0') ?? 0,
      niveles: int.tryParse(json['niveles']?.toString() ?? '1') ?? 1,
      precioHora: double.tryParse(json['precio_hora']?.toString() ?? '0.0') ?? 0.0,
    );
  }
}

// MODELO ACTUALIZADO PARA SOPORTAR MÚLTIPLES RESERVAS Y NOMBRES
class ReservaActiva {
  final String nombre;
  final String token;
  final String espacio;

  ReservaActiva({required this.nombre, required this.token, required this.espacio});

  factory ReservaActiva.fromJson(Map<String, dynamic> json) {
    return ReservaActiva(
      nombre: json['nombre_reserva'] ?? "Mi Reserva",
      token: json['token_qr'] ?? "",
      espacio: json['id_espacio']?.toString() ?? json['numero_espacio']?.toString() ?? "N/A",
    );
  }
}

// --- GESTIÓN DE ESTADO GLOBAL ---

class ParkingState {
  static List<bool> ocupados = [];
  static List<int> tiempos = [];
  static List<bool> esDiscapacitado = [];
  static List<Timer?> timers = [];
  static final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

  static void prepararCajones(int cantidad) {
    if (ocupados.length != cantidad) {
      ocupados = List.filled(cantidad, false);
      tiempos = List.filled(cantidad, 0);
      esDiscapacitado = List.filled(cantidad, false);
      timers = List.generate(cantidad, (_) => null);
    }
  }

  static Future<void> initNotificaciones() async {
    await Permission.notification.request();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await notifications.initialize(const InitializationSettings(android: androidSettings));
  }

  static void notificar(String mensaje) async {
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

// --- PÁGINA PRINCIPAL ---

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String nombre = "Cargando...";
  String correo = "...";
  String foto = "";
  String saldo = "0.00";
  int idUsuario = 0;
  Timer? _timerConsulta;
  Estacionamiento? seleccionado;
  int pisoSeleccionado = 1;
  List<Estacionamiento> misEstacionamientos = [];
  bool cargando = true;
  bool cambiandoSucursal = false;

  // CAMBIO: Ahora usamos una lista en lugar de un solo token
  List<ReservaActiva> misReservas = [];

  @override
  void initState() {
    super.initState();
    ParkingState.initNotificaciones();
    _inicializarApp();
    _timerConsulta = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && seleccionado != null) _actualizarEstadoDesdeServidor();
    });
  }

  @override
  void dispose() {
    _timerConsulta?.cancel();
    super.dispose();
  }

  Future<void> _inicializarApp() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      idUsuario = prefs.getInt('id_usuario') ?? 0;
      nombre = prefs.getString('nombre_usuario') ?? "Usuario";
      correo = prefs.getString('correo_usuario') ?? "Sin correo";
      foto = prefs.getString('foto_usuario') ?? "";
      saldo = prefs.getString('saldo_usuario') ?? "0.00";
    });

    if (idUsuario != 0) _cargarDatosUsuarioServidor();
    _obtenerReservas(); // Cambio de nombre de función
    await _obtenerEstacionamientosReal();

    int? idGuardado = prefs.getInt('estacionamiento_id');
    if (idGuardado != null && misEstacionamientos.isNotEmpty) {
      setState(() {
        seleccionado = misEstacionamientos.firstWhere((e) => e.id == idGuardado,
            orElse: () => misEstacionamientos.first);
        ParkingState.prepararCajones(seleccionado!.totalCajones);
      });
      _actualizarEstadoDesdeServidor();
    } else if (misEstacionamientos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _mostrarDialogoSeleccion());
    }
  }

  Future<void> _actualizarEstadoDesdeServidor() async {
    if (seleccionado == null) return;
    try {
      final response = await http.get(Uri.parse(
          "https://carlossalinas.webpro1213.com/api/get_espacios.php?id_estacionamiento=${seleccionado!.id}"));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          for (var item in data) {
            int numEspacio = int.tryParse(item['numero_espacio'].toString()) ?? 0;
            int index = numEspacio - 1;

            if (index >= 0 && index < seleccionado!.totalCajones) {
              ParkingState.esDiscapacitado[index] = (item['es_discapacitado'].toString() == "1");

              String estadoBD = item['estado'].toString(); // 'libre', 'reservado', 'ocupado'

              // 1. Determinar si está apartado o ya ocupado físicamente
              bool estaOcupado = (estadoBD != 'libre');
              ParkingState.ocupados[index] = estaOcupado;

              // 2. Lógica del cronómetro (Solo si ya es 'ocupado')
              if (estadoBD == 'ocupado' && item['fecha_fin'] != null) {
                DateTime horaFin = DateTime.parse(item['fecha_fin'].toString());
                int restantes = horaFin.difference(DateTime.now()).inSeconds;

                if (restantes > 0) {
                  ParkingState.tiempos[index] = restantes;
                  if (ParkingState.timers[index] == null || !ParkingState.timers[index]!.isActive) {
                    _reanimarTimerCajon(index);
                  }
                } else {
                  ParkingState.tiempos[index] = 0;
                }
              } else {
                // Si es 'reservado' (naranja), el tiempo se queda en 0 para la lógica visual
                ParkingState.tiempos[index] = 0;
                ParkingState.timers[index]?.cancel();
              }
            }
          }
        });
      }
    } catch (e) { debugPrint("Sync error: $e"); }
  }

  void _reanimarTimerCajon(int index) {
    ParkingState.timers[index]?.cancel();
    ParkingState.timers[index] = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) {
        setState(() {
          if (ParkingState.tiempos[index] > 0) {
            ParkingState.tiempos[index]--;
          } else {
            t.cancel();
            ParkingState.ocupados[index] = false;
            ParkingState.notificar("Cajón C${index + 1} se ha liberado.");
          }
        });
      }
    });
  }

  // FUNCIÓN MEJORADA: Ahora recibe el token específico del QR que quieres simular
  Future<void> _simularEntradaQR(String token) async {
    try {
      final response = await http.post(
        Uri.parse('https://carlossalinas.webpro1213.com/api/validar_entrada.php'),
        body: {'token_qr': token},
      );

      if (response.body.isNotEmpty) {
        final res = json.decode(response.body);
        if (res['status'] == 'success') {
          await _actualizarEstadoDesdeServidor();
          _obtenerReservas(); // Refrescar lista de QRs
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("¡Entrada exitosa!"), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: ${res['message']}"), backgroundColor: Colors.orange),
          );
        }
      }
    } catch (e) { print("Error: $e"); }
  }

  Future<void> _cargarDatosUsuarioServidor() async {
    try {
      var response = await http.post(
        Uri.parse('https://carlossalinas.webpro1213.com/api/get_user_data.php'),
        body: {'id_usuario': idUsuario.toString()},
      );
      var res = json.decode(response.body);
      if (res['status'] == 'success') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saldo_usuario', res['user']['saldo'].toString());
        if (mounted) {
          setState(() {
            saldo = res['user']['saldo'].toString();
            foto = res['user']['foto'] ?? foto;
          });
        }
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  // FUNCIÓN MEJORADA PARA OBTENER LA LISTA DE RESERVAS
  Future<void> _obtenerReservas() async {
    try {
      final response = await http.post(
        Uri.parse('https://carlossalinas.webpro1213.com/api/get_reserva_activa.php'),
        body: {'id_usuario': idUsuario.toString()},
      );
      final res = json.decode(response.body);
      if (res['status'] == 'success') {
        var listaJson = res['reservas'] as List;
        setState(() {
          misReservas = listaJson.map((r) => ReservaActiva.fromJson(r)).toList();
        });
      } else {
        setState(() => misReservas = []);
      }
    } catch (e) { debugPrint(e.toString()); }
  }

  Future<void> _obtenerEstacionamientosReal() async {
    try {
      final response = await http.get(Uri.parse("https://carlossalinas.webpro1213.com/api/get_estacionamientos.php"));
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Selecciona Sucursal", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...misEstacionamientos.map((est) => ListTile(
              leading: const Icon(Icons.business, color: Color(0xFF166088)),
              title: Text(est.nombre),
              subtitle: Text("${est.totalCajones} cajones • \$${est.precioHora}/hr + \$5 de reserva"),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('estacionamiento_id', est.id);
                Navigator.pop(context);
                setState(() {
                  seleccionado = est;
                  cambiandoSucursal = true;
                  pisoSeleccionado = 1;
                  ParkingState.prepararCajones(est.totalCajones);
                });
                await _actualizarEstadoDesdeServidor();
                setState(() => cambiandoSucursal = false);
              },
            )),
          ],
        ),
      ),
    );
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
        body: Stack(
          children: [
            cargando
                ? const Center(child: CircularProgressIndicator())
                : seleccionado == null
                ? const Center(child: Text("Selecciona un estacionamiento"))
                : Column(
              children: [
                _buildInfoBanner(),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildParkingGrid(),
                      const Center(child: Text("Vista de Mapa en desarrollo")),
                      _buildQRView(), // ESTA ES LA VISTA QUE CAMBIÓ
                    ],
                  ),
                ),
              ],
            ),
            if (cambiandoSucursal)
              Container(
                color: Colors.white.withOpacity(0.8),
                child: const Center(child: CircularProgressIndicator()),
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
              backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
              child: foto.isEmpty ? const Icon(Icons.person, size: 40) : null,
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
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecargaPage())),
          ),
          const Spacer(),
          const Divider(indent: 20, endIndent: 20),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Cerrar Sesión", style: TextStyle(color: Colors.red)),
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
            },
          ),
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text("NexPark Alpha-v0.5.0", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ActionChip(
            avatar: const Icon(Icons.business, size: 16),
            label: Text(seleccionado?.nombre ?? "Seleccionar"),
            onPressed: _mostrarDialogoSeleccion,
          ),
          Row(
            children: [
              Chip(
                backgroundColor: Colors.green.shade50,
                label: Text("\$$saldo", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
              if (seleccionado != null && seleccionado!.niveles > 1) ...[
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: pisoSeleccionado,
                  underline: const SizedBox(),
                  items: List.generate(seleccionado!.niveles, (i) => i + 1)
                      .map((p) => DropdownMenuItem(value: p, child: Text("Piso $p"))).toList(),
                  onChanged: (v) => setState(() => pisoSeleccionado = v!),
                ),
              ]
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
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: fin - inicio,
      itemBuilder: (context, index) => ParkingSlotItem(index: inicio + index),
    );
  }

  // VISTA DE QR MEJORADA: LISTA DESLIZABLE DE TARJETAS
  Widget _buildQRView() {
    if (misReservas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner, size: 80, color: Colors.grey),
            const SizedBox(height: 10),
            const Text("No tienes reservas activas", style: TextStyle(color: Colors.grey)),
            ElevatedButton(onPressed: _obtenerReservas, child: const Text("Actualizar")),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: misReservas.length,
      itemBuilder: (context, index) {
        final r = misReservas[index];
        return Card(
          elevation: 4,
          margin: const EdgeInsets.only(bottom: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(r.nombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF166088))),
                Text("Espacio: C${r.espacio}", style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 15),
                QrImageView(data: r.token, size: 200, foregroundColor: const Color(0xFF166088)),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  onPressed: () => _simularEntradaQR(r.token),
                  icon: const Icon(Icons.check_circle),
                  label: const Text("SIMULAR ENTRADA"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- ITEM DEL CAJÓN ---

class ParkingSlotItem extends StatefulWidget {
  final int index;
  const ParkingSlotItem({super.key, required this.index});
  @override
  State<ParkingSlotItem> createState() => _ParkingSlotItemState();
}

class _ParkingSlotItemState extends State<ParkingSlotItem> {
  String llegadaProgramada = DateTime.now().toString().split('.')[0];
  Timer? localUpdateTimer;

  @override
  void initState() {
    super.initState();
    localUpdateTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    localUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _seleccionarHoraLlegada(BuildContext context, StateSetter setDialogState) async {
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      final ahora = DateTime.now();
      final sel = DateTime(ahora.year, ahora.month, ahora.day, picked.hour, picked.minute);
      setDialogState(() => llegadaProgramada = sel.toString().split('.')[0]);
    }
  }

  void _confirmarReserva(int index) async {
    final homeState = context.findAncestorStateOfType<_HomePageState>();
    final est = homeState!.seleccionado!;

    final TextEditingController nombreController = TextEditingController(text: "Reserva C${index + 1}");

    if (ParkingState.esDiscapacitado[index]) {
      bool? continuar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Espacio Azul"),
          content: const Text("Este espacio es exclusivo para personas con discapacidad. ¿Continuar?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("NO")),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("SÍ")),
          ],
        ),
      );
      if (continuar != true) return;
    }

    int horas = 1;
    String metodo = "Saldo";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double total = 5.0 + (est.precioHora * horas);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text("Reserva Cajón C${index + 1}"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // CAMBIO: Agregamos el campo de nombre aquí
                  TextField(
                    controller: nombreController,
                    decoration: const InputDecoration(labelText: "Nombre para tu reserva", prefixIcon: Icon(Icons.edit)),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    leading: const Icon(Icons.access_time, color: Color(0xFF166088)),
                    title: Text(llegadaProgramada),
                    onTap: () => _seleccionarHoraLlegada(context, setDialogState),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(icon: const Icon(Icons.remove_circle), onPressed: () => setDialogState(() => horas > 1 ? horas-- : null)),
                      Text("$horas hr(s)", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.add_circle), onPressed: () => setDialogState(() => horas++)),
                    ],
                  ),
                  RadioListTile(title: const Text("Saldo NexPark"), value: "Saldo", groupValue: metodo, onChanged: (v) => setDialogState(() => metodo = v!)),
                  RadioListTile(title: const Text("Mercado Pago"), value: "Mercado Pago", groupValue: metodo, onChanged: (v) => setDialogState(() => metodo = v!)),
                  Text("Total: \$${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
              ElevatedButton(
                onPressed: () {
                  if (metodo == "Saldo" && double.parse(homeState.saldo) < total) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saldo insuficiente")));
                    return;
                  }
                  Navigator.pop(context);
                  _procesarPago(index, est, horas, total, metodo, nombreController.text);
                },
                child: const Text("Confirmar Pago"),
              )
            ],
          );
        },
      ),
    );
  }

  void _procesarPago(int index, Estacionamiento est, int horas, double monto, String metodo, String nombreR) async {
    final homeState = context.findAncestorStateOfType<_HomePageState>();
    try {
      final url = (metodo == "Saldo")
          ? 'https://carlossalinas.webpro1213.com/api/crear_reserva.php'
          : 'https://carlossalinas.webpro1213.com/api/crear_preferencia.php';

      final response = await http.post(
        Uri.parse(url),
        body: {
          'id_usuario': homeState!.idUsuario.toString(),
          'id_espacio': (index + 1).toString(),
          'monto': monto.toString(),
          'id_estacionamiento': est.id.toString(),
          'hora_llegada_estimada': llegadaProgramada.trim(),
          'metodo': metodo,
          'horas': horas.toString(),
          'nombre_reserva': nombreR,
        },
      );

      final res = json.decode(response.body);
      if (res['status'] == 'success') {
        if (metodo == "Saldo") {
          setState(() => ParkingState.ocupados[index] = true);
          homeState._cargarDatosUsuarioServidor();
          homeState._obtenerReservas();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Reserva confirmada!")));
        } else {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => PagoWebView(url: res['url_pago'])));
          if (result == "success") {
            homeState._cargarDatosUsuarioServidor();
            homeState._obtenerReservas();
          }
        }
      }
    } catch (e) { debugPrint("Error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    bool ocupado = ParkingState.ocupados[widget.index];
    bool esDis = ParkingState.esDiscapacitado[widget.index];
    int tiempoRestante = ParkingState.tiempos[widget.index];

    // LÓGICA DE COLORES:
    Color colorCajon;

    if (!ocupado) {
      // ESTADO: LIBRE
      colorCajon = esDis ? Colors.blue.shade600 : Colors.green.shade400;
    } else {
      // ESTADO: RESERVADO U OCUPADO
      if (tiempoRestante > 0) {
        // ROJO: Ya escaneó el QR y el tiempo está corriendo
        colorCajon = Colors.red.shade400;
      } else {
        // NARANJA: Está apartado en la BD pero aún no llega (tiempo = 0)
        colorCajon = Colors.orange.shade400;
      }
    }

    return GestureDetector(
      onTap: () => ocupado ? null : _confirmarReserva(widget.index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
            color: colorCajon,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.black12)
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                ocupado && tiempoRestante > 0 ? Icons.timer : (esDis ? Icons.accessible : Icons.local_parking),
                color: Colors.white,
                size: 35
            ),
            Text(
                "C${widget.index + 1}",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)
            ),
            if (ocupado)
              Text(
                  tiempoRestante > 0 ? ParkingState.formatearTiempo(tiempoRestante) : "RESERVADO",
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)
              ),
          ],
        ),
      ),
    );
  }
}