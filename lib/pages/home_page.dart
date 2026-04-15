import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
  final String token;
  final String nombre;
  final String espacio;
  final String horaLlegada;
  final int horasPagadas;
  final int idEstacionamiento;

  ReservaActiva({
    required this.token,
    required this.nombre,
    required this.espacio,
    required this.horaLlegada,
    required this.horasPagadas,
    required this.idEstacionamiento,
  });

  factory ReservaActiva.fromJson(Map<String, dynamic> json) {
    return ReservaActiva(
      token: json['token_qr'] ?? '',
      nombre: json['nombre_reserva'] ?? 'Sin nombre',
      espacio: json['numero_espacio']?.toString() ?? '',

      horaLlegada: json['hora_llegada_estimada']?.toString() ?? '',
      horasPagadas: int.tryParse(json['horas_pagadas']?.toString() ?? '1') ?? 1,
      idEstacionamiento: int.parse(json['id_estacionamiento']?.toString() ?? '0'),
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
  static List<int> idsReales = [];

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

class _HomePageState extends State<HomePage>with SingleTickerProviderStateMixin {
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
  late TabController _tabController;

  // CAMBIO: Ahora usamos una lista en lugar de un solo token
  List<ReservaActiva> misReservas = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    ParkingState.initNotificaciones();
    _inicializarApp();
    _timerConsulta = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && seleccionado != null) _actualizarEstadoDesdeServidor();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  void _confirmarCancelacion(ReservaActiva reserva) {
    // 1. Obtener tiempo actual
    final DateTime ahora = DateTime.now();

    // 2. Parsear la hora de la base de datos (ya viene con la columna nueva del PHP)
    // Reemplazamos espacio por 'T' para que DateTime.parse no falle
    String raw = reserva.horaLlegada.trim().replaceFirst(' ', 'T');

    DateTime? horaLimite;
    try {
      horaLimite = DateTime.parse(raw);
    } catch (e) {
      debugPrint("Error parseando fecha: $e");
      // Si falla el parseo, mostramos error y no seguimos
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error al procesar la fecha de reserva"))
      );
      return;
    }

    // 3. Determinar si es tardío
    // Es tardío si la hora actual es DESPUÉS de la hora límite
    bool esTardio = ahora.isAfter(horaLimite);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "¿Confirmar Cancelación?",
          style: TextStyle(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: esTardio ? Colors.orange.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: esTardio ? Colors.orange : Colors.green,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    esTardio ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                    color: esTardio ? Colors.orange.shade900 : Colors.green.shade900,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      esTardio
                          ? "Cancelación tardía: Se aplicará una comisión del 25% por penalización."
                          : "¡Estás a tiempo! Se reembolsará el 100% de tu pago a tu saldo NexPark.",
                      style: TextStyle(
                        color: esTardio ? Colors.orange.shade900 : Colors.green.shade900,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Tu hora programada era:",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              reserva.horaLlegada, // Muestra la hora real que viene de la DB
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Al confirmar, el espacio se liberará inmediatamente.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("VOLVER", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(context);
              _ejecutarCancelacionEnServidor(reserva.token);
            },
            child: const Text(
              "SÍ, CANCELAR",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoExtender(ReservaActiva reserva) {
    int horasExtra = 1;
    String metodo = "Saldo";
    double precioHora = seleccionado?.precioHora ?? 0.0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double totalExtra = precioHora * horasExtra;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Extender Tiempo", style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("¿Cuántas horas deseas agregar al espacio C${reserva.espacio}?"),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                      onPressed: () => setDialogState(() => horasExtra > 1 ? horasExtra-- : null),
                    ),
                    Text("$horasExtra hr(s)", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                      onPressed: () => setDialogState(() => horasExtra++),
                    ),
                  ],
                ),
                const Divider(),
                RadioListTile(
                  title: const Text("Saldo NexPark"),
                  value: "Saldo",
                  groupValue: metodo,
                  onChanged: (v) => setDialogState(() => metodo = v!),
                ),
                RadioListTile(
                  title: const Text("Mercado Pago"),
                  value: "Mercado Pago",
                  groupValue: metodo,
                  onChanged: (v) => setDialogState(() => metodo = v!),
                ),
                const SizedBox(height: 10),
                Text(
                  "Total Extra: \$${totalExtra.toStringAsFixed(2)}",
                  style: const TextStyle(fontSize: 20, color: Colors.blue, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF166088)),
                onPressed: () {
                  Navigator.pop(context);
                  _procesarExtension(reserva.token, horasExtra, totalExtra, metodo);
                },
                child: const Text("PAGAR EXTENSIÓN", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _procesarExtension(String token, int horas, double monto, String metodo) async {
    try {
      final response = await http.post(
        Uri.parse('https://carlossalinas.webpro1213.com/api/extender_reserva.php'),
        body: {
          'token_qr': token,
          'horas_adicionales': horas.toString(),
          'monto': monto.toString(),
          'metodo': metodo,
          'id_usuario': idUsuario.toString(),
        },
      );

      final res = json.decode(response.body);
      if (res['status'] == 'success') {
        await _cargarDatosUsuarioServidor();
        await _obtenerReservas();
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Tiempo extendido con éxito"), backgroundColor: Colors.green),
        );
        _cargarDatosUsuarioServidor();
        _actualizarEstadoDesdeServidor();
      } else {
        _mostrarAlertaError("Error", res['message']);
      }
    } catch (e) {
      debugPrint("Error al extender: $e");
    }
  }

  void _mostrarAlertaError(String titulo, String mensaje) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                  "Espacio Ocupado",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
              ),
            ),
          ],
        ),
        content: Text(
          mensaje,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text("CERRAR", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Future<void> _ejecutarCancelacionEnServidor(String token) async {
    try {

      final response = await http.post(
        Uri.parse('https://carlossalinas.webpro1213.com/api/cancelar_reserva.php'),
        body: {'token_qr': token},
      );

      final res = json.decode(response.body);
      if (res['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']), backgroundColor: Colors.green),
        );
        _obtenerReservas();
        _cargarDatosUsuarioServidor();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint("Error al cancelar: $e");
    }
  }


  Future<void> _actualizarEstadoDesdeServidor() async {
    if (seleccionado == null) return;
    try {
      final response = await http.get(Uri.parse(
          "https://carlossalinas.webpro1213.com/api/get_espacios.php?id_estacionamiento=${seleccionado!.id}"));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        // 1. Aseguramos que la lista de IDs reales tenga el tamaño de la sucursal actual
        if (ParkingState.idsReales.length != seleccionado!.totalCajones) {
          ParkingState.idsReales = List.filled(seleccionado!.totalCajones, 0);
        }

        setState(() {
          for (var item in data) {
            // Usamos el numero_espacio para saber qué posición del Grid ocupar (ej: "1" -> index 0)
            int numEspacio = int.tryParse(item['numero_espacio'].toString()) ?? 0;
            int index = numEspacio - 1;

            if (index >= 0 && index < seleccionado!.totalCajones) {

              // 2. GUARDAMOS EL ID REAL DE LA DB (Vital para crear_reserva.php)
              ParkingState.idsReales[index] = int.parse(item['id_espacio'].toString());

              // 3. Cargamos preferencias de accesibilidad
              ParkingState.esDiscapacitado[index] = (item['es_discapacitado'].toString() == "1");

              // 4. Lógica de estados según el nuevo get_espacios.php
              String estadoAPI = item['estado'].toString();

              // Si el API dice 'libre', el cajón está disponible (Verde)
              // Si dice 'reservado' (Amarillo) u 'ocupado' (Rojo), marcamos como ocupado para el gesto
              ParkingState.ocupados[index] = (estadoAPI != 'libre');

              // 5. Lógica del cronómetro: Solo si el estado es físicamente 'ocupado'
              if (estadoAPI == 'ocupado' && item['fecha_fin'] != null) {
                DateTime horaFin = DateTime.parse(item['fecha_fin'].toString());
                int restantes = horaFin.difference(DateTime.now()).inSeconds;

                if (restantes > 0) {
                  ParkingState.tiempos[index] = restantes;
                  // Iniciamos el timer local de Flutter si no está corriendo
                  if (ParkingState.timers[index] == null || !ParkingState.timers[index]!.isActive) {
                    _reanimarTimerCajon(index);
                  }
                } else {
                  ParkingState.tiempos[index] = 0;
                }
              } else {
                // Si es 'reservado' (Amarillo), el tiempo se mantiene en 0
                // para que el UI muestre el texto "RESERVADO"
                ParkingState.tiempos[index] = 0;
                ParkingState.timers[index]?.cancel();
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Error de sincronización: $e");
    }
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
          _obtenerReservas();
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
    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/logowhite.png', height: 40, fit: BoxFit.contain),
        centerTitle: true,
        backgroundColor: const Color(0xFF166088),
        foregroundColor: Colors.white,
        // Usamos el controlador manual para sincronizar las pestañas
        bottom: TabBar(
          controller: _tabController,
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
          // LÓGICA DE ESTADOS (CARGANDO / SELECCIÓN)
          cargando
              ? const Center(child: CircularProgressIndicator())
              : seleccionado == null
              ? const Center(child: Text("Selecciona un estacionamiento"))
              : Column(
            children: [
              _buildInfoBanner(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildParkingGrid(),
                    const Center(child: Text("Vista de Mapa en desarrollo")),
                    _buildQRView(),
                  ],
                ),
              ),
            ],
          ),

          // CAPA DE CARGA AL CAMBIAR SUCURSAL
          if (cambiandoSucursal)
            Container(
              color: Colors.white.withOpacity(0.8),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
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
          // USAMOS FLEXIBLE PARA QUE EL CHIP SE ADAPTE SI EL NOMBRE ES MUY LARGO
          Flexible(
            child: ActionChip(
              avatar: const Icon(Icons.business, size: 16),
              // Si el nombre es muy largo, se mostrarán puntos suspensivos (...)
              label: Text(
                seleccionado?.nombre ?? "Seleccionar",
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: _mostrarDialogoSeleccion,
            ),
          ),

          const SizedBox(width: 10), // Espacio mínimo

          Row(
            children: [
              Chip(
                backgroundColor: Colors.green.shade50,
                // Si el saldo es grande, el chip crecerá pero el Flexible anterior cederá espacio
                label: Text(
                    "\$$saldo",
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)
                ),
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


  Widget _buildQRView() {
    // 1. FILTRO: Solo mostramos las reservas que coinciden con la sucursal que el usuario está viendo
    final reservasFiltradas = misReservas.where((r) {
      return r.idEstacionamiento == seleccionado?.id;
    }).toList();

    // 2. Si la lista global está vacía o no hay nada para este estacionamiento
    if (reservasFiltradas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text(
              misReservas.isEmpty
                  ? "No tienes reservas activas"
                  : "Sin reservas en ${seleccionado?.nombre}",
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF166088)),
              onPressed: _obtenerReservas,
              child: const Text("ACTUALIZAR", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    // 3. Mostramos solo los QRs filtrados
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: reservasFiltradas.length,
      itemBuilder: (context, index) {
        final r = reservasFiltradas[index];
        return Card(
          elevation: 4,
          margin: const EdgeInsets.only(bottom: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(r.nombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF166088))),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.access_time, size: 14, color: Colors.grey),
                    const SizedBox(width: 5),
                    Text(
                      "Llegada: ${r.horaLlegada.length > 16 ? r.horaLlegada.substring(11, 16) : r.horaLlegada}",
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  "Espacio: C${r.espacio}",
                  style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 15),
                Text(
                  r.horasPagadas > 1
                      ? "Tiempo: 1 hr + ${r.horasPagadas - 1} hr extra"
                      : "Tiempo: ${r.horasPagadas} hr",
                  style: const TextStyle(color: Color(0xFF166088), fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 15),
                QrImageView(data: r.token, size: 200, foregroundColor: const Color(0xFF166088)),
                const SizedBox(height: 15),

                // Botón para simular entrada
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                    onPressed: () => _simularEntradaQR(r.token),
                    icon: const Icon(Icons.check_circle),
                    label: const Text("SIMULAR ENTRADA"),
                  ),
                ),
                const SizedBox(height: 8),

                // Botón AUMENTAR TIEMPO
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                    onPressed: () => _mostrarDialogoExtender(r),
                    icon: const Icon(Icons.more_time),
                    label: const Text("AUMENTAR TIEMPO"),
                  ),
                ),
                const SizedBox(height: 8),

                // Botón para cancelar reserva
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    onPressed: () => _confirmarCancelacion(r),
                    icon: const Icon(Icons.cancel),
                    label: const Text("CANCELAR RESERVA"),
                  ),
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


  void _mostrarAlertaExito(String titulo, String mensaje) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),

        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                  titulo,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                )
            ),
          ],
        ),

        content: Text(mensaje),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Entendido"))],
      ),
    );
  }

  void _mostrarAlertaError(String titulo, String mensaje) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [Icon(Icons.error, color: Colors.red), SizedBox(width: 10), Text(titulo)]),
        content: Text(mensaje), // Aquí saldrá el mensaje del PHP: "El espacio ya está ocupado..."
        actions: [ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context), child: Text("Cerrar"))],
      ),
    );
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
          'id_espacio': ParkingState.idsReales[index].toString(),
          'monto': monto.toString(),
          'hora_llegada_estimada': llegadaProgramada.trim(),
          'metodo': metodo,
          'horas': horas.toString(),
          'nombre_reserva': nombreR,
        },
      );

      final res = json.decode(response.body);

      if (res['status'] == 'success') {
        // CASO DE ÉXITO
        if (metodo == "Saldo") {
          homeState.setState(() => ParkingState.ocupados[index] = true);
          await homeState._cargarDatosUsuarioServidor();
          await homeState._obtenerReservas();

          await homeState._actualizarEstadoDesdeServidor();
          // Notificación en la barra de estado
          ParkingState.notificar("¡Reserva Confirmada! Lugar: C${index + 1} para $nombreR.");

          if (mounted) {
            _mostrarAlertaExito("¡Reserva Exitosa!", "Tu lugar ha sido apartado correctamente.");
            homeState._tabController.animateTo(2);
          }
        } else {
          // Si es Mercado Pago, el WebView se encarga del resto
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => PagoWebView(url: res['url_pago'])));
          if (result == "success") {
            homeState._cargarDatosUsuarioServidor();
            homeState._obtenerReservas();
            homeState._tabController.animateTo(2);
          }
        }
      } else {
        // --- CASO DE ERROR (Colisión o falta de saldo) ---
        ParkingState.notificar("Error: No se pudo completar la reserva.");
        if (mounted) {
          _mostrarAlertaError("Registro Fallido", res['message'] ?? "Error desconocido");
        }
      }
    } catch (e) {
      debugPrint("Error en proceso de pago: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool ocupado = ParkingState.ocupados[widget.index];
    bool esDis = ParkingState.esDiscapacitado[widget.index];
    int tiempoRestante = ParkingState.tiempos[widget.index];

    // LÓGICA DE COLORES CORREGIDA:
    Color colorCajon;

    if (!ocupado) {
      // ESTADO: LIBRE
      colorCajon = esDis ? Colors.blue.shade600 : Colors.green.shade500;
    } else {
      // ESTADO: RESERVADO U OCUPADO
      if (tiempoRestante > 0) {
        // Ocupado físicamente (el coche ya llegó)
        colorCajon = Colors.red.shade400;
      } else {
        // Estado "Apartado" (aún no escanean el QR)
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