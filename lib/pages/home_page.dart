import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'login_page.dart';
import 'user_account.dart';


class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Estacionamiento (Nombre/en base de datos)"),
          centerTitle: true,
          elevation: 2,

          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.local_parking), text: "Cajones"),
              Tab(icon: Icon(Icons.map), text: "Mapa"),
              Tab(icon: Icon(Icons.qr_code), text: "QR"),
            ],
          ),
        ),

        // EL DRAWER ES PARA EL MENU DESPLEGABLE DONDE SE MANEJA COMO UNA LISTA EN DONDE POR EL MOMENTO SE COLOCA LAS OPCIONES DEL MENU E INICIO (USANDO ICONOS PREDETERMINADOS DEL FLUTTER)
        drawer: Drawer(
          child: ListView(
            children: [

              //SE USA CONTAINER PARA UNA CABECERA DE COLOR AZUL EN DONDE TIENE EL MENU, SE ESTABA USANDO DRAWERHEADER PERO TENIA UN TAMAÑO PREDETERMINADO QUE HACIA QUE LUCIERA MAL.
              Container(
                height: 120,
                color: Colors.black26,
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [

                    Image.asset(
                      'assets/logo.png',
                      height: 80,
                    ),


                  ],
                ),
              ),

              //SE COLOCA EL TITULO DE INICIO
              ListTile(
                leading: const Icon(Icons.home),

                title: const Text("Inicio"),
                onTap: () {
                  Navigator.pop(context);
                },
              ),

              //TITULO CUENTAAAA
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text("Cuenta"),
                onTap: () {
                  // 1. Cerramos el Drawer antes de navegar
                  Navigator.pop(context);

                  // 2. Navegamos a la página de cuenta de usuario
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UserAccount()),
                  );
                },
              ),

              //SE COLOCA EL TITULO CERRAR SESION
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


        body: const TabBarView(
          children: [
            ParkingGrid(index: 0),
            MapPage(),
            QRPage(),
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
  Widget build(BuildContext context) {

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(blurRadius: 10, color: Colors.black12)
              ],
            ),
            child: const Icon(Icons.qr_code, size: 200),
          ),
        ),
        const SizedBox(height: 20),
        const Text("Escanea para entrar/salir"),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.camera_alt),
          label: const Text("Escanear QR"),
        )
      ],
    );
  }
}


// ESTADO GLOBAL DEL BOTON (TENIENDO COMO VARIABLES SI ESTA OCUPADO (ESTANDO COMO INICIAL EN FALSO), EL TIEMPO Y COMO TAL LOS TIMERS
class ParkingState {
  static List<bool> ocupados = [false, false];
  static List<int> tiempos = [0, 0];
  static List<Timer?> timers = [null, null];
//SE AGREGO UN GLOBAL TIMER PARA QUE NO SE ROMPA AL MOMENTO DE CAMBIAR DE PESTAÑA
  static Timer? globalTimer;

  static void iniciarGlobal(VoidCallback updateUI) {
    globalTimer?.cancel();

    globalTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      updateUI();
    });
  }
}

// ------------------------------

class ParkingGrid extends StatefulWidget {
  final int index;

  const ParkingGrid({super.key, required this.index});

  @override
  State<ParkingGrid> createState() => _ParkingGridState();
}

class _ParkingGridState extends State<ParkingGrid> {

  final FlutterLocalNotificationsPlugin notifications =
  FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    initNotificaciones();


    ParkingState.iniciarGlobal(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> initNotificaciones() async {
    await Permission.notification.request();

    const androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const settings = InitializationSettings(android: androidSettings);

    await notifications.initialize(settings);
  }


  Future<void> notificar(String mensaje) async {
    const androidDetails = AndroidNotificationDetails(
      'canal',
      'notificaciones',
      importance: Importance.max,
      priority: Priority.high,
    );

    await notifications.show(
      0,
      'Estacionamiento',
      mensaje,
      const NotificationDetails(android: androidDetails),
    );
  }
//EN ESTA PARTE ES DEL INICIO DEL CONTEO DEL TIMER, INICIANDO DE 20 SEGUNDOS, DONDE SE HACE EL LLAMADO DE LA NOTIFICACION AL FALTAR SOLO 10s DE CAJON n.
  void iniciarTimer(int index) {
    ParkingState.tiempos[index] = 20;

    ParkingState.timers[index]?.cancel();

    ParkingState.timers[index] =
        Timer.periodic(const Duration(seconds: 1), (t) {

          ParkingState.tiempos[index]--;

          if (ParkingState.tiempos[index] == 10) {
            notificar("Cajón ${index + 1}: quedan 10s");
          }

          if (ParkingState.tiempos[index] == 0) {
            t.cancel();
            ParkingState.ocupados[index] = false;
            notificar("Cajón ${index + 1} disponible");
          }
        });
  }
//ESTA PARTE ES AL MOMENTO DE PRESIONAR EL CUADRADO, DEPENDIENDO SI ES ROJO MANDARA EL MENSAJE DE OCUPADO, SI NO TE DARA LA OPCION DE NADA MAS CONFIRMAR O CANCELAR.
  void seleccionar(int index) {
    if (ParkingState.ocupados[index]) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Ocupado"),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text("Reservar C${index + 1}"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancelar"),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    ParkingState.ocupados[index] = true;
                  });
                  iniciarTimer(index);
                  Navigator.pop(context);
                },
                child: const Text("Confirmar"),
              )
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    int i = widget.index;
    bool ocupado = ParkingState.ocupados[i];

    return Center(
      child: GestureDetector(
        onTap: () => seleccionar(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: ocupado ? Colors.red : Colors.green,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 4),
              )
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.local_parking,
                color: Colors.white,
                size: 40,
              ),
              const SizedBox(height: 10),
              Text(
                "C${i + 1}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (ocupado)
                Text(
                  "${ParkingState.tiempos[i]}s",
                  style: const TextStyle(color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }
}