// [EXAMEN-2] CU18: reposición offline (POS → Reposiciones).
//
// Venta original, prenda devuelta, prenda nueva del mismo producto, stock,
// diferencia clasificada y confirmación con nota de reposición local.
//
// [EXAMEN-2] B1.10: la pantalla ya no pide **IDs a mano**: las prendas se
// eligen del catálogo local (con talla, color y stock), lo que además
// permite validar que la prenda nueva sea del mismo producto.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/product_model.dart';
import '../../../core/providers/catalog_provider.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/offline_return_provider.dart';
import '../../../core/services/offline_document_service.dart';
import '../return/widgets/return_price_difference_card.dart';
import 'widgets/alternative_size_sheet.dart';

class PosExchangePage extends StatefulWidget {
  const PosExchangePage({super.key});

  @override
  State<PosExchangePage> createState() => _PosExchangePageState();
}

class _PosExchangePageState extends State<PosExchangePage> {
  final _comprobante = TextEditingController();
  String? _notaRuta;

  /// [EXAMEN-2] B1.10.a: prendas elegidas (devuelta → nueva) con cantidad.
  int? _varianteDevueltaId;
  int? _varianteNuevaId;
  String _nombreDevuelta = '';
  String _nombreNueva = '';
  double _precioDevuelto = 0;
  double _precioNuevo = 0;
  int _cantidad = 1;
  // [EXAMEN-2] B1.10.h: medio de pago de la diferencia de precio.
  String _medioPagoDiferencia = 'EFECTIVO';

