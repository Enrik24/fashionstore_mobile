import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/providers/pos_provider.dart';
import '../../core/services/offline_document_service.dart';

/// [EXAMEN-2] Venta de contado sin conexión (CU07).
class PosSalePage extends StatefulWidget {
  const PosSalePage({super.key});

  @override
  State<PosSalePage> createState() => _PosSalePageState();
}

class _PosSalePageState extends State<PosSalePage> {
  final _busqueda = TextEditingController();
  final _recibido = TextEditingController();

  @override
  void dispose() {
    _busqueda.dispose();
    _recibido.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Venta offline')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _busqueda,
              decoration: InputDecoration(
                labelText: 'Buscar producto o SKU',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => pos.search(_busqueda.text),
                ),
              ),
              onSubmitted: pos.search,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OutlinedButton.icon(
              onPressed: () async {
                final sku = await context.push<String>('/pos/barcode');
                if (sku != null && sku.isNotEmpty) {
                  _busqueda.text = sku;
                  await pos.search(sku);
                }
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear c?digo'),
            ),
          ),
          Expanded(
            child: ListView(
              children: pos.searchResults.map((producto) {
                return ListTile(
                  title: Text(producto.nombre),
                  subtitle: Text(producto.sku),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_shopping_cart),
                    onPressed: producto.variantes.isEmpty
                        ? null
                        : () => pos.addProduct(
                            varianteProductoId: producto.variantes.first.id,
                            cantidad: 1,
                            precioUnitario:
                                producto.variantes.first.precioVariante ??
                                producto.precio,
                            nombre: producto.nombre,
                            stockConocido: producto.variantes.first.stockTotal,
                          ),
                  ),
                );
              }).toList(),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Total: ${pos.total.toStringAsFixed(2)}'),
                  TextField(
                    controller: _recibido,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Monto recibido',
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: pos.isLoading
                        ? null
                        : () async {
                            final venta = await pos.confirm(
                              sucursalId: 1,
                              cajeroId: 0,
                              montoRecibido:
                                  double.tryParse(_recibido.text) ?? 0,
                            );
                            if (venta != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Venta ${venta.uuidOffline.substring(0, 8)} pendiente de sincronización',
                                  ),
                                ),
                              );
                              await showDialog<void>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Comprobante temporal'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      QrImageView(
                                        data: venta.uuidOffline,
                                        size: 180,
                                        semanticsLabel: 'C?digo QR de la venta',
                                      ),
                                      const SizedBox(height: 12),
                                      if (pos.receiptPath != null)
                                        TextButton.icon(
                                          onPressed: () => context
                                              .read<OfflineDocumentService>()
                                              .abrirArchivo(pos.receiptPath!),
                                          icon: const Icon(
                                            Icons.picture_as_pdf,
                                          ),
                                          label: const Text('Abrir PDF'),
                                        ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: const Text('Cerrar'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                    child: const Text('Confirmar venta'),
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
