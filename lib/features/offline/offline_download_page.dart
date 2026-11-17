import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/offline_catalog_provider.dart';
import '../../core/widgets/offline_data_stamp.dart';

/// [EXAMEN-2] Descarga del catálogo offline (CU05).
class OfflineDownloadPage extends StatefulWidget {
  const OfflineDownloadPage({super.key});

  @override
  State<OfflineDownloadPage> createState() => _OfflineDownloadPageState();
}

class _OfflineDownloadPageState extends State<OfflineDownloadPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OfflineCatalogProvider>().cargarLocal();
    });
  }

  /// [EXAMEN-2] B1.1.f: confirma la descarga con el mensaje del spec.
  void _alDescargar(OfflineCatalogProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    await provider.descargarPaquete();
    if (!mounted) return;
    final confirmacion = provider.mensajeConfirmacion;
    if (confirmacion != null) {
      messenger.showSnackBar(SnackBar(content: Text(confirmacion)));
      return;
    }
    // [EXAMEN-2] B1.1.i: el paquete no cabe ⇒ se ofrece la descarga selectiva.
    if (provider.requiereDescargaSelectiva) {
      await _ofrecerDescargaSelectiva(provider);
    }
  }

  /// [EXAMEN-2] B1.1.i: "descarga selectiva" con confirmación del usuario.
  Future<void> _ofrecerDescargaSelectiva(
    OfflineCatalogProvider provider,
  ) async {
    final limite = provider.productosSelectivos ?? 0;
    final aceptar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Espacio local insuficiente'),
        content: Text(
          'No cabe todo el catálogo en el dispositivo.\n\n'
          '¿Descargar sólo los $limite productos más vendidos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Descargar selección'),
          ),
        ],
      ),
    );
    if (aceptar != true || !mounted) return;
    await provider.descargarPaquete(limiteProductos: limite);
    if (!mounted) return;
    final confirmacion = provider.mensajeConfirmacion;
    if (confirmacion != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(confirmacion)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OfflineCatalogProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo offline')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Paquete de catálogo y stock'),
              subtitle: Text(
                provider.isDownloading
                    ? 'Descargando catálogo y stock…'
                    : provider.status.incompleto
                    // [EXAMEN-2] B1.1.g: marcador literal del spec.
                    ? 'Incompleto - requiere reconexión'
                    : '${provider.products.length} productos disponibles',
              ),
              trailing: provider.isDownloading
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.chevron_right),
              onTap: provider.isDownloading
                  ? null
                  : () => _alDescargar(provider),
            ),
          ),
          if (provider.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: provider.isDownloading
                        ? null
                        : () => _alDescargar(provider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar descarga'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // [EXAMEN-2] B2.1: actualización incremental (catálogo, stock,
          // clientes y promociones) sin bajar el paquete completo.
          OutlinedButton.icon(
            onPressed: provider.isDownloading
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final resultado = await provider.actualizarDatos();
                    if (!mounted) return;
                    final ok = resultado.values.where((v) => v == 1).length;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          ok > 0
                              ? 'Datos actualizados ($ok de ${resultado.length})'
                              : 'No se pudieron actualizar los datos',
                        ),
                        backgroundColor: ok > 0 ? Colors.green : Colors.red,
                      ),
                    );
                  },
            icon: const Icon(Icons.sync_alt),
            label: const Text('Actualizar datos (incremental)'),
          ),
          const SizedBox(height: 12),
          const OfflineDataStamp(),
          const SizedBox(height: 12),
          ...provider.products.map(
            (producto) => ListTile(
              title: Text(producto.nombre),
              subtitle: Text(
                '${producto.sku} · ${producto.totalStock} unidades',
              ),
              trailing: Text(producto.displayPrice.toStringAsFixed(2)),
            ),
          ),
        ],
      ),
    );
  }
}