  @override
  void initState() {
    super.initState();
    // [EXAMEN-2] B0.1.h: el provider es compartido con la pantalla de
    // devolución; se reinicia para no arrastrar líneas de otra operación.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OfflineReturnProvider>().reiniciarOperacion();
    });
  }

  @override
  void dispose() {
    _comprobante.dispose();
    super.dispose();
  }

  /// [EXAMEN-2] B1.10.a: elegidor de prenda del catálogo local.
  Future<void> _elegirPrenda({
    required bool esDevuelta,
  }) async {
    final catalog = context.read<CatalogProvider>();
    if (catalog.products.isEmpty) {
      catalog.loadCatalog();
    }
    if (!mounted) return;
    final eleccion = await showModalBottomSheet<_PrendaElegida>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _SelectorPrendas(
        productos: catalog.products,
        esDevuelta: esDevuelta,
      ),
    );
    if (eleccion == null || !mounted) return;
    setState(() {
      if (esDevuelta) {
        _varianteDevueltaId = eleccion.variante.id;
        _nombreDevuelta = eleccion.nombre;
        _precioDevuelto = eleccion.precio;
      } else {
        _varianteNuevaId = eleccion.variante.id;
        _nombreNueva = eleccion.nombre;
        _precioNuevo = eleccion.precio;
      }
    });
  }

  /// [EXAMEN-2] B1.10.e: deriva a devolución con reembolso o saldo a favor.
  Future<void> _derivarADevolucion() async {
    final provider = context.read<OfflineReturnProvider>();
    final items = provider.itemsReposicion;
    if (items.isEmpty) {
      _mostrarAviso('Selecciona primero la prenda devuelta.');
      return;
    }
    final opcion = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sin alternativa de talla'),
        content: const Text(
          'No hay una talla mayor ni menor disponible.\n\n'
          '¿Cómo se resuelve la devolución de la prenda?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'REEMBOLSO'),
            child: const Text('Reembolso'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'SALDO_FAVOR'),
            child: const Text('Saldo a favor'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (opcion == null || !mounted) return;
    final solicitud = await provider.confirmarDevolucionOffline(
      numeroComprobanteOrigen: _comprobante.text,
      sucursalId: await provider.resolverSucursalId(),
      saldoFavor: opcion == 'SALDO_FAVOR',
      // [EXAMEN-2] B2.4: el backend notificará al cliente la falta de
      // talla alternativa (RN-022/RN-024).
      notificarAlternativa: true,
    );
    if (!mounted) return;
    _mostrarAviso(
      solicitud == null
          ? provider.errorMessage ?? 'No se pudo registrar la devolución'
          : 'Derivada a devolución ${solicitud.numeroSolicitud}',
    );
  }

  void _mostrarAviso(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OfflineReturnProvider>();
    final catalog = context.watch<CatalogProvider>();
    final conectividad = context.watch<ConnectivityProvider>();
    final offline = !conectividad.estaEnLinea;

    return Scaffold(
      appBar: AppBar(title: const Text('Reposición offline')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _comprobante,
            decoration: InputDecoration(
              labelText: 'Número de comprobante o UUID de venta',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () async {
                  final venta = await provider.buscarVentaOriginal(
                    _comprobante.text,
                  );
                  if (!mounted) return;
                  final limite = venta?['fecha_limite_cambio']?.toString();
                  provider.setVentaOriginal(
                    venta,
                    fechaLimite: limite == null
                        ? null
                        : DateTime.tryParse(limite),
                  );
                },
              ),
            ),
          ),
          if (provider.ventaOriginal != null)
            Text(
              provider.plazoValido
                  ? 'Plazo válido (RN-012)'
                  : 'Fuera de período permitido',
              style: TextStyle(
                color: provider.plazoValido ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(height: 12),

          // [EXAMEN-2] B1.10.a: prenda devuelta (del catálogo local).
          _TarjetaPrenda(
            titulo: 'Prenda devuelta',
            nombre: _nombreDevuelta.isEmpty ? null : _nombreDevuelta,
            onElegir: () => _elegirPrenda(esDevuelta: true),
          ),
          const SizedBox(height: 8),
          // [EXAMEN-2] B1.10.a: prenda nueva (mismo producto).
          _TarjetaPrenda(
            titulo: 'Prenda nueva (mismo producto)',
            nombre: _nombreNueva.isEmpty ? null : _nombreNueva,
            onElegir: () => _elegirPrenda(esDevuelta: false),
          ),
          const SizedBox(height: 8),

          // [EXAMEN-2] B1.10.c: cantidad a reponer.
          Row(
            children: [
              const Text('Cantidad:'),
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: _cantidad <= 1
                    ? null
                    : () => setState(() => _cantidad--),
              ),
              Text('$_cantidad'),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => setState(() => _cantidad++),
              ),
            ],
          ),

          // [EXAMEN-2] B1.10.h: medio de pago de la diferencia.
          DropdownButtonFormField<String>(
            initialValue: _medioPagoDiferencia,
            decoration: const InputDecoration(
              labelText: 'Pago de la diferencia de precio',
            ),
            items: [
              const DropdownMenuItem<String>(
                value: 'EFECTIVO',
                child: Text('Efectivo'),
              ),
              if (!offline)
                const DropdownMenuItem<String>(
                  value: 'TARJETA',
                  child: Text('Tarjeta (pasarela)'),
                ),
            ],
            onChanged: (valor) {
              if (valor != null) setState(() => _medioPagoDiferencia = valor);
            },
          ),
          if (offline)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Sin conexión: la diferencia sólo puede cobrarse en efectivo '
                '(RN-008).',
                style: TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ),

          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _varianteDevueltaId == null
                ? null
                : () {
                    provider.agregarItem(
                      LineaSeleccion(
                        varianteProductoId: _varianteDevueltaId!,
                        precioUnitario: _precioDevuelto,
                        cantidad: _cantidad,
                        varianteCambioId: _varianteNuevaId,
                        precioVarianteNueva: _precioNuevo == 0
                            ? null
                            : _precioNuevo,
                      ),
                    );
                    _mostrarAviso('Línea agregada.');
                  },
            icon: const Icon(Icons.add),
            label: const Text('Agregar línea'),
          ),
          TextButton(
            onPressed: _varianteDevueltaId == null
                ? null
                : () => showAlternativeSizeSheet(
                    context,
                    varianteId: _varianteDevueltaId!,
                  ),
            child: const Text('Buscar alternativas de talla'),
          ),
          const SizedBox(height: 8),
          ReturnPriceDifferenceCard(
            diferenciaPrecio: provider.diferencia,
            tipoDiferencia: provider.diferencia < -0.005
                ? 'SALDO_FAVOR'
                : provider.diferencia > 0.005
                ? 'COBRO'
                : 'SIN_DIFERENCIA',
            saldoFavor: provider.saldoFavor,
          ),
          if (provider.sinAlternativa)
            Card(
              color: Colors.orange.withOpacity(0.12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SIN_ALTERNATIVA: sin talla mayor ni menor disponible.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    // [EXAMEN-2] B1.10.e: derivación real a devolución.
                    FilledButton.icon(
                      onPressed: _derivarADevolucion,
                      icon: const Icon(Icons.assignment_return_outlined),
                      label: const Text('Derivar a devolución'),
                    ),
                  ],
                ),
              ),
            ),
          if (provider.alternativas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Alternativas encontradas: ${provider.alternativas.length}. '
                'Si están en otra sucursal se puede solicitar el traspaso.',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          if (provider.errorMessage != null)
            Text(
              provider.errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                provider.isLoading || !provider.plazoValido
                ? null
                : () async {
                    final solicitud = await provider
                        .confirmarReposicionOffline(
                          numeroComprobanteOrigen: _comprobante.text,
                          sucursalId: await provider.resolverSucursalId(),
                          // [EXAMEN-2] B1.10.h: medio de pago y modo offline.
                          metodoPagoDiferencia: _medioPagoDiferencia,
                          offline: offline,
                        );
                    if (!context.mounted) return;
                    if (solicitud != null) {
                      final docs = context.read<OfflineDocumentService>();
                      _notaRuta = await docs.generarNotaReposicion(
                        uuidOffline: solicitud.uuidOffline!,
                        datos: OfflineDocumentService.datosNotaReposicion(
                          uuidOffline: solicitud.uuidOffline!,
                          numeroComprobanteOrigen: _comprobante.text,
                          numeroReposicion: solicitud.numeroReposicion,
                          // [EXAMEN-2] B1.10.k: la nota muestra las prendas
                          // reales (antes salía "—" en ambos campos).
                          prendaDevuelta: _nombreDevuelta,
                          prendaNueva: _nombreNueva,
                          motivo: solicitud.motivo,
                          diferenciaPrecio: solicitud.diferenciaPrecio,
                          tipoDiferencia: solicitud.tipoDiferencia,
                          montoPagadoDiferencia:
                              solicitud.montoPagadoDiferencia,
                          saldoFavor: solicitud.saldoFavor,
                        ),
                      );
                      if (!context.mounted) return;
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Reposición ${solicitud.numeroReposicion ?? solicitud.numeroSolicitud} registrada; nota generada',
                          ),
                        ),
                      );
                    } else if (provider.errorMessage != null) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(provider.errorMessage!)),
                      );
                    }
                  },
            icon: const Icon(Icons.swap_horiz_outlined),
            label: const Text('Confirmar reposición offline'),
          ),
          if (_notaRuta != null)
            TextButton.icon(
              onPressed: () => context
                  .read<OfflineDocumentService>()
                  .abrirArchivo(_notaRuta!),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Abrir nota de reposición'),
            ),
          const SizedBox(height: 8),
          const Text(
            'Entrada y salida de inventario en la misma transacción (RN-025).',
          ),
          if (catalog.isOfflineData)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Catálogo descargado: los precios y el stock son referenciales.',
                style: TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tarjeta de la prenda elegida (devuelta o nueva).
