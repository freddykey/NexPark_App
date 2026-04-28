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
import 'home_page.dart';
import 'mis_vehiculos.dart';
import 'ticket_page.dart';
import 'dart:async';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

// MODELOS DE DATOS

class Estacionamiento {
  final int id;
  final String nombre;
  final int totalCajones;
  final int niveles;
  final double precioHora;
  final String horaApertura;
  final String horaCierre;

  Estacionamiento({
    required this.id,
    required this.nombre,
    required this.totalCajones,
    required this.niveles,
    required this.precioHora,
    required this.horaApertura,
    required this.horaCierre,
  });

  factory Estacionamiento.fromJson(Map<String, dynamic> json) {
    return Estacionamiento(
      id: int.tryParse(json['id']?.toString() ?? json['id_estacionamiento']?.toString() ?? '0') ?? 0,
      nombre: json['nombre']?.toString() ?? "Sin nombre",
      totalCajones: int.tryParse(json['totalCajones']?.toString() ?? json['total_cajones']?.toString() ?? '0') ?? 0,
      niveles: int.tryParse(json['niveles']?.toString() ?? '1') ?? 1,
      precioHora: double.tryParse(json['precio_hora']?.toString() ?? '0.0') ?? 0.0,
      horaApertura: json['hora_apertura'] ?? "00:00:00",
      horaCierre: json['hora_cierre'] ?? "23:59:59",
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
  final String estado;


  ReservaActiva({
    required this.token,
    required this.nombre,
    required this.espacio,
    required this.horaLlegada,
    required this.horasPagadas,
    required this.idEstacionamiento,
    required this.estado,
  });

  factory ReservaActiva.fromJson(Map<String, dynamic> json) {
    return ReservaActiva(
      token: json['token_qr'] ?? '',
      nombre: json['nombre_reserva'] ?? 'Sin nombre',
      espacio: json['numero_espacio']?.toString() ?? '',

      horaLlegada: json['hora_llegada_estimada']?.toString() ?? '',
      horasPagadas: int.tryParse(json['horas_pagadas']?.toString() ?? '1') ?? 1,
      idEstacionamiento: int.parse(json['id_estacionamiento']?.toString() ?? '0'),
      estado: json['estado']?.toString() ?? 'programada',
    );
  }
}

// GESTIÓN DE ESTADO

class ParkingState {
  static List<bool> ocupados = [];
  static List<int> tiempos = [];
  static List<bool> esDiscapacitado = [];
  static List<bool> esElectrico = [];
  static List<Timer?> timers = [];
  static final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
  static List<int> idsReales = [];
  static List<int> duenos = [];
  static int idUsuarioActual = 0;

  static void prepararCajones(int cantidad) {
    if (ocupados.length != cantidad) {
      ocupados = List.filled(cantidad, false);
      tiempos = List.filled(cantidad, 0);
      esDiscapacitado = List.filled(cantidad, false);
      esElectrico = List.filled(cantidad, false);
      timers = List.generate(cantidad, (_) => null);
      duenos = List.filled(cantidad, 0);
    }
  }

  static Future<void> initNotificaciones() async {
    await Permission.notification.request();
    const androidSettings = AndroidInitializationSettings('launcher_icon');
    await notifications.initialize(const InitializationSettings(android: androidSettings));
  }

  static void notificar(String mensaje) async {
    const androidDetails = AndroidNotificationDetails(
      'canal_nexpark',
      'NexPark Alerts',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'launcher_icon', // <--- AGREGA ESTA LÍNEA (asegúrate que se llame igual que en tu AndroidManifest)
    );
    await notifications.show(
        0,
        'NexPark',
        mensaje,
        const NotificationDetails(android: androidDetails)
    );
  }

  static String formatearTiempo(int segundosTotales) {
    int horas = segundosTotales ~/ 3600;
    int minutos = (segundosTotales % 3600) ~/ 60;
    int segundos = segundosTotales % 60;
    return "${horas.toString().padLeft(2, '0')}:${minutos.toString().padLeft(2, '0')}:${segundos.toString().padLeft(2, '0')}";
  }
}

// PÁGINA PRINCIPAL

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

  final ScreenshotController screenshotController = ScreenshotController();

  List<ReservaActiva> misReservas = [];

  @override
  void initState() {
    super.initState();
    _pedirPermisoNotificaciones();
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
    _obtenerReservas();
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

  Future<void> _pedirPermisoNotificaciones() async {
    // Esto hará que aparezca el cuadro de "NexPark quiere enviarte notificaciones. ¿Permitir?"
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> _compartirQRCompleto(String token, String espacio) async {
    try {
      // Captura el widget que esté envuelto en Screenshot()
      final image = await screenshotController.capture();

      if (image != null) {
        // Obtener directorio temporal para guardar la imagen
        final directory = await getTemporaryDirectory();
        final imagePath = await File('${directory.path}/qr_nexpark.png').create();
        await imagePath.writeAsBytes(image);

        // Compartir archivo + texto descriptivo
        await Share.shareXFiles(
          [XFile(imagePath.path)],
          text: '🔑 *Acceso NexPark*\n'
              '📍 Lugar: $espacio\n'
              '🎟️ Token: $token\n\n'
              'Presenta esta imagen en el lector para ingresar.',
        );
      }
    } catch (e) {
      debugPrint("Error al compartir: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo generar la imagen para compartir")),
      );
    }
  }

  void _confirmarCancelacion(ReservaActiva reserva) {

    final DateTime ahora = DateTime.now();


    String raw = reserva.horaLlegada.trim().replaceFirst(' ', 'T');

    DateTime? horaLimite;
    try {
      horaLimite = DateTime.parse(raw);
    } catch (e) {
      debugPrint("Error parseando fecha: $e");

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error al procesar la fecha de reserva"))
      );
      return;
    }

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
              reserva.horaLlegada,
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

        if (ParkingState.idsReales.length != seleccionado!.totalCajones) {
          ParkingState.idsReales = List.filled(seleccionado!.totalCajones, 0);
          ParkingState.esDiscapacitado = List.filled(seleccionado!.totalCajones, false);
          ParkingState.esElectrico = List.filled(seleccionado!.totalCajones, false);
        }

        setState(() {
          ParkingState.idUsuarioActual = idUsuario;
          for (var item in data) {
            int numEspacio = int.tryParse(item['numero_espacio'].toString()) ?? 0;
            int index = numEspacio - 1;

            if (index >= 0 && index < seleccionado!.totalCajones) {
              ParkingState.idsReales[index] = int.parse(item['id_espacio'].toString());
              ParkingState.esDiscapacitado[index] = (item['es_discapacitado'].toString() == "1");
              ParkingState.esElectrico[index] = (item['es_electrico'].toString() == "1");
              ParkingState.duenos[index] = int.tryParse(item['dueno_reserva'].toString()) ?? 0;

              String estadoAPI = item['estado'].toString();

              // 1. GESTIÓN DE OCUPADO (Físico o Reserva activa)
              ParkingState.ocupados[index] = (estadoAPI == 'ocupado');

              if (estadoAPI == 'ocupado' && item['fecha_fin'] != null) {
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
              }
              // 2. GESTIÓN DE APARTADO (Naranja para Usuario B)
              else if (estadoAPI == 'reservado') {
                // El PHP ya calculó que faltan menos de 15 min. Marcamos -1.
                ParkingState.tiempos[index] = -1;
                ParkingState.timers[index]?.cancel();
              }
              // 3. GESTIÓN DE RESERVA FUTURA (Verde con Aviso)
              else if (estadoAPI == 'reservado_futuro') {
                // El PHP ya calculó que falta mucho tiempo. Marcamos -2.
                ParkingState.tiempos[index] = -2;
                ParkingState.timers[index]?.cancel();
              }
              // 4. LIBRE TOTAL
              else {
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
        backgroundColor: const Color(0xFF166088),
        foregroundColor: Colors.white,

        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logowhite.png', height: 30, fit: BoxFit.contain),
            const SizedBox(height: 4),
            Text(
              "¡Bienvenido, $nombre!",
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.white70
              ),
            ),
          ],
        ),
        centerTitle: true,
        toolbarHeight: 70,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.local_parking), text: "Cajones"),
            Tab(icon: Icon(Icons.map), text: "Mapa"),
            Tab(icon: Icon(Icons.qr_code), text: "QR"),
          ],
        ),
      ),
      drawer: _buildDrawer(),

      body: SafeArea(
        child: Stack(
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
          ListTile(
            leading: const Icon(Icons.directions_car, color: Color(0xFF166088)),
            title: const Text("Mis Vehículos"),
            onTap: () {
              Navigator.pop(context); // Cierra el drawer
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MisVehiculos()));
            },
          ),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.airplane_ticket, color: Color(0xFF166088)),
            title: const Text("Ticket"),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TicketPage())),
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
            child: Text("NexPark Alpha-v0.10.0", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {

    if (seleccionado == null) return const SizedBox.shrink();
    final String apertura = seleccionado!.horaApertura.substring(0, 5);
    final String cierre = seleccionado!.horaCierre.substring(0, 5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: ActionChip(
                  avatar: const Icon(Icons.business, size: 16),
                  label: Text(
                    seleccionado!.nombre,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _mostrarDialogoSeleccion,
                ),
              ),
              const SizedBox(width: 10),
              Row(
                children: [
                  Chip(
                    backgroundColor: Colors.green.shade50,
                    label: Text(
                        "\$$saldo",
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)
                    ),
                  ),
                  if (seleccionado!.niveles > 1) ...[
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: pisoSeleccionado,
                      underline: const SizedBox(),
                      items: List.generate(seleccionado!.niveles, (i) => i + 1)
                          .map((p) => DropdownMenuItem(value: p, child: Text("Piso $p")))
                          .toList(),
                      onChanged: (v) => setState(() => pisoSeleccionado = v!),
                    ),
                  ]
                ],
              ),
            ],
          ),

          // SECCIÓN DE HORARIO REAL (BASE DE DATOS)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time_filled, size: 14, color: Colors.blueGrey.shade700),
                const SizedBox(width: 6),
                Text(
                  "Horario de servicio: $apertura - $cierre hrs",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey.shade900,
                  ),
                ),
              ],
            ),
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
    final reservasFiltradas = misReservas.where((r) {
      return r.idEstacionamiento == seleccionado?.id &&
          (r.estado == 'programada' || r.estado == 'apartado' || r.estado == 'activo');
    }).toList();

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

    return ListView.builder(
      padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 80),
      itemCount: reservasFiltradas.length,
      itemBuilder: (context, index) {
        final r = reservasFiltradas[index];

        // --- SOLUCIÓN: Creamos un controlador único para cada tarjeta ---
        final ScreenshotController localController = ScreenshotController();

        return Card(
          elevation: 4,
          margin: const EdgeInsets.only(bottom: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(r.nombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF166088))),
                const SizedBox(height: 5),
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
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 5),
                Text(
                  "Tiempo total: ${r.horasPagadas} ${r.horasPagadas == 1 ? 'hr' : 'hrs'}",
                  style: const TextStyle(
                      color: Color(0xFF166088),
                      fontWeight: FontWeight.bold,
                      fontSize: 15
                  ),
                ),

                const SizedBox(height: 15),

                // --- ÁREA DE CAPTURA CON EL CONTROLADOR LOCAL ---
                Screenshot(
                  controller: localController,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        QrImageView(
                            data: r.token,
                            size: 200,
                            foregroundColor: const Color(0xFF166088)
                        ),
                        const SizedBox(height: 10),
                        const Text(
                            "TOKEN DE ACCESO",
                            style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)
                        ),
                        Text(
                          r.token,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF166088),
                              letterSpacing: 2
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // BOTÓN DE COMPARTIR USANDO EL CONTROLADOR LOCAL
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    onPressed: () => _compartirTicketEspecifico(localController, r.token, r.espacio),
                    icon: const Icon(Icons.share),
                    label: const Text("COMPARTIR ACCESO"),
                  ),
                ),

                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),

                // BOTONES DE ACCIÓN RESTANTES


                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                    onPressed: () => _mostrarDialogoExtender(r),
                    icon: const Icon(Icons.more_time),
                    label: const Text("AUMENTAR TIEMPO"),
                  ),
                ),
                const SizedBox(height: 12),

                if (r.estado.toLowerCase() != 'activo')
                  SizedBox(
                    width: double.infinity,
                    height: 48,
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

// NUEVA FUNCIÓN DE COMPARTIR QUE RECIBE EL CONTROLADOR
  Future<void> _compartirTicketEspecifico(ScreenshotController controller, String token, String espacio) async {
    try {
      final image = await controller.capture();
      if (image != null) {
        final directory = await getTemporaryDirectory();
        final imagePath = await File('${directory.path}/qr_$token.png').create();
        await imagePath.writeAsBytes(image);

        await Share.shareXFiles(
          [XFile(imagePath.path)],
          text: '🔑 *Acceso NexPark*\n📍 Lugar: C$espacio\n🎟️ Token: $token\n\nPresenta esta imagen en el lector.',
        );
      }
    } catch (e) {
      debugPrint("Error al compartir: $e");
    }
  }
}


