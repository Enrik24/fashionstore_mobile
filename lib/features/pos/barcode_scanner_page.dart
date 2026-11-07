import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final _manual = TextEditingController();
  bool _procesado = false;

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  void _devolver(String valor) {
    final texto = valor.trim();
    if (texto.isEmpty || _procesado) return;
    _procesado = true;
    Navigator.of(context).pop(texto);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear c?digo de barras')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (captures) {
                final valor = captures.barcodes.isEmpty
                    ? ''
                    : captures.barcodes.first.rawValue ?? '';
                _devolver(valor);
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manual,
                      decoration: const InputDecoration(
                        labelText: 'Introducir SKU manualmente',
                      ),
                      onSubmitted: _devolver,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _devolver(_manual.text),
                    child: const Text('Buscar'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
