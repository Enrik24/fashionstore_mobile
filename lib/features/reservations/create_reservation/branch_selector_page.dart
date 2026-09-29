import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../config/theme.dart';
import '../../../core/models/reservation_model.dart';
import '../../../core/providers/reservation_provider.dart';

class BranchSelectorPage extends StatefulWidget {
  const BranchSelectorPage({super.key});

  @override
  State<BranchSelectorPage> createState() => _BranchSelectorPageState();
}

class _BranchSelectorPageState extends State<BranchSelectorPage> {
  final MapController _mapController = MapController();
  BranchModel? _selectedBranch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ReservationProvider>();
      provider.loadBranches().then((_) {
        if (provider.branches.isNotEmpty && mounted) {
          setState(() {
            _selectedBranch = provider.selectedBranch ?? provider.branches.first;
          });
          _mapController.move(
            LatLng(_selectedBranch!.latitud, _selectedBranch!.longitud),
            14.0,
          );
        }
      });
    });
  }

  void _onBranchTapped(BranchModel branch) {
    setState(() {
      _selectedBranch = branch;
    });
    _mapController.move(
      LatLng(branch.latitud, branch.longitud),
      14.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar Sucursal'),
      ),
      body: Consumer<ReservationProvider>(
        builder: (context, provider, child) {
          if (provider.isLoadingBranches && provider.branches.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }

          final branches = provider.branches;
          final center = _selectedBranch != null
              ? LatLng(_selectedBranch!.latitud, _selectedBranch!.longitud)
              : const LatLng(-17.7833, -63.1821); // Santa Cruz default

          return Stack(
            children: [
              // OpenStreetMap Flutter Map
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 13.0,
                  minZoom: 5.0,
                  maxZoom: 18.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.fashionstore.mobile',
                  ),
                  MarkerLayer(
                    markers: branches.map((branch) {
                      final isSelected = _selectedBranch?.id == branch.id;
                      return Marker(
                        point: LatLng(branch.latitud, branch.longitud),
                        width: 50,
                        height: 50,
                        child: GestureDetector(
                          onTap: () => _onBranchTapped(branch),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.accent : AppColors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.storefront,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),

              // Selected Branch Bottom Sheet Card
              if (_selectedBranch != null)
                Positioned(
                  bottom: 20,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.store, color: AppColors.accent, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedBranch!.nombre,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    _selectedBranch!.direccion,
                                    style: Theme.of(context).textTheme.bodySmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (_selectedBranch!.telefono != null) ...[
                              const Icon(Icons.phone, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                _selectedBranch!.telefono!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(width: 16),
                            ],
                            const Icon(Icons.access_time, size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              '${_selectedBranch!.horarioApertura ?? '10:00'} - ${_selectedBranch!.horarioCierre ?? '22:00'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            context.read<ReservationProvider>().selectBranch(_selectedBranch!);
                            Navigator.pop(context, _selectedBranch);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Seleccionar esta Sucursal',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
