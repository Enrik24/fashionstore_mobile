import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/device_model.dart';
import '../../core/services/device_service.dart';

/// [EXAMEN-2] CU17: listado y revocación de dispositivos autorizados.
class OfflineDevicesPage extends StatefulWidget {
  const OfflineDevicesPage({super.key});

  @override
  State<OfflineDevicesPage> createState() => _OfflineDevicesPageState();
}

class _OfflineDevicesPageState extends State<OfflineDevicesPage> {
  late Future<List<DeviceModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<DeviceService>().listar();
  }

  void _reload() {
    setState(() => _future = context.read<DeviceService>().listar());
  }

  Future<void> _revoke(DeviceModel device) async {
    try {
      await context.read<DeviceService>().revocar(
        device.id,
        motivo: 'Revocado desde la app móvil',
      );
      _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo revocar el dispositivo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos')),
      body: FutureBuilder<List<DeviceModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'No se pudieron cargar los dispositivos.\n${snapshot.error}',
              ),
            );
          }
          final devices = snapshot.data ?? const [];
          if (devices.isEmpty) {
            return const Center(
              child: Text('No hay dispositivos registrados.'),
            );
          }
          return ListView.separated(
            itemCount: devices.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final device = devices[index];
              return ListTile(
                leading: Icon(
                  device.plataforma == 'IOS'
                      ? Icons.phone_iphone
                      : Icons.devices,
                ),
                title: Text(
                  device.nombre?.isNotEmpty == true
                      ? device.nombre!
                      : device.plataforma,
                ),
                subtitle: Text(device.activo ? 'Activo' : 'Revocado'),
                trailing: device.activo
                    ? TextButton(
                        onPressed: () => _revoke(device),
                        child: const Text('Revocar'),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
