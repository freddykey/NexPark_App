import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PagoWebView extends StatefulWidget {
  final String url;
  const PagoWebView({super.key, required this.url});

  @override
  State<PagoWebView> createState() => _PagoWebViewState();
}

class _PagoWebViewState extends State<PagoWebView> {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            // Si el usuario le dio a "Volver" tras un pago exitoso
            if (url.contains("pago_exitoso.php")) {
              Navigator.pop(context, "success");
            }
            // Si el usuario canceló o falló el pago y quiere volver
            if (url.contains("pago_fallido.php") || url.contains("pago_pendiente.php")) {
              Navigator.pop(context, "cancel");
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pago Seguro"),
        backgroundColor: const Color(0xFF166088),
        foregroundColor: Colors.white,
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}