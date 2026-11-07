import 'package:flutter/material.dart';

/// [EXAMEN-2] C2.4 (§5.3, RN-014): sello de descarga y etiqueta
/// "precio referencial" para precios locales sin verificar en servidor.
class OfflineDataStamp extends StatelessWidget {
  const OfflineDataStamp({
    super.key,
    this.sello,
    this.esReferencial = false,
  });

  final DateTime? sello;
  final bool esReferencial;

  @override
  Widget build(BuildContext context) {
    final partes = <String>[];
    if (sello != null) {
      final d = sello!.toLocal();
      partes.add(
        'Datos del ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
      );
    }
    if (esReferencial) partes.add('Precio referencial — verificar al sincronizar');
    if (partes.isEmpty) return const SizedBox.shrink();
    return Text(
      partes.join(' · '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: Theme.of(context).hintColor,
          ),
    );
  }
}
