import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../config/theme.dart';
import '../../../core/models/product_model.dart';
import '../../../core/models/reservation_model.dart';
import '../../../core/providers/reservation_provider.dart';

class CreateReservationPage extends StatefulWidget {
  final ProductModel? product;
  final VarianteProducto? variant;
  final int quantity;
  final int? initialBranchId;
  final List<Map<String, dynamic>>? initialItems;

  const CreateReservationPage({
    super.key,
    this.product,
    this.variant,
    this.quantity = 1,
    this.initialBranchId,
    this.initialItems,
  });

  @override
  State<CreateReservationPage> createState() => _CreateReservationPageState();
}

class _CreateReservationPageState extends State<CreateReservationPage> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String _selectedTimeSlot = '15:00 - 18:00 (Tarde)';
  final TextEditingController _notesController = TextEditingController();
  BranchModel? _branch;

  final List<String> _timeSlots = [
    '10:00 - 13:00 (Mañana)',
    '14:00 - 17:00 (Tarde)',
    '17:00 - 20:00 (Noche)',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ReservationProvider>();
      if (provider.branches.isEmpty) {
        provider.loadBranches().then((_) {
          if (mounted) {
            setState(() {
              _branch = _findInitialBranch(provider) ??
                  provider.selectedBranch;
            });
          }
        });
      } else {
        setState(() {
          _branch = _findInitialBranch(provider) ??
              provider.selectedBranch ??
              provider.branches.first;
        });
      }
    });
  }

  /// Sucursal preseleccionada (p.ej. elegida desde disponibilidad, CU10).
  BranchModel? _findInitialBranch(ReservationProvider provider) {
    final id = widget.initialBranchId;
    if (id == null) return null;
    try {
      return provider.branches.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(now) ? now : _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _chooseBranch() async {
    final selected = await context.push<BranchModel>('/reservations/branch-select');
    if (selected != null && mounted) {
      setState(() {
        _branch = selected;
      });
    }
  }

  Future<void> _submitReservation() async {
    if (_branch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona una sucursal')),
      );
      return;
    }

    final provider = context.read<ReservationProvider>();

    // Ítems: desde el carrito (CU12) o de la variante/producto preseleccionado.
    final items = <Map<String, dynamic>>[];
    if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      items.addAll(widget.initialItems!);
    } else if (widget.variant != null) {
      items.add({
        'variante_producto_id': widget.variant!.id,
        'cantidad': widget.quantity,
      });
    } else if (widget.product != null && widget.product!.variantes.isNotEmpty) {
      items.add({
        'variante_producto_id': widget.product!.variantes.first.id,
        'cantidad': widget.quantity,
      });
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay prendas para reservar')),
      );
      return;
    }

    final res = await provider.createReservation(
      sucursalId: _branch!.id,
      fechaReserva: _selectedDate,
      horarioAproximado: _selectedTimeSlot,
      notas: _notesController.text.trim(),
      items: items,
    );

    if (!mounted) return;

    if (res != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡Reserva ${res.numeroReserva} creada con éxito!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/reservations');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'No se pudo crear la reserva'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEEE d \'de\' MMMM, yyyy', 'es_ES');
    final provider = context.watch<ReservationProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reservar Prenda en Tienda'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Prendas desde el carrito (CU12: reserva multi-prenda)
            if (widget.product == null &&
                widget.initialItems != null &&
                widget.initialItems!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.accent.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined,
                        color: AppColors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${widget.initialItems!.length} prenda(s) de tu carrito para probar en tienda',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            // Preselected Product Card
            if (widget.product != null)
              Container(                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        widget.product!.primaryImage,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.product!.nombre,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          if (widget.variant != null)
                            Text(
                              '${widget.variant!.tallaNombre ?? ''} ${widget.variant!.colorNombre != null ? '• ${widget.variant!.colorNombre}' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          const SizedBox(height: 4),
                          Text(
                            'Cantidad: ${widget.quantity} unidad(es)',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Branch Selector Card
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.storefront, color: AppColors.accent, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Sucursal para Probarse',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: _chooseBranch,
                        icon: const Icon(Icons.map_outlined, size: 16),
                        label: const Text('Ver Mapa', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_branch != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _branch!.nombre,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  _branch!.direccion,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    OutlinedButton(
                      onPressed: _chooseBranch,
                      child: const Text('Seleccionar Sucursal'),
                    ),
                ],
              ),
            ),

            // Date & Time Selector Card
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
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
                      const Icon(Icons.event, color: AppColors.accent, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Fecha y Horario Estimado',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Date Picker button
                  InkWell(
                    onTap: _selectDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_month, color: AppColors.primary, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                dateFormat.format(_selectedDate),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const Icon(Icons.edit_calendar, size: 18, color: AppColors.accent),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Time Slot chips
                  Text(
                    'Horario de visita sugerido:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _timeSlots.map((slot) {
                      final isSelected = _selectedTimeSlot == slot;
                      return ChoiceChip(
                        label: Text(slot),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.surfaceVariant,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSelected ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedTimeSlot = slot;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            // Additional Notes
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
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
                      const Icon(Icons.notes, color: AppColors.accent, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Notas o Indicaciones (Opcional)',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Ej. Deseo probarme también la talla M si está disponible.',
                    ),
                  ),
                ],
              ),
            ),

            // Submit Button
            ElevatedButton(
              onPressed: provider.isCreating ? null : _submitReservation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: provider.isCreating
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Guardando Reserva...'),
                      ],
                    )
                  : const Text(
                      'Confirmar Reserva de Prenda',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
