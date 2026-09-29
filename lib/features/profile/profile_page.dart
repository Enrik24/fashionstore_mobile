import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/secondary_button.dart';
import '../../core/widgets/error_snackbar.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cerrar Sesión',
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        content: const Text('¿Estás seguro de que deseas cerrar tu sesión en FashionStore?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final auth = context.read<AuthProvider>();
              await auth.logout();
              if (context.mounted) {
                AppNotifications.showSuccess(context, 'Sesión cerrada exitosamente.');
                context.go('/login');
              }
            },
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final profile = auth.clienteProfile;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBar(
        title: 'Mi Perfil',
        showAvatar: false,
      ),
      body: auth.isAuthenticated && user != null
          ? RefreshIndicator(
              onRefresh: () => auth.refreshProfile(),
              color: AppColors.accent,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Avatar Header
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.accent, width: 2),
                            ),
                            child: CircleAvatar(
                              radius: 44,
                              backgroundColor: AppColors.primary,
                              child: Text(
                                user.initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            user.fullName,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.correo,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Role badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              user.roles.isNotEmpty ? user.roles.first.nombre : 'Cliente',
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Information Card with Edit Button
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.badge_outlined, size: 20, color: AppColors.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Datos Personales',
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                              TextButton.icon(
                                onPressed: () => context.push('/profile/edit'),
                                icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.accent),
                                label: const Text('Editar', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          _buildProfileRow(
                            icon: Icons.person_outline_rounded,
                            label: 'Nombre completo',
                            value: user.fullName,
                          ),
                          _buildProfileRow(
                            icon: Icons.email_outlined,
                            label: 'Correo',
                            value: user.correo,
                          ),
                          _buildProfileRow(
                            icon: Icons.badge_outlined,
                            label: 'NIT / CI',
                            value: profile?.nitCi ?? 'No especificado',
                          ),
                          _buildProfileRow(
                            icon: Icons.phone_outlined,
                            label: 'Teléfono',
                            value: (user.telefono != null && user.telefono!.isNotEmpty)
                                ? user.telefono!
                                : (profile?.telefono ?? 'No especificado'),
                          ),
                          _buildProfileRow(
                            icon: Icons.location_on_outlined,
                            label: 'Dirección de Entrega',
                            value: profile?.direccionEnvio ?? 'No especificada',
                          ),
                          if (user.fechaRegistro != null)
                            _buildProfileRow(
                              icon: Icons.calendar_today_outlined,
                              label: 'Miembro desde',
                              value: DateFormat('dd/MM/yyyy').format(user.fechaRegistro!),
                              isLast: true,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Shopping & Activity Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.receipt_long_outlined, color: AppColors.primary, size: 20),
                            ),
                            title: const Text('Historial de Compras', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: const Text('Revisa tus compras en línea y facturación', style: TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                            onTap: () => context.push('/profile/orders'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.favorite_outline, color: AppColors.accent, size: 20),
                            ),
                            title: const Text('Mis Favoritos', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: const Text('Prendas que guardaste para después', style: TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                            onTap: () => context.push('/favorites'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.event_seat_outlined, color: AppColors.primary, size: 20),
                            ),
                            title: const Text('Mis Reservas en Tienda', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: const Text('Prendas apartadas para probar en sucursales', style: TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                            onTap: () => context.push('/reservations'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.assignment_return_outlined, color: AppColors.primary, size: 20),
                            ),
                            title: const Text('Mis Devoluciones', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: const Text('Seguimiento de devoluciones y cambios', style: TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                            onTap: () => context.push('/profile/returns'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // AI Features Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
                            ),
                            title: const Text('Asesor de Moda IA', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: const Text('Chatea y recibe recomendaciones de estilo', style: TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.accent),
                            onTap: () => context.push('/ai-assistant'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.accessibility_new, color: AppColors.accent, size: 20),
                            ),
                            title: const Text('Vestidor Virtual', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: const Text('Pruébate prendas con foto e inteligencia artificial', style: TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.accent),
                            onTap: () => context.push('/ar-fitting'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Security & Session Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.lock_reset_rounded, color: AppColors.primary, size: 20),
                            ),
                            title: const Text('Cambiar Contraseña', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: const Text('Actualiza tu clave de acceso', style: TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                            onTap: () => context.push('/change-password'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
                            ),
                            title: const Text('Cerrar Sesión', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.error)),
                            subtitle: const Text('Finalizar tu sesión actual', style: TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.error),
                            onTap: () => _confirmLogout(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_off_outlined,
                        size: 56,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Inicia Sesión',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Accede a tu cuenta para gestionar tus compras, reservas, probador virtual y asesoría inteligente.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      text: 'Iniciar Sesión',
                      icon: Icons.login_rounded,
                      onPressed: () => context.push('/login'),
                    ),
                    const SizedBox(height: 12),
                    SecondaryButton(
                      text: 'Registrarme',
                      icon: Icons.person_add_outlined,
                      onPressed: () => context.push('/register'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProfileRow({
    required IconData icon,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
