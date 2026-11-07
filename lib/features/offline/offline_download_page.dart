import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/offline_catalog_provider.dart';
import 'widgets/offline_data_stamp.dart';

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
                provider.status.incompleto
                    ? 'La última descarga quedó incompleta.'
                    : '${provider.products.length} productos disponibles',
              ),
              trailing: provider.isLoading
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.chevron_right),
              onTap: provider.isLoading
                  ? null
                  : () async {
                      try {
                        await provider.descargarPaquete();
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('No se pudo descargar: $error'),
                            ),
                          );
                        }
                      }
                    },
            ),
          ),
          if (provider.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(provider.errorMessage!),
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
