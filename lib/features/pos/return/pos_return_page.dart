// [EXAMEN-2] CU13: devolución pura offline (POS → Devoluciones).
// Busca la venta original, valida el plazo RN-012, permite elegir entre
// reembolso o saldo a favor y genera la nota de devolución local.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/return_request_model.dart';
import '../../../core/providers/offline_return_provider.dart';
import '../../../core/services/offline_document_service.dart';
import 'widgets/return_price_difference_card.dart';

class PosReturnPage extends StatefulWidget {
  const PosReturnPage({super.key});

  @override
  State<PosReturnPage> createState() => _PosReturnPageState();
}

class _PosReturnPageState extends State<PosReturnPage> {
  final _comprobante = TextEditingController();
  bool _saldoFavor = false;
  String? _notaRuta;

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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OfflineReturnProvider>();
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
          SwitchListTile(
            title: const Text('Saldo a favor (en vez de reembolso)'),
            value: _saldoFavor,
            onChanged: (v) => setState(() => _saldoFavor = v),
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
            onPressed: provider.isLoading || !provider.plazoValido
                ? null
                : () async {
                    final solicitud = await provider
                        .confirmarDevolucionOffline(
                          numeroComprobanteOrigen: _comprobante.text,
                          sucursalId: 0,
                          saldoFavor: _saldoFavor,
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
          Text(
            'Reembolso estimado: Bs. '
            '${MotivosDevolucion.todos.isEmpty ? 0 : provider.diferencia.abs().toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
