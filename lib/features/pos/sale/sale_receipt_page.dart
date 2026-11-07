// [EXAMEN-2] CU13/CU18: comprobante temporal y nota de devolución o
// reposición con QR y apertura del PDF.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/services/offline_document_service.dart';
import '../return/widgets/return_price_difference_card.dart';

class SaleReceiptPage extends StatelessWidget {
  const SaleReceiptPage({
    super.key,
    required this.uuidOffline,
    this.titulo = 'Comprobante temporal',
    this.diferenciaPrecio,
    this.tipoDiferencia,
    this.saldoFavor,
    this.rutaPdf,
  });

  final String uuidOffline;
  final String titulo;
  final double? diferenciaPrecio;
  final String? tipoDiferencia;
  final double? saldoFavor;
  final String? rutaPdf;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Venta en modo offline — pendiente de confirmación',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Center(
            child: QrImageView(
              data: uuidOffline,
              size: 200,
              semanticsLabel: 'Código QR del comprobante',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            uuidOffline,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
          if (diferenciaPrecio != null) ...[
            const SizedBox(height: 16),
            ReturnPriceDifferenceCard(
              diferenciaPrecio: diferenciaPrecio!,
              tipoDiferencia: tipoDiferencia ?? 'SIN_DIFERENCIA',
              saldoFavor: saldoFavor,
            ),
          ],
          const SizedBox(height: 24),
          if (rutaPdf != null)
            FilledButton.icon(
              onPressed: () => context
                  .read<OfflineDocumentService>()
                  .abrirArchivo(rutaPdf!),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Reimprimir / abrir PDF'),
            ),
        ],
      ),
    );
  }
}