class _TarjetaPrenda extends StatelessWidget {
  const _TarjetaPrenda({
    required this.titulo,
    required this.nombre,
    required this.onElegir,
  });

  final String titulo;
  final String? nombre;
  final VoidCallback onElegir;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.checkroom_outlined),
        title: Text(titulo),
        subtitle: Text(
          nombre ?? 'Sin elegir — toca para buscar en el catálogo',
          style: TextStyle(
            color: nombre == null ? Colors.orange : null,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onElegir,
      ),
    );
  }
}

/// Prenda elegida en el selector del catálogo local.
class _PrendaElegida {
  const _PrendaElegida({
    required this.variante,
    required this.nombre,
    required this.precio,
  });

  final VarianteProducto variante;
  final String nombre;
  final double precio;
}

/// Selector de prendas del catálogo local (B1.10.a).
class _SelectorPrendas extends StatelessWidget {
  const _SelectorPrendas({required this.productos, required this.esDevuelta});

  final List<ProductModel> productos;
  final bool esDevuelta;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            esDevuelta ? 'Prenda a devolver' : 'Prenda nueva',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final producto in productos)
            for (final variante in producto.variantes)
              ListTile(
                title: Text(
                  '${producto.nombre} · '
                  '${variante.tallaNombre ?? ''} '
                  '${variante.colorNombre ?? ''}',
                ),
                subtitle: Text('Stock local: ${variante.stockTotal}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(
                  context,
                  _PrendaElegida(
                    variante: variante,
                    nombre:
                        '${producto.nombre} · '
                        '${variante.tallaNombre ?? ''} '
                        '${variante.colorNombre ?? ''}',
                    precio:
                        variante.precioVariante ?? producto.precio,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
