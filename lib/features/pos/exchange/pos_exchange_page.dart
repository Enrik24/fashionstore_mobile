// [EXAMEN-2] CU18: reposición offline (POS → Reposiciones).
// Venta original, prenda devuelta, prenda nueva del mismo producto, stock,
// diferencia clasificada y confirmación con nota de reposición local.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  final _varianteDevuelta = TextEditingController();
  final _varianteNueva = TextEditingController();
  final _precioDevuelto = TextEditingController();
  final _precioNuevo = TextEditingController();
  String? _notaRuta;

  @override
  void dispose() {
    _comprobante.dispose();
    _varianteDevuelta.dispose();
    _varianteNueva.dispose();
    _precioDevuelto.dispose();
    _precioNuevo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OfflineReturnProvider>();
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
          TextField(
            controller: _varianteDevuelta,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Variante devuelta (ID)',
            ),
          ),
          TextField(
            controller: _varianteNueva,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Variante nueva — mismo producto (ID)',
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _precioDevuelto,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Precio devuelto',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _precioNuevo,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Precio nuevo',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              final devuelta = int.tryParse(_varianteDevuelta.text) ?? 0;
              final nueva = int.tryParse(_varianteNueva.text) ?? 0;
              final precioDevuelto = double.tryParse(_precioDevuelto.text) ?? 0;
              final precioNuevo = double.tryParse(_precioNuevo.text) ?? 0;
              provider.agregarItem(
                LineaSeleccion(
                  varianteProductoId: devuelta,
                  precioUnitario: precioDevuelto,
                  varianteCambioId: nueva == 0 ? null : nueva,
                  precioVarianteNueva: precioNuevo == 0
                      ? null
                      : precioNuevo,
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Agregar línea'),
          ),
          TextButton(
            onPressed: () {
              final devuelta = int.tryParse(_varianteDevuelta.text);
              if (devuelta != null) {
                showAlternativeSizeSheet(
                  context,
                  varianteId: devuelta,
                );
              }
            },
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
            const ListTile(
              leading: Icon(Icons.help_outline),
              title: Text('SIN_ALTERNATIVA'),
              subtitle: Text(
                'Sin talla mayor ni menor: se deriva a devolución (RN-022).',
              ),
            ),
          if (provider.errorMessage != null)
            Text(
              provider.errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: provider.isLoading || !provider.plazoValido
                ? null
                : () async {
                    final solicitud = await provider
                        .confirmarReposicionOffline(
                          numeroComprobanteOrigen: _comprobante.text,
                          sucursalId: 0,
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
        ],
      ),
    );
  }
}