class ParkingSlotItem extends StatefulWidget {
  final int index;

  const ParkingSlotItem({super.key, required this.index});
  @override
  State<ParkingSlotItem> createState() => _ParkingSlotItemState();
}

class _ParkingSlotItemState extends State<ParkingSlotItem> {
  dynamic vehiculoSeleccionado;
  List<dynamic> misVehiculosParaReserva = [];
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

  void _verificarSaldoYReservar(int index) {
    final homeState = context.findAncestorStateOfType<_HomePageState>();
    if (homeState == null) return;

    double saldoActual = double.tryParse(homeState.saldo) ?? 0.0;

    if (saldoActual < 50.0) {

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).removeCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade900,
          duration: const Duration(seconds: 5), // Un poco más de tiempo para que lea los dos botones
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(15),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "¡Saldo bajo! Se recomienda recargar.",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // BOTÓN PARA HACERLO DESPUÉS
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    },
                    child: const Text("LUEGO", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  // BOTÓN PARA RECARGAR
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.orange.shade900,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const RecargaPage()));
                    },
                    child: const Text("RECARGAR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }

  void _mostrarQRIndividual(int index) {
    final homeState = context.findAncestorStateOfType<_HomePageState>();
    if (homeState == null) return;

    final int idEspacioTocado = ParkingState.idsReales[index];
    final String nombreCajonTocado = "C${index + 1}";

    ReservaActiva? reservaEncontrada;
    try {
      reservaEncontrada = homeState.misReservas.firstWhere((r) {
        String espacioLimpio = r.espacio.replaceAll(RegExp(r'[^0-9]'), '');
        return r.idEstacionamiento == idEspacioTocado || espacioLimpio == (index + 1).toString();
      });
    } catch (e) { reservaEncontrada = null; }

    if (reservaEncontrada == null) return;

    showDialog(
      context: context,
      builder: (context) {
        Timer? localTimer;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool estaActiva = reservaEncontrada!.estado.toLowerCase() == 'activo';
            int segundosRestantes = ParkingState.tiempos[index];

            if (estaActiva && segundosRestantes <= 0) {
              try {
                DateTime ahora = DateTime.now();
                DateTime horaLlegada = DateTime.parse(reservaEncontrada!.horaLlegada);
                DateTime horaFinEstimada = horaLlegada.add(Duration(hours: reservaEncontrada!.horasPagadas));
                segundosRestantes = horaFinEstimada.difference(ahora).inSeconds;
              } catch (e) {
                segundosRestantes = 0;
              }
            }

            if (localTimer == null) {
              localTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
                if (context.mounted) {
                  setDialogState(() {});
                } else {
                  timer.cancel();
                }
              });
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: EdgeInsets.zero,
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stars, color: Colors.amber, size: 40),
                      const SizedBox(height: 10),
                      Text(reservaEncontrada!.nombre,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),

                      // --- CUADRO DE TIEMPO (RESTANTE O LLEGADA) ---
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: estaActiva
                                ? Colors.green.withOpacity(0.1)
                                : Colors.blueGrey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            Text(
                              estaActiva ? "TIEMPO RESTANTE" : "LLEGADA ESTIMADA",
                              style: TextStyle(
                                  fontSize: 10,
                                  color: estaActiva ? Colors.green.shade700 : Colors.blueGrey,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              estaActiva
                                  ? (segundosRestantes > 0
                                  ? ParkingState.formatearTiempo(segundosRestantes)
                                  : "EXPIRADO")
                                  : (reservaEncontrada!.horaLlegada.length > 16
                                  ? reservaEncontrada!.horaLlegada.substring(11, 16)
                                  : reservaEncontrada!.horaLlegada),
                              style: TextStyle(
                                color: estaActiva ? Colors.green.shade800 : Colors.blueGrey.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: estaActiva ? 28 : 20,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),

                      // --- NUEVO: INDICADOR DE TIEMPO TOTAL CONTRATADO ---
                      const SizedBox(height: 12),
                      Text(
                        "Tiempo total contratado: ${reservaEncontrada!.horasPagadas} ${reservaEncontrada!.horasPagadas == 1 ? 'hr' : 'hrs'}",
                        style: const TextStyle(
                          color: Color(0xFF166088),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --- ÁREA DE CAPTURA (SOLO QR Y TOKEN) ---
                      Screenshot(
                        controller: homeState.screenshotController,
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              QrImageView(
                                data: reservaEncontrada!.token,
                                size: 180,
                                foregroundColor: const Color(0xFF166088),
                              ),
                              const SizedBox(height: 10),
                              const Text("TOKEN DE ACCESO",
                                  style: TextStyle(fontSize: 9, color: Colors.grey)),
                              const SizedBox(height: 5),
                              Text(
                                reservaEncontrada!.token,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF166088),
                                    letterSpacing: 2),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 25),

                      // BOTÓN COMPARTIR
                      _botonPrincipal(
                        "COMPARTIR ACCESO",
                        Icons.share,
                        Colors.teal.shade700,
                            () {
                          homeState._compartirQRCompleto(
                              reservaEncontrada!.token, "C${index + 1}");
                        },
                      ),

                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),

                      // BOTÓN AUMENTAR TIEMPO
                      _botonPrincipal(
                        "AUMENTAR TIEMPO",
                        Icons.more_time,
                        Colors.blue.shade700,
                            () {
                          localTimer?.cancel();
                          Navigator.pop(context);
                          homeState._mostrarDialogoExtender(reservaEncontrada!);
                        },
                      ),

                      // BOTÓN CANCELAR (SOLO SI NO ESTÁ ACTIVA)
                      if (!estaActiva) ...[
                        const SizedBox(height: 12),
                        _botonSecundario(
                          "CANCELAR RESERVA",
                          Icons.cancel,
                          Colors.red,
                              () {
                            localTimer?.cancel();
                            Navigator.pop(context);
                            homeState._confirmarCancelacion(reservaEncontrada!);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }


  Widget _botonPrincipal(String t, IconData i, Color c, VoidCallback p) => SizedBox(
    width: double.infinity, height: 48,
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      onPressed: p, icon: Icon(i, size: 18), label: Text(t),
    ),
  );

  Widget _botonSecundario(String t, IconData i, Color c, VoidCallback p) => SizedBox(
    width: double.infinity, height: 48,
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(foregroundColor: c, side: BorderSide(color: c, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      onPressed: p, icon: Icon(i, size: 18), label: Text(t),
    ),
  );

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
        content: Text(mensaje),
        actions: [ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context), child: Text("Cerrar"))],
      ),
    );
  }

  Future<bool?> _mostrarAlertaTipoCajon(String titulo, String mensaje) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(mensaje),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("NO")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF166088)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("SÍ", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
  }

  Future<void> _seleccionarHoraLlegada(BuildContext context, StateSetter setDialogState) async {
    final DateTime ahora = DateTime.now();

    final TimeOfDay? horaSeleccionada = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.dial,
      helpText: "INGRESA HORA DE LLEGADA",
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );

    if (horaSeleccionada == null) return;

    DateTime fechaFinal = DateTime(
      ahora.year, ahora.month, ahora.day,
      horaSeleccionada.hour, horaSeleccionada.minute,
    );

    if (fechaFinal.isBefore(ahora.subtract(const Duration(minutes: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Esta hora ya pasó"), backgroundColor: Colors.red),
      );
      setDialogState(() {
        llegadaProgramada = "INVÁLIDA";
      });
      return;
    }

    setDialogState(() {
      llegadaProgramada = fechaFinal.toString().substring(0, 19);
    });
  }

  Future<void> _cargarVehiculosUsuario() async {
    final homeState = context.findAncestorStateOfType<_HomePageState>();
    if (homeState == null) return;

    try {
      final response = await http.get(Uri.parse(
          "https://carlossalinas.webpro1213.com/api/get_vehiculos.php?id_usuario=${homeState.idUsuario}"));
      if (response.statusCode == 200) {
        setState(() {
          misVehiculosParaReserva = json.decode(response.body);
        });
      }
    } catch (e) {
      debugPrint("Error cargando vehículos: $e");
    }
  }

  void _confirmarReserva(int index) async {
    await _cargarVehiculosUsuario();
    final homeState = context.findAncestorStateOfType<_HomePageState>();
    if (homeState == null) return;

    final est = homeState.seleccionado!;
    final TextEditingController nombreController = TextEditingController(text: "Reserva C${index + 1}");

    // 1. CHECK DE DISPONIBILIDAD FUTURA (Tu lógica existente)
    try {
      final checkRes = await http.get(Uri.parse(
          'https://carlossalinas.webpro1213.com/api/check_disponibilidad.php?id_espacio=${ParkingState.idsReales[index]}'
      )).timeout(const Duration(seconds: 5));

      if (checkRes.statusCode == 200) {
        final data = json.decode(checkRes.body);
        if (data['status'] == 'busy_future') {
          DateTime proxima = DateTime.parse(data['proxima_reserva']);
          DateTime limiteReal = proxima.subtract(const Duration(minutes: 15));
          String horaFormateada = "${proxima.hour.toString().padLeft(2, '0')}:${proxima.minute.toString().padLeft(2, '0')}";

          bool? continuar = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("⚠️ ¡Aviso de tiempo!"),
              content: Text("Este cajón tiene una reserva a las $horaFormateada.\n\nDebes terminar antes de las ${limiteReal.hour}:${limiteReal.minute.toString().padLeft(2, '0')}.\n¿Continuar?"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("VOLVER")),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("SÍ, ENTIENDO")),
              ],
            ),
          );
          if (continuar != true) return;
        }
      }
    } catch (e) {
      debugPrint("Error en check preventivo: $e");
    }

    // 2. VALIDACIONES DE TIPO DE CAJÓN (Tu lógica existente)
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

    // 3. DIÁLOGO DE CONFIGURACIÓN CON BLOQUEOS
    int horas = 1;
    String metodo = "Saldo";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {

          // >>> AQUÍ AGREGAS LA LÓGICA DE VALIDACIÓN <<<
          bool horaPasada = llegadaProgramada == "INVÁLIDA";
          bool fueraDeHorario = false;

          if (!horaPasada) {
            DateTime entrada = DateTime.parse(llegadaProgramada);
            DateTime salida = entrada.add(Duration(hours: horas));

            int minEntrada = entrada.hour * 60 + entrada.minute;
            int minSalida = salida.hour * 60 + salida.minute;

            // Usamos 'est' que ya lo tienes definido unas líneas arriba en tu función
            int minApertura = int.parse(est.horaApertura.split(':')[0]) * 60 + int.parse(est.horaApertura.split(':')[1]);
            int minCierre = int.parse(est.horaCierre.split(':')[0]) * 60 + int.parse(est.horaCierre.split(':')[1]);

            if (minEntrada < minApertura || minSalida > minCierre) {
              fueraDeHorario = true;
            }
          }

          // Esta variable controla si el botón se puede presionar
          bool botonBloqueado = horaPasada || fueraDeHorario;
          double total = 5.0 + (est.precioHora * horas);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text("Reserva Cajón C${index + 1}"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Mensaje de error visual (Opcional pero recomendado)
                  if (fueraDeHorario)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        "🚫 Horario no disponible\nCierre: ${est.horaCierre.substring(0,5)}",
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // Selector de vehículo
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300)
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text("Seleccionar vehículo (Opcional)"),
                        value: (vehiculoSeleccionado is Map)
                            ? vehiculoSeleccionado['id_vehiculo'].toString()
                            : vehiculoSeleccionado?.toString(),
                        items: [
                          DropdownMenuItem(
                            value: "agregar",
                            child: Row(
                              children: [
                                Icon(Icons.add_circle, color: Colors.blue.shade700, size: 20),
                                const SizedBox(width: 10),
                                const Text("Agregar nuevo", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          ...misVehiculosParaReserva.map((v) {
                            return DropdownMenuItem<String>(
                              value: v['id_vehiculo'].toString(),
                              child: Text("${v['modelo']} (${v['placa']})"),
                            );
                          }).toList(),
                        ],
                        onChanged: (val) {
                          if (val == "agregar") {
                            Navigator.pop(context);
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const MisVehiculos()))
                                .then((_) => _confirmarReserva(index));
                          } else {
                            setDialogState(() => vehiculoSeleccionado = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: nombreController,
                    decoration: const InputDecoration(labelText: "Nombre para tu reserva", prefixIcon: Icon(Icons.edit)),
                  ),
                  const SizedBox(height: 10),

                  // Selector de Horario con Etiqueta Superior
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: "Seleccionar horario",
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.access_time, color: Color(0xFF166088)),
                      title: Text(llegadaProgramada == "INVÁLIDA"
                          ? "⚠️ Hora no válida (Toca aquí)"
                          : llegadaProgramada.substring(11, 16)),
                      onTap: () => _seleccionarHoraLlegada(context, setDialogState),
                    ),
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
                // BOTÓN BLOQUEADO SI LA HORA ES INVÁLIDA O EXCEDE EL CIERRE
                onPressed: botonBloqueado ? null : () {
                  if (metodo == "Saldo" && double.parse(homeState.saldo) < total) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saldo insuficiente")));
                    return;
                  }

                  String idVehiculoAEnviar = "null";
                  if (vehiculoSeleccionado != null && vehiculoSeleccionado != "agregar") {
                    idVehiculoAEnviar = (vehiculoSeleccionado is Map)
                        ? vehiculoSeleccionado['id_vehiculo'].toString()
                        : vehiculoSeleccionado.toString();
                  }

                  Navigator.pop(context);

                  _procesarPago(
                      index,
                      est,
                      horas,
                      total,
                      metodo,
                      nombreController.text,
                      idVehiculoAEnviar
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: botonBloqueado ? Colors.grey : null,
                ),
                child: const Text("Confirmar Pago"),
              )
            ],
          );
        },
      ),
    );
  }




