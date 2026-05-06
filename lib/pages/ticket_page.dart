import 'dart:convert';
import 'dart:convert' show latin1;
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

class TicketPage extends StatefulWidget {
  const TicketPage({super.key});

  @override
  State<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<TicketPage> {
  final FlutterBluetoothClassic _bluetooth = FlutterBluetoothClassic();

  bool isPrinterConnected = false;
  bool isConnectingPrinter = false;
  bool isFetchingTicket = false;

  String status = '';

  TicketData? currentTicket;
  BluetoothDevice? selectedPrinter;

  final TextEditingController qrController = TextEditingController();
  final FocusNode qrFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    // 🔥 Mantener foco SIEMPRE para el escáner
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(qrFocus);
    });
  }

  // ================= VALIDAR QR =================
  Future<void> validarQR(String qr) async {
    setState(() => status = "Validando...");

    try {
      final url = Uri.parse(
          "https://carlossalinas.webpro1213.com/api/validar_qr.php?qr=$qr");

      final response = await http.get(url);

      setState(() {
        status = response.body;
      });
    } catch (e) {
      setState(() {
        status = "Error conexión";
      });
    }
  }

  // ================= GENERAR TICKET =================
  Future<void> fetchTicket() async {
    try {
      setState(() {
        isFetchingTicket = true;
        status = 'Generando ticket...';
      });

      final response = await http.get(Uri.parse(
          'https://carlossalinas.webpro1213.com/api/generar_ticket.php?tipo=entrada'));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final json = jsonDecode(response.body);

      if (json['disponible'] == false) {
        setState(() {
          currentTicket = null;
          status = json['mensaje'];
        });
        return;
      }

      final ticket = TicketData.fromJson(json);

      setState(() {
        currentTicket = ticket;
        status = 'Ticket generado';
      });
    } catch (e) {
      setState(() {
        status = 'Error: $e';
      });
    } finally {
      setState(() => isFetchingTicket = false);
    }
  }

  // ================= IMPRIMIR =================
  Future<void> printCurrentTicket() async {
    if (currentTicket == null) {
      setState(() => status = 'Primero genera un ticket');
      return;
    }

    if (!isPrinterConnected) {
      await connectPrinter();
      if (!isPrinterConnected) return;
    }

    final bytes = _buildTicket(currentTicket!);
    final ok = await _bluetooth.sendData(bytes);

    setState(() {
      status = ok ? 'Impreso correctamente' : 'Error al imprimir';
    });
  }

  // ================= CONECTAR IMPRESORA =================
  Future<void> connectPrinter() async {
    try {
      setState(() {
        isConnectingPrinter = true;
        status = 'Buscando impresora...';
      });

      final enabled = await _bluetooth.isBluetoothEnabled();
      if (!enabled) {
        final ok = await _bluetooth.enableBluetooth();
        if (!ok) return;
      }

      final devices = await _bluetooth.getPairedDevices();

      final picked = await showModalBottomSheet<BluetoothDevice>(
        context: context,
        builder: (context) => ListView(
          children: devices
              .map((d) => ListTile(
            title: Text(d.name),
            subtitle: Text(d.address),
            onTap: () => Navigator.pop(context, d),
          ))
              .toList(),
        ),
      );

      if (picked == null) return;

      final ok = await _bluetooth.connect(picked.address);

      setState(() {
        isPrinterConnected = ok;
        status = ok ? 'Impresora conectada' : 'Error al conectar';
      });
    } catch (e) {
      setState(() => status = 'Error: $e');
    }
  }

  // ================= TICKET =================
  List<int> _buildTicket(TicketData t) {
    final bytes = <int>[];

    void text(String s) => bytes.addAll(latin1.encode(s));
    void center() => bytes.addAll([0x1B, 0x61, 0x01]);
    void left() => bytes.addAll([0x1B, 0x61, 0x00]);
    void feed([int n = 1]) => bytes.addAll(List.filled(n, 0x0A));

    void qr(String data) {
      final d = latin1.encode(data);
      bytes.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);
      bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x06]);
      bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]);

      int len = d.length + 3;
      bytes.addAll([0x1D, 0x28, 0x6B, len % 256, len ~/ 256, 0x31, 0x50, 0x30]);
      bytes.addAll(d);
      bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    }

    bytes.addAll([0x1B, 0x40]);

    center();
    text("NEXPARK\n");
    feed();

    left();
    text("Tipo: ${t.tipo}\n");
    text("Cajon: ${t.cajon}\n");
    text("Hora: ${t.hora}\n");

    feed();
    center();
    qr(t.qr);

    feed(3);
    return bytes;
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NexPark')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 🔥 INPUT INVISIBLE PARA GM65
            SizedBox(
              height: 0,
              child: TextField(
                controller: qrController,
                focusNode: qrFocus,
                autofocus: true,
                onSubmitted: (value) {
                  final qr = value.trim();
                  validarQR(qr);

                  qrController.clear();
                  FocusScope.of(context).requestFocus(qrFocus);
                },
              ),
            ),

            const SizedBox(height: 20),

            FilledButton(
              onPressed: isFetchingTicket ? null : fetchTicket,
              child: const Text("Generar ticket"),
            ),

            const SizedBox(height: 10),

            FilledButton(
              onPressed: printCurrentTicket,
              child: const Text("Imprimir ticket"),
            ),

            const SizedBox(height: 20),

            Text(
              status,
              style: const TextStyle(fontSize: 22),
            ),

            const SizedBox(height: 20),

            if (currentTicket != null) ...[
              Text("Tipo: ${currentTicket!.tipo}"),
              Text("Cajón: ${currentTicket!.cajon}"),
              Text("Hora: ${currentTicket!.hora}"),
              const SizedBox(height: 10),
              QrImageView(
                data: currentTicket!.qr,
                size: 200,
              ),
            ]
          ],
        ),
      ),
    );
  }
}

class TicketData {
  final String tipo;
  final String cajon;
  final String qr;
  final String hora;
  final String? validoHasta;

  TicketData({
    required this.tipo,
    required this.cajon,
    required this.qr,
    required this.hora,
    this.validoHasta,
  });

  factory TicketData.fromJson(Map<String, dynamic> json) {
    return TicketData(
      tipo: json['tipo'],
      cajon: json['cajon'],
      qr: json['qr'],
      hora: json['hora'] ?? '',
      validoHasta: json['valido_hasta'],
    );
  }
}