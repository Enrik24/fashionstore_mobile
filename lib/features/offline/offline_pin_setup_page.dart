import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/offline_session_provider.dart';

/// [EXAMEN-2] CU17: configurar o cambiar el PIN offline.
class OfflinePinSetupPage extends StatefulWidget {
  const OfflinePinSetupPage({super.key});

  @override
  State<OfflinePinSetupPage> createState() => _OfflinePinSetupPageState();
}

class _OfflinePinSetupPageState extends State<OfflinePinSetupPage> {
  final _pin = TextEditingController();
  final _password = TextEditingController();
  bool _cargando = false;

  @override
  void dispose() {
    _pin.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _cargando = true);
    try {
      // [EXAMEN-2] C1.2: página -> provider -> servicio (no servicio directo).
      final ok = await context.read<OfflineSessionProvider>().configurarPin(
        pin: _pin.text,
        contrasenaActual: _password.text,
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PIN offline configurado.')));
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              context.read<OfflineSessionProvider>().error ?? 'Error al guardar PIN',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = context.read<OfflineSessionProvider>().pinConfigurado;
    return Scaffold(
      appBar: AppBar(title: const Text('Seguridad offline')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: ListTile(
              leading: Icon(configured ? Icons.verified_user : Icons.lock_open),
              title: Text(
                configured ? 'PIN configurado' : 'PIN no configurado',
              ),
              subtitle: const Text(
                'Usa entre 6 y 12 dígitos. El PIN nunca se guarda en claro.',
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña actual'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 12,
            decoration: const InputDecoration(labelText: 'Nuevo PIN'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _cargando ? null : _save,
            child: Text(_cargando ? 'Guardando…' : 'Guardar PIN'),
          ),
        ],
      ),
    );
  }
}