// ... aquí sigue el resto de tu clase ...
  void _procesarPago(int index, Estacionamiento est, int horas, double monto, String metodo, String nombreR, String idVehiculo) async {
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
          'hora_llegada_estimada': llegadaProgramada.substring(0, 19),
          'metodo': metodo,
          'horas': horas.toString(),
          'nombre_reserva': nombreR,
          'id_vehiculo': idVehiculo,
        },
      );

      final res = json.decode(response.body);

      if (res['status'] == 'success') {

        if (metodo == "Saldo") {
          homeState.setState(() => ParkingState.ocupados[index] = true);
          await homeState._cargarDatosUsuarioServidor();
          await homeState._obtenerReservas();
          await homeState._actualizarEstadoDesdeServidor();

          ParkingState.notificar("¡Reserva Confirmada! Lugar: C${index + 1} para $nombreR.");

          if (mounted) {
            _mostrarAlertaExito("¡Reserva Exitosa!", "Tu lugar ha sido apartado correctamente.");
            homeState._tabController.animateTo(2);
          }
        } else {

          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => PagoWebView(url: res['url_pago'])));
          if (result == "success") {
            homeState._cargarDatosUsuarioServidor();
            homeState._obtenerReservas();
            homeState._tabController.animateTo(2);
          }
        }
      } else {

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
    bool esElec = ParkingState.esElectrico[widget.index];
    int tiempoRestante = ParkingState.tiempos[widget.index]; // -1: cortesía, -2: futura lejana
    int idDueno = ParkingState.duenos[widget.index];
    bool soyYo = (idDueno != 0 && idDueno == ParkingState.idUsuarioActual);

    // --- LÓGICA DE COLORES Y ICONOS ---
    Color colorCajon;
    IconData iconoCajon;
    String textoAbajo = "";

    if (soyYo) {
      colorCajon = Colors.yellow.shade700;
      iconoCajon = Icons.stars;
      textoAbajo = (tiempoRestante > 0)
          ? ParkingState.formatearTiempo(tiempoRestante)
          : "MI LUGAR";
    } else if (ocupado) {
      colorCajon = Colors.red.shade400;
      iconoCajon = Icons.lock;
      textoAbajo = "OCUPADO";
    } else if (tiempoRestante == -1) {
      // ESTADO APARTADO (Menos de 15 min para que llegue el dueño A) 
      colorCajon = Colors.orange.shade400;
      iconoCajon = Icons.history;
      textoAbajo = "APARTADO";
    } else {
      // ESTADO LIBRE O RESERVA FUTURA (Aquí entra el Usuario B cuando faltan 5 horas)
      if (esDis) {
        colorCajon = Colors.blue.shade600;
        iconoCajon = Icons.accessible;
      } else if (esElec) {
        colorCajon = Colors.teal.shade500;
        iconoCajon = Icons.bolt;
      } else {
        // Si tiene una reserva futura lejana (-2), lo pintamos verde igual para el Usuario B
        colorCajon = Colors.green.shade500;
        iconoCajon = Icons.local_parking;
      }
      textoAbajo = "LIBRE";
    }

    return GestureDetector(
      onTap: () {
        _verificarSaldoYReservar(widget.index);

        if (soyYo) {
          _mostrarQRIndividual(widget.index);
          return;
        }

        // 2. Bloqueo físico: Alguien está dentro
        if (ocupado) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Este cajón está ocupado actualmente")),
          );
          return;
        }

        // 3. Bloqueo de Cortesía: El Usuario A llega en menos de 15 min
        if (tiempoRestante == -1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Espacio reservado: El dueño está por llegar")),
          );
          return;
        }

        // 4. DISPONIBILIDAD PARA USUARIO B
        // Si tiempoRestante es 0 (libre) o -2 (reserva futura del Usuario A a las 5 horas)
        // el Usuario B SÍ PUEDE presionar y abrir el diálogo de reserva.
        _confirmarReserva(widget.index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
            color: colorCajon,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
                color: soyYo ? Colors.black87 : Colors.black12,
                width: soyYo ? 3 : 1
            )
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconoCajon, color: soyYo ? Colors.black87 : Colors.white, size: 35),
            Text(
                "C${widget.index + 1}",
                style: TextStyle(
                    color: soyYo ? Colors.black87 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18
                )
            ),
            if (textoAbajo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                    textoAbajo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: soyYo ? Colors.black87 : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold
                    )
                ),
              ),
          ],
        ),
      ),
    );
  }
}