// [EXAMEN-2] CU13: devolución pura offline (POS → Devoluciones).
//
// Flujo: busca la venta original (central con red o local sin red), valida el
// plazo RN-012, permite elegir **las prendas concretas** a devolver, el motivo
// y el medio de reembolso, y genera la nota de devolución local.
//
// [EXAMEN-2] B0.1: antes esta pantalla nunca llamaba a
// `OfflineReturnProvider.agregarItem`, por lo que `_items` quedaba vacío y
// `ReturnService.crearDevolucionOffline` lanzaba
// `FormatException('La devolución exige al menos una prenda')`: **el flujo
// nunca podía completarse desde la app**.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/return_request_model.dart';
import '../../../core/providers/offline_return_provider.dart';
import '../../../core/services/offline_document_service.dart';
import '../return/widgets/return_price_difference_card.dart';

class PosReturnPage extends StatefulWidget {
  const PosReturnPage({super.key});

  @override
  State<PosReturnPage> createState() => _PosReturnPageState();
}

class _PosReturnPageState extends State<PosReturnPage> {
  final _comprobante = TextEditingController();
  String? _notaRuta;

  @override
  void initState() {
    super.initState();
    // [EXAMEN-2] B0.1.h: el provider es compartido con la pantalla de
    // reposición; se reinicia para no arrastrar líneas de otra operación.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OfflineReturnProvider>().reiniciarOperacion();
    });
  }

  @override
  void dispose() {
    _comprobante.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final provider = context.read<OfflineReturnProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final venta = await provider.buscarVentaOriginal(_comprobante.text);
    if (!mounted) return;
    final dentro = venta?['dentro_plazo'] == true;
    final limite = venta?['fecha_limite_cambio']?.toString();
    provider.setVentaOriginal(
      venta,
      fechaLimite: limite == null ? null : DateTime.tryParse(limite),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          venta == null
              ? 'Venta no encontrada'
              : dentro
              ? 'Venta encontrada, dentro de plazo'
              : 'Fuera de período permitido',
        ),
      ),
    );
  }

  /// [EXAMEN-2] B0.1.b/c: agrega o quita una prenda de la venta original.
  void _alternarPrenda(
    OfflineReturnProvider provider,
    Map<String, Object?> item,
  ) {
    final varianteId = (item['variante_producto_id'] as num?)?.toInt();
    if (varianteId == null) return;
    final yaElegida = provider.itemsDevolucion.any(
      (e) => e.varianteProductoId == varianteId,
    );
    if (yaElegida) {
      provider.quitarItem(varianteId);
      return;
    }
    final cantidad = (item['cantidad'] as num?)?.toInt() ?? 1;
    provider.agregarItem(
      LineaSeleccion(
        varianteProductoId: varianteId,
        productoId: (item['producto_id'] as num?)?.toInt(),
        productoNombre: item['producto_nombre']?.toString(),
        cantidad: cantidad,
        precioUnitario:
            (item['precio_unitario'] as num?)?.toDouble() ?? 0,
        detalleOrdenId: (item['detalle_orden_id'] as num?)?.toInt(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OfflineReturnProvider>();
    final ventaItems = provider.itemsVentaOriginal;
    return Scaffold(
      appBar: AppBar(title: const Text('Devolución offline')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _comprobante,
            decoration: InputDecoration(
              labelText: 'Número de comprobante o UUID de venta',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _buscar,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (provider.ventaOriginal != null)
            Text(
              provider.plazoValido
                  ? 'Plazo válido (RN-012)'
                  : 'Fuera de período permitido — no se puede devolver',
              style: TextStyle(
                color: provider.plazoValido ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(height: 12),
          // [EXAMEN-2] B0.1.b: listado de las prendas de la venta original.
          if (ventaItems.isNotEmpty) ...[
            Text(
              'Prendas de la venta original (seleccione las que devuelve)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final item in ventaItems)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: CheckboxListTile(
                  value: provider.itemsDevolucion.any(
                    (e) =>
                        e.varianteProductoId ==
                        (item['variante_producto_id'] as num?)?.toInt(),
                  ),
                  onChanged: (v) => _alternarPrenda(provider, item),
                  title: Text(
                    item['producto_nombre']?.toString() ??
                        'Prenda #${item['variante_producto_id']}',
                  ),
                  subtitle: Text(
                    'Cantidad: ${item['cantidad'] ?? 1} · '
                    'Precio: ${((item['precio_unitario'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                  ),
                ),
              ),
          ] else if (provider.ventaOriginal != null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'La venta no tiene detalle local. Verifique el número de comprobante '
                'o conéctese para buscar la venta en el servidor.',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          const SizedBox(height: 12),
          // [EXAMEN-2] B0.1.e: motivo de la devolución.
          DropdownButtonFormField<String>(
            initialValue: provider.motivo,
            decoration: const InputDecoration(
              labelText: 'Motivo de la devolución',
            ),
            items: [
              for (final motivo in MotivosDevolucion.todos)
                DropdownMenuItem<String>(
                  value: motivo,
                  child: Text(_etiquetaMotivo(motivo)),
                ),
            ],
            onChanged: (valor) {
              if (valor != null) provider.setMotivo(valor);
            },
          ),
          const SizedBox(height: 12),
          // [EXAMEN-2] B0.1.f: medio de reembolso.
          DropdownButtonFormField<String>(
            initialValue: provider.medioReembolso,
            decoration: const InputDecoration(labelText: 'Medio de reembolso'),
            items: const [
              DropdownMenuItem<String>(
                value: 'REEMBOLSO',
                child: Text('Reembolso (efectivo / tarjeta)'),
              ),
              DropdownMenuItem<String>(
                value: 'SALDO_FAVOR',
                child: Text('Saldo a favor'),
              ),
            ],
            onChanged: (valor) {
              if (valor != null) provider.setMedioReembolso(valor);
            },
          ),
          const SizedBox(height: 12),
          ReturnPriceDifferenceCard(
            diferenciaPrecio: provider.diferencia,
            tipoDiferencia: provider.diferencia < -0.005
                ? 'SALDO_FAVOR'
                : provider.diferencia > 0.005
                ? 'COBRO'
                : 'SIN_DIFERENCIA',
            saldoFavor: provider.saldoFavor,
          ),
          if (provider.errorMessage != null)
            Text(
              provider.errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            // [EXAMEN-2] B0.1: sólo se habilita con prendas seleccionadas.
            onPressed:
                provider.isLoading ||
                    !provider.plazoValido ||
                    !provider.tieneSeleccion
                ? null
                : () async {
                    final solicitud = await provider
                        .confirmarDevolucionOffline(
                          numeroComprobanteOrigen: _comprobante.text,
                          sucursalId: await provider.resolverSucursalId(),
                        );
                    if (!context.mounted) return;
                    if (solicitud != null) {
                      final docs = context.read<OfflineDocumentService>();
                      _notaRuta = await docs.generarNotaDevolucion(
                        uuidOffline: solicitud.uuidOffline!,
                        datos: OfflineDocumentService.datosNotaDevolucion(
                          uuidOffline: solicitud.uuidOffline!,
                          numeroComprobanteOrigen: _comprobante.text,
                          motivo: solicitud.motivo,
                          diferenciaPrecio: solicitud.diferenciaPrecio,
                          tipoDiferencia: solicitud.tipoDiferencia,
                          saldoFavor: solicitud.saldoFavor,
                          montoReembolso: solicitud.montoReembolso,
                        ),
                      );
                      if (!context.mounted) return;
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Devolución ${solicitud.numeroSolicitud} registrada; nota generada',
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
            icon: const Icon(Icons.assignment_return_outlined),
            label: const Text('Confirmar devolución offline'),
          ),
          if (_notaRuta != null)
            TextButton.icon(
              onPressed: () => context
                  .read<OfflineDocumentService>()
                  .abrirArchivo(_notaRuta!),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Abrir nota de devolución'),
            ),
          const SizedBox(height: 8),
          const Text(
            'La prenda devuelta reingresa al inventario; '
            'no hay prenda nueva ni salida.',
          ),
          const SizedBox(height: 8),
          // [EXAMEN-2] B0.1.d: total real a reembolsar.
          Text(
            provider.medioReembolso == 'SALDO_FAVOR'
                ? 'Saldo a favor: ${provider.totalReembolso.toStringAsFixed(2)}'
                : 'Reembolso estimado: ${provider.totalReembolso.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _etiquetaMotivo(String motivo) {
    switch (motivo) {
      case MotivosDevolucion.tallaIncorrecta:
        return 'Talla incorrecta';
      case MotivosDevolucion.colorIncorrecto:
        return 'Color incorrecto';
      case MotivosDevolucion.defectoFabrica:
        return 'Defecto de fábrica';
      case MotivosDevolucion.otro:
        return 'Otro';
      default:
        return motivo;
    }
  }
}
