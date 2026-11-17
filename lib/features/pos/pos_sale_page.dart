import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/providers/pos_provider.dart';
import '../../core/services/cart_service.dart';

/// [EXAMEN-2] Venta de contado sin conexión (CU07).
class PosSalePage extends StatefulWidget {
  const PosSalePage({super.key});

  @override
  State<PosSalePage> createState() => _PosSalePageState();
}

class _PosSalePageState extends State<PosSalePage> {
  final _busqueda = TextEditingController();
  final _recibido = TextEditingController();
  // [EXAMEN-2] B1.3.f: forzar la venta cuando el stock local es crítico.
  // La operación queda marcada para revisión del servidor (RN-006).
  bool _forzar = false;
  // [EXAMEN-2] B1.3.a: cantidad por variante agregada.
  final Map<int, int> _cantidades = <int, int>{};

  @override
  void initState() {
    super.initState();
    // [EXAMEN-2] CU07: sucursal y cajero de la sesión (sin IDs fijos).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PosProvider>().resolverSucursalActual();
    });
  }

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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // [EXAMEN-2] B1.3.a: cantidad editable por línea.
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: producto.variantes.isEmpty
                            ? null
                            : () => setState(() {
                                final id = producto.variantes.first.id;
                                final actual = _cantidades[id] ?? 1;
                                if (actual <= 1) {
                                  _cantidades.remove(id);
                                } else {
                                  _cantidades[id] = actual - 1;
                                }
                              }),
                      ),
                      Text(
                        '${_cantidades[producto.variantes.isEmpty ? 0 : producto.variantes.first.id] ?? 1}',
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: producto.variantes.isEmpty
                            ? null
                            : () => setState(() {
                                final id = producto.variantes.first.id;
                                _cantidades[id] = (_cantidades[id] ?? 1) + 1;
                              }),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_shopping_cart),
                        onPressed: producto.variantes.isEmpty
                            ? null
                            : () async {
                                final variante = producto.variantes.first;
                                // [EXAMEN-2] B0.2.d: el aviso de stock
                                // referencial aparece sólo cuando el stock
                                // **conocido** es 0. Con `stockPorSucursal`
                                // vacío no hay dato local (se distingue "sin
                                // stock" de "sin dato").
                                final sinDato =
                                    variante.stockPorSucursal.isEmpty;
                                if (!sinDato && variante.stockTotal <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        CartService.mensajeStockReferencial(
                                          variante.stockTotal,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final cantidad = _cantidades[variante.id] ?? 1;
                                final ok = await pos.addProduct(
                                  varianteProductoId: variante.id,
                                  cantidad: cantidad,
                                  precioUnitario:
                                      variante.precioVariante ??
                                      producto.precio,
                                  nombre: producto.nombre,
                                  stockConocido: variante.stockTotal,
                                  forzar: _forzar,
                                );
                                if (!ok &&
                                    context.mounted &&
                                    pos.errorMessage != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(pos.errorMessage!),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              },
                      ),
                    ],
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
                  // [EXAMEN-2] B1.3.a: líneas agregadas a la venta.
                  if (pos.lineas.isNotEmpty) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Prendas en la venta',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final linea in pos.lineas)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${linea['producto_nombre'] ?? 'Prenda'} x${linea['cantidad']}',
                        ),
                        subtitle: Text(
                          'Precio ${((linea['precio_unitario'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                        ),
                        trailing: Text(
                          ((linea['subtotal'] as num?)?.toDouble() ?? 0)
                              .toStringAsFixed(2),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    const Divider(),
                  ],
                  Text('Total: ${pos.total.toStringAsFixed(2)}'),
                  // [EXAMEN-2] B1.3.b: el cambio se muestra al cajero.
                  if (_recibido.text.isNotEmpty)
                    Builder(
                      builder: (context) {
                        final recibido =
                            double.tryParse(_recibido.text) ?? 0;
                        final cambio = pos.changeFor(recibido);
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Cambio: ${cambio.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        );
                      },
                    ),
                  // [EXAMEN-2] B1.3.f: forzar la venta con stock crítico.
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Forzar venta (quedará para revisión al sincronizar)',
                    ),
                    value: _forzar,
                    onChanged: (v) => setState(() => _forzar = v),
                  ),
                  TextField(
                    controller: _recibido,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Monto recibido',
                    ),
                    // [EXAMEN-2] B1.3.b: recalcula el cambio al escribir.
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: pos.isLoading
                        ? null
                        : () async {
                            final venta = await pos.confirm(
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
                              // [EXAMEN-2] B1.3.h: la ruta `/pos/sale/receipt`
                              // existía pero **nadie navegaba** a ella; el POS
                              // usaba un diálogo inline. Ahora se muestra la
                              // pantalla completa con QR, PDF e impresión.
                              context.push('/pos/sale/receipt', extra: {
                                'uuidOffline': venta.uuidOffline,
                                'titulo': 'Comprobante temporal',
                                'rutaPdf': pos.receiptPath,
                              });
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
