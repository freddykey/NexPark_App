import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'home_page.dart';

class TicketPage extends StatefulWidget {
  const TicketPage({super.key});

  @override
  State<TicketPage> createState() => _TicketPageState();
}


class _TicketPageState extends State<TicketPage> {
  final FlutterBluetoothClassic _bluetooth = FlutterBluetoothClassic();

  String esp32BaseUrl = 'http://192.168.4.1';
  bool isPrinterConnected = false;
  bool isConnectingPrinter = false;
  bool isFetchingTicket = false;
  String status = '';
  TicketData? currentTicket;
  BluetoothDevice? selectedPrinter;

  String _horaActual() {
    return DateFormat('HH:mm').format(DateTime.now());
  }

  String _horaMasUnaHora() {
    return DateFormat('HH:mm').format(
      DateTime.now().add(const Duration(hours: 1)),
    );
  }

  Future<void> configureEsp32Url() async {
    final controller = TextEditingController(text: esp32BaseUrl);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurar ESP32'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'URL base',
            hintText: 'http://192.168.4.1',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        esp32BaseUrl = result;
      });
    }
  }

  Future<void> connectPrinter() async {
    try {
      setState(() {
        isConnectingPrinter = true;
        status = 'Buscando impresora...';
      });

      final enabled = await _bluetooth.isBluetoothEnabled();
      if (!enabled) {
        final ok = await _bluetooth.enableBluetooth();
        if (!ok) {
          setState(() {
            isConnectingPrinter = false;
            status = 'Bluetooth no fue habilitado.';
          });
          return;
        }
      }

      final List<BluetoothDevice> devices = await _bluetooth.getPairedDevices();

      if (!mounted) return;

      if (devices.isEmpty) {
        setState(() {
          isConnectingPrinter = false;
          status = 'No hay impresoras emparejadas.';
        });
        return;
      }

      final BluetoothDevice? picked = await showModalBottomSheet<BluetoothDevice>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final d = devices[index];
                return ListTile(
                  leading: const Icon(Icons.print),
                  title: Text(d.name.isNotEmpty ? d.name : 'Sin nombre'),
                  subtitle: Text(d.address),
                  onTap: () => Navigator.pop(context, d),
                );
              },
            ),
          );
        },
      );

      if (picked == null) {
        setState(() {
          isConnectingPrinter = false;
          status = 'Conexión cancelada.';
        });
        return;
      }

      final ok = await _bluetooth.connect(picked.address);

      setState(() {
        selectedPrinter = picked;
        isPrinterConnected = ok;
        isConnectingPrinter = false;
        status = ok ? 'Impresora conectada.' : 'No se pudo conectar a la impresora.';
      });
    } catch (e) {
      setState(() {
        isConnectingPrinter = false;
        isPrinterConnected = false;
        status = 'Error al conectar impresora: $e';
      });
    }
  }

  Future<void> fetchTicket(String tipo) async {
    try {
      setState(() {
        isFetchingTicket = true;
        status = 'Solicitando ticket...';
      });

      final endpoint = tipo == 'entrada'
          ? '$esp32BaseUrl/ticket/entrada'
          : '$esp32BaseUrl/ticket/salida';

      final response =
      await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 7));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> json =
      jsonDecode(response.body) as Map<String, dynamic>;

      if (json['disponible'] == false) {
        setState(() {
          currentTicket = null;
          status = (json['mensaje'] ?? 'No hay ticket disponible').toString();
        });
        return;
      }

      final ticket = TicketData.fromJson(json);

      final ticketConHoraReal = ticket.copyWith(
        hora: _horaActual(),
        validoHasta: ticket.tipo.toLowerCase() == 'entrada' ? _horaMasUnaHora() : '',
      );

      setState(() {
        currentTicket = ticketConHoraReal;
        status = '';
      });
    } catch (e) {
      setState(() {
        status = 'Error al obtener ticket: $e';
      });
    } finally {
      if (mounted) {
        setState(() => isFetchingTicket = false);
      }
    }
  }

  Future<void> printCurrentTicket() async {
    if (currentTicket == null) {
      setState(() => status = 'Primero obtén un ticket.');
      return;
    }

    if (!isPrinterConnected) {
      await connectPrinter();
      if (!isPrinterConnected) return;
    }

    try {
      final bytes = _buildEscPosTicket(currentTicket!);
      final ok = await _bluetooth.sendData(bytes);

      setState(() {
        status = ok ? 'Ticket enviado a impresión.' : 'La impresora no aceptó los datos.';
      });
    } catch (e) {
      setState(() => status = 'Error al imprimir: $e');
    }
  }

  List<int> _buildEscPosTicket(TicketData t) {
    final bytes = <int>[];

    void text(String value) {
      bytes.addAll(latin1.encode(value));
    }

    void center() {
      bytes.addAll([0x1B, 0x61, 0x01]);
    }

    void left() {
      bytes.addAll([0x1B, 0x61, 0x00]);
    }

    void boldOn() {
      bytes.addAll([0x1B, 0x45, 0x01]);
    }

    void boldOff() {
      bytes.addAll([0x1B, 0x45, 0x00]);
    }

    void feed([int n = 1]) {
      bytes.addAll(List.filled(n, 0x0A));
    }

    void cut() {
      bytes.addAll([0x1D, 0x56, 0x41, 0x10]);
    }

    void addQrCode(String data) {
      final qrData = latin1.encode(data);

      bytes.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);
      bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x06]);
      bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]);

      final storeLen = qrData.length + 3;
      final pL = storeLen % 256;
      final pH = storeLen ~/ 256;

      bytes.addAll([0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30]);
      bytes.addAll(qrData);
      bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    }

    bytes.addAll([0x1B, 0x40]);

    center();
    boldOn();
    text('NEXPARK\n');
    boldOff();
    text('------------------------------\n');
    feed();

    left();
    text('Tipo: ${t.tipo}\n');
    text('Cajon: ${t.cajon}\n');
    text('Hora: ${t.hora}\n');

    if ((t.validoHasta ?? '').isNotEmpty) {
      text('Valido hasta: ${t.validoHasta}\n');
    }

    if ((t.tiempoIncluido ?? '').isNotEmpty) {
      text('Tiempo incluido: ${t.tiempoIncluido}\n');
    }

    if ((t.mensaje ?? '').isNotEmpty) {
      text('${t.mensaje}\n');
    }

    text('------------------------------\n');
    feed();

    center();
    text('CODIGO QR\n');
    feed();

    addQrCode(t.qr);
    feed(2);

    text('${t.qr}\n');
    feed();

    text('Presenta este ticket\n');
    text('al ingresar o salir\n');
    feed(3);

    cut();
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NexPark'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'esp32':
                  configureEsp32Url();
                  break;
                case 'printer':
                  connectPrinter();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'esp32', child: Text('Configurar ESP32')),
              PopupMenuItem(value: 'printer', child: Text('Conectar impresora')),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: isFetchingTicket ? null : () => fetchTicket('entrada'),
              icon: const Icon(Icons.login),
              label: Text(
                isFetchingTicket ? 'Solicitando...' : 'Obtener ticket de entrada',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isFetchingTicket ? null : () => fetchTicket('salida'),
              icon: const Icon(Icons.logout),
              label: const Text('Obtener ticket de salida'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: printCurrentTicket,
              icon: const Icon(Icons.print),
              label: const Text('Imprimir ticket'),
            ),
            const SizedBox(height: 12),
            if (status.isNotEmpty)
              Text(
                status,
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 16),
            Expanded(
              child: currentTicket == null
                  ? const Center(child: Text('Aún no hay ticket recibido.'))
                  : Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const Text(
                          'Vista previa del ticket',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('Tipo: ${currentTicket!.tipo}'),
                        Text('Cajón: ${currentTicket!.cajon}'),
                        Text('Hora: ${currentTicket!.hora}'),
                        if ((currentTicket!.validoHasta ?? '').isNotEmpty)
                          Text('Válido hasta: ${currentTicket!.validoHasta}'),
                        if ((currentTicket!.tiempoIncluido ?? '').isNotEmpty)
                          Text('Tiempo incluido: ${currentTicket!.tiempoIncluido}'),
                        const SizedBox(height: 16),
                        QrImageView(
                          data: currentTicket!.qr,
                          version: QrVersions.auto,
                          size: 220,
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          currentTicket!.qr,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
  final String? tiempoIncluido;
  final String? mensaje;

  TicketData({
    required this.tipo,
    required this.cajon,
    required this.qr,
    required this.hora,
    this.validoHasta,
    this.tiempoIncluido,
    this.mensaje,
  });

  TicketData copyWith({
    String? tipo,
    String? cajon,
    String? qr,
    String? hora,
    String? validoHasta,
    String? tiempoIncluido,
    String? mensaje,
  }) {
    return TicketData(
      tipo: tipo ?? this.tipo,
      cajon: cajon ?? this.cajon,
      qr: qr ?? this.qr,
      hora: hora ?? this.hora,
      validoHasta: validoHasta ?? this.validoHasta,
      tiempoIncluido: tiempoIncluido ?? this.tiempoIncluido,
      mensaje: mensaje ?? this.mensaje,
    );
  }

  factory TicketData.fromJson(Map<String, dynamic> json) {
    return TicketData(
      tipo: (json['tipo'] ?? '').toString(),
      cajon: (json['cajon'] ?? '').toString(),
      qr: (json['qr'] ?? '').toString(),
      hora: (json['hora'] ?? '').toString(),
      validoHasta: json['valido_hasta']?.toString(),
      tiempoIncluido: json['tiempo_incluido']?.toString(),
      mensaje: json['mensaje']?.toString(),
    );
  }
}