import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/providers/offline_session_provider.dart';
import '../../core/services/storage_service.dart';

/// [EXAMEN-2] CU17: acceso local mediante PIN.
class OfflineAccessPage extends StatefulWidget {
  const OfflineAccessPage({super.key});

  @override
  State<OfflineAccessPage> createState() => _OfflineAccessPageState();
}

class _OfflineAccessPageState extends State<OfflineAccessPage> {
  final _pin = TextEditingController();
  bool _visible = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _access() async {
    final provider = context.read<OfflineSessionProvider>();
    final ok = await provider.iniciar(_pin.text);
    if (!mounted) return;
    if (ok) {
      context.go('/home');
    } else if (provider.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.error!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OfflineSessionProvider>();
    final restante = state.tiempoRestante;
    final tenantNombre =
        context.read<StorageService>().getUser()?.tenantNombre ??
        'FashionStore';
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso sin conexión')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 72),
                  const SizedBox(height: 16),
                  Text(
                    tenantNombre,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.sesionVencida
                        ? 'Sesión vencida: solo consulta. Conéctate para operar.'
                        : 'Ingresa tu PIN para operar sin conexión.',
                    textAlign: TextAlign.center,
                  ),
                  if (state.expiraEn != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Vence en ${restante.inHours}h ${restante.inMinutes.remainder(60)}m',
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    obscureText: !_visible,
                    maxLength: 12,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _visible ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _visible = !_visible),
                      ),
                    ),
                    onSubmitted: (_) => _access(),
                  ),
                  const SizedBox(height: 12),
                  if (state.intentosRestantes < 5)
                    Text('Intentos restantes: ${state.intentosRestantes}'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: state.cargando ? null : _access,
                      child: Text(state.cargando ? 'Validando…' : 'Entrar'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => context.go('/login'),
                    icon: const Icon(Icons.cloud_off_outlined),
                    label: const Text('Conectar al servidor'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
