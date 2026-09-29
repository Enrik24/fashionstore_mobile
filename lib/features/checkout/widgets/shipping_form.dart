import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../core/models/reservation_model.dart';
import '../../../core/providers/checkout_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/reservation_provider.dart';

class ShippingFormWidget extends StatefulWidget {
  final GlobalKey<FormState> formKey;

  const ShippingFormWidget({
    super.key,
    required this.formKey,
  });

  @override
  State<ShippingFormWidget> createState() => _ShippingFormWidgetState();
}

class _ShippingFormWidgetState extends State<ShippingFormWidget> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController(text: 'Santa Cruz');
  final TextEditingController _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final checkout = context.read<CheckoutProvider>();
      final reservation = context.read<ReservationProvider>();

      if (reservation.branches.isEmpty) {
        reservation.loadBranches();
      } else if (checkout.selectedBranch == null && reservation.branches.isNotEmpty) {
        checkout.setSelectedBranch(reservation.branches.first);
      }

      if (auth.clienteProfile != null) {
        if (auth.clienteProfile!.direccionEnvio != null && auth.clienteProfile!.direccionEnvio!.isNotEmpty) {
          _addressController.text = auth.clienteProfile!.direccionEnvio!;
          checkout.setShippingAddress(auth.clienteProfile!.direccionEnvio!);
        }
        if (auth.clienteProfile!.telefono != null && auth.clienteProfile!.telefono!.isNotEmpty) {
          _phoneController.text = auth.clienteProfile!.telefono!;
          checkout.setPhoneNumber(auth.clienteProfile!.telefono!);
        }
      }
    });
  }

  @override
  void dispose() {
    _addressController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checkout = context.watch<CheckoutProvider>();
    final reservation = context.watch<ReservationProvider>();

    return Form(
      key: widget.formKey,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, color: AppColors.accent, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Método de Entrega',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Mode Selector: Shipping vs Pickup
            Row(
              children: [
                Expanded(
                  child: _buildModeCard(
                    title: 'Envío a Domicilio',
                    subtitle: 'Entrega directa',
                    icon: Icons.delivery_dining_outlined,
                    isSelected: checkout.deliveryType == 'SHIPPING',
                    onTap: () => checkout.setDeliveryType('SHIPPING'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildModeCard(
                    title: 'Retiro en Tienda',
                    subtitle: 'En sucursal física',
                    icon: Icons.store_outlined,
                    isSelected: checkout.deliveryType == 'PICKUP',
                    onTap: () {
                      checkout.setDeliveryType('PICKUP');
                      if (checkout.selectedBranch == null && reservation.branches.isNotEmpty) {
                        checkout.setSelectedBranch(reservation.branches.first);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (checkout.deliveryType == 'SHIPPING') ...[
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Dirección de Entrega *',
                  hintText: 'Ej. Av. San Martín #450, Edif. Los Pinos',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
                validator: (val) {
                  if (checkout.deliveryType == 'SHIPPING' && (val == null || val.trim().isEmpty)) {
                    return 'Por favor ingresa la dirección de entrega';
                  }
                  return null;
                },
                onChanged: (val) => checkout.setShippingAddress(val),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        labelText: 'Ciudad',
                        prefixIcon: Icon(Icons.location_city_outlined),
                      ),
                      onChanged: (val) => checkout.setCity(val),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono / Celular',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      onChanged: (val) => checkout.setPhoneNumber(val),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Branch Selection
              const Text(
                'Selecciona la sucursal de retiro:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (reservation.isLoadingBranches)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (reservation.branches.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No hay sucursales disponibles por el momento.'),
                )
              else
                DropdownButtonFormField<BranchModel>(
                  value: checkout.selectedBranch ?? (reservation.branches.isNotEmpty ? reservation.branches.first : null),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.storefront_outlined),
                    labelText: 'Sucursal de Retiro *',
                  ),
                  isExpanded: true,
                  items: reservation.branches.map((branch) {
                    return DropdownMenuItem<BranchModel>(
                      value: branch,
                      child: Text(
                        '${branch.nombre} (${branch.direccion})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      checkout.setSelectedBranch(val);
                    }
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? AppColors.surfaceVariant : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.accent : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.accent : AppColors.textSecondary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isSelected ? AppColors.accent : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
