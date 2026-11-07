import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/providers/compensation_provider.dart';
import '../../core/providers/pos_provider.dart';

/// [EXAMEN-2] Inicio del POS offline (CU07).
class PosHomePage extends StatelessWidget {
  const PosHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    // [EXAMEN-2] RF-030/CU19: badge de compensaciones pendientes (cajero).
    var pendientesCompensacion = 0;
    try {
      pendientesCompensacion =
          context.watch<CompensationProvider>().pendientesCount;
    } catch (_) {}
    return Scaffold(
      appBar: AppBar(title: const Text('Punto de venta')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.point_of_sale, size: 72),
            const SizedBox(height: 16),
            Text('Total actual: ${pos.total.toStringAsFixed(2)}'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                pos.startSale();
                context.push('/pos/sale');
              },
              child: const Text('Iniciar venta'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/pos/return'),
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('Devoluciones'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.push('/pos/exchange'),
              icon: const Icon(Icons.swap_horiz_outlined),
              label: const Text('Reposiciones'),
            ),
            const SizedBox(height: 8),
            Badge(
              isLabelVisible: pendientesCompensacion > 0,
              label: Text('$pendientesCompensacion'),
              child: OutlinedButton.icon(
                onPressed: () => context.push('/pos/compensations'),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Compensaciones'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
