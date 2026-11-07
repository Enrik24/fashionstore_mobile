// [EXAMEN-2] CU13/CU18: bloque «Diferencia» reutilizado por devolución y
// reposición. COBRO rojo, SALDO_FAVOR verde, SIN_DIFERENCIA gris.
import 'package:flutter/material.dart';

class ReturnPriceDifferenceCard extends StatelessWidget {
  const ReturnPriceDifferenceCard({
    super.key,
    required this.diferenciaPrecio,
    required this.tipoDiferencia,
    this.montoPagadoDiferencia,
    this.saldoFavor,
    this.detallePorLinea = const [],
  });

  final double diferenciaPrecio;
  final String tipoDiferencia;
  final double? montoPagadoDiferencia;
  final double? saldoFavor;
  final List<Map<String, Object?>> detallePorLinea;

  String get _tipo => tipoDiferencia.toUpperCase();

  Color get _color => switch (_tipo) {
    'COBRO' => Colors.red.shade800,
    'SALDO_FAVOR' => Colors.green.shade800,
    _ => Colors.grey.shade700,
  };

  String get _titulo => switch (_tipo) {
    'COBRO' => 'Cobro',
    'SALDO_FAVOR' => 'Saldo a favor',
    _ => 'Sin diferencia',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (_tipo) {
                  'COBRO' => Icons.payments_outlined,
                  'SALDO_FAVOR' => Icons.account_balance_wallet_outlined,
                  _ => Icons.remove_circle_outline,
                },
                color: _color,
              ),
              const SizedBox(width: 8),
              Text(
                _titulo,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _color,
                ),
              ),
              const Spacer(),
              Text(
                'Bs. ${diferenciaPrecio.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _color,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (montoPagadoDiferencia != null)
            Text(
              'Pagado por diferencia: Bs. '
              '${(montoPagadoDiferencia ?? 0).toStringAsFixed(2)}',
            ),
          if (saldoFavor != null)
            Text(
              'Saldo a favor: Bs. ${(saldoFavor ?? 0).toStringAsFixed(2)}',
            ),
          if (detallePorLinea.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...detallePorLinea.map(
              (linea) => Text(
                '• ${linea['label'] ?? ''}: '
                'Bs. ${((linea['diferencia'] as num?) ?? 0).toStringAsFixed(2)}',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
