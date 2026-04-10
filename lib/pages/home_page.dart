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
      precioHora: double.tryParse(json['precio_hora']?.toString() ?? '10.0') ?? 10.0,
    );
  }
}

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
  String? tokenQRActual;

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
    _obtenerTokenQR();
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
              bool estaOcupado = (item['estado'].toString() != 'libre');
              ParkingState.ocupados[index] = estaOcupado;

              if (estaOcupado && item['fecha_fin'] != null) {
                DateTime horaFin = DateTime.parse(item['fecha_fin'].toString());
                int restantes = horaFin.difference(DateTime.now()).inSeconds;
                if (restantes > 0) {
                  ParkingState.tiempos[index] = restantes;
                  if (ParkingState.timers[index] == null || !ParkingState.timers[index]!.isActive) {
                    _reanimarTimerCajon(index);
                  }
                }
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

  Future<void> _simularEntradaQR() async {
    if (tokenQRActual == null) return;

    try {
      final response = await http.post(
        Uri.parse('https://carlossalinas.webpro1213.com/api/validar_entrada.php'),
        body: {'token_qr': tokenQRActual},
      );

      print("Status Code: ${response.statusCode}");
      print("Cuerpo crudo: '${response.body}'"); // Fíjate si esto sale vacío en la consola

      if (response.body.isEmpty) {
        print("EL SERVIDOR DEVOLVIÓ UN TEXTO VACÍO");
        return;
      }

      final res = json.decode(response.body);
      // ... resto del código ...

      if (res['status'] == 'success') {
        // Si entra aquí, el botón SI sirve y el PHP respondió bien
        await _actualizarEstadoDesdeServidor();
        setState(() { tokenQRActual = null; });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("¡Entrada exitosa!"), backgroundColor: Colors.green),
        );
      } else {
        // Aquí verás el error que te manda el PHP (ej: "No se encontró reserva")
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Servidor dice: ${res['message']}"), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      print("Error de red o código: $e");
    }
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

  Future<void> _obtenerTokenQR() async {
    try {
      final response = await http.post(
        Uri.parse('https://carlossalinas.webpro1213.com/api/get_reserva_activa.php'),
        body: {'id_usuario': idUsuario.toString()},
      );
      final res = json.decode(response.body);
      setState(() => tokenQRActual = (res['status'] == 'success') ? res['token_qr'] : null);
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
              subtitle: Text("${est.totalCajones} cajones • \$${est.precioHora}/hr"),
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
                      _buildQRView(),

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
            child: Text("NexPark Alpha-v0.4.5", style: TextStyle(color: Colors.grey, fontSize: 12)),
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

  Widget _buildQRView() {
    if (tokenQRActual == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner, size: 80, color: Colors.grey),
            const SizedBox(height: 10),
            const Text("No tienes reservas activas", style: TextStyle(color: Colors.grey)),
            ElevatedButton(onPressed: _obtenerTokenQR, child: const Text("Actualizar")),

          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Tu Pase QR", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF166088))),
          const SizedBox(height: 20),
          QrImageView(data: tokenQRActual!, size: 250, foregroundColor: const Color(0xFF166088)),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text("Escanea este código al llegar.", textAlign: TextAlign.center),


          ),
          const SizedBox(height: 10),

          // --- BOTÓN DE SIMULACIÓN AQUÍ ---
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.check_circle),
            label: const Text("SIMULAR ENTRADA (Check-in)"),
            onPressed: () => _simularEntradaQR(),
          ),
          const SizedBox(height: 30),
        ],
      ),
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

    // Validación de espacio azul (del código 1)
    if (ParkingState.esDiscapacitado[index]) {
      bool? continuar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Espacio Azul"),
          content: const Text("Este espacio es para uso exclusivo de personas con discapacidad. ¿Deseas continuar?"),
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
                  ListTile(
                    leading: const Icon(Icons.access_time, color: Color(0xFF166088)),
                    title: Text(llegadaProgramada),
                    subtitle: const Text("Hora estimada de llegada"),
                    onTap: () => _seleccionarHoraLlegada(context, setDialogState),
                  ),
                  const Divider(),
                  const Text("Horas de estancia:"),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(icon: const Icon(Icons.remove_circle), onPressed: () => setDialogState(() => horas > 1 ? horas-- : null)),
                      Text("$horas hr(s)", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.add_circle), onPressed: () => setDialogState(() => horas++)),
                    ],
                  ),
                  const Divider(),
                  RadioListTile(
                    title: const Text("Saldo NexPark"),
                    subtitle: Text("Disponible: \$${homeState.saldo}",
                      style: TextStyle(
                          color: double.parse(homeState.saldo) >= total ? Colors.grey : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold
                      ),
                    ),
                    value: "Saldo",
                    groupValue: metodo,
                    onChanged: (v) => setDialogState(() => metodo = v!),
                  ),
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
                  _procesarPago(index, est, horas, total, metodo);
                },
                child: const Text("Confirmar Pago"),
              )
            ],
          );
        },
      ),
    );
  }

  void _procesarPago(int index, Estacionamiento est, int horas, double monto, String metodo) async {
    final homeState = context.findAncestorStateOfType<_HomePageState>();
    try {
      // Separación de lógica según el método (del código 2)
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
        },
      );

      final res = json.decode(response.body);
      if (res['status'] == 'success') {
        if (metodo == "Saldo") {
          setState(() => ParkingState.ocupados[index] = true);
          homeState._cargarDatosUsuarioServidor();
          homeState._obtenerTokenQR();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("¡Reserva confirmada con saldo!")));
        } else {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => PagoWebView(url: res['url_pago'])));
          if (result == "success") {
            homeState._cargarDatosUsuarioServidor();
            homeState._obtenerTokenQR();
          }
        }
      }
    } catch (e) { debugPrint("Error de Pago: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    bool ocupado = ParkingState.ocupados[widget.index];
    bool esDis = ParkingState.esDiscapacitado[widget.index];
    int tiempoRestante = ParkingState.tiempos[widget.index];

    // LÓGICA DE COLOR DINÁMICO
    Color colorCajon;
    if (ocupado) { // ocupado es true si el estado en la DB es 'ocupado'
      if (tiempoRestante > 0) {
        colorCajon = Colors.red.shade400; // DEBERÍA SER ROJO
      } else {
        colorCajon = Colors.orange.shade400; // AMARILLO
      }
    } else {
      // Si no está ocupado -> VERDE o AZUL
      colorCajon = esDis ? Colors.blue.shade600 : Colors.green.shade400;
    }

    return GestureDetector(
      onTap: () => ocupado ? null : _confirmarReserva(widget.index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: colorCajon,
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                ocupado && tiempoRestante == 0 ? Icons.event_available : (esDis ? Icons.accessible : Icons.local_parking),
                color: Colors.white,
                size: 35
            ),
            Text("C${widget.index + 1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),

            // LÓGICA DE TEXTO DEBAJO DEL ICONO
            if (ocupado)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  tiempoRestante > 0
                      ? ParkingState.formatearTiempo(tiempoRestante)
                      : "RESERVADO", // Cambiamos el 00:00:00 por un texto claro
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}