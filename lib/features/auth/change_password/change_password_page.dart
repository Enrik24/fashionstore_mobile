import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/error_snackbar.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmNewPasswordController = TextEditingController();

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleChangePassword() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.changePassword(
      currentPassword: _currentPasswordController.text,
      newPassword: _newPasswordController.text,
    );

    if (!mounted) return;

    if (success) {
      AppNotifications.showSuccess(
        context,
        '¡Tu contraseña ha sido cambiada exitosamente!',
      );
      context.pop();
    } else {
      AppNotifications.showError(
        context,
        auth.errorMessage ?? 'Error al cambiar la contraseña. Verifica tu contraseña actual.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.primary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Cambiar Contraseña',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      CustomTextField(
                        controller: _currentPasswordController,
                        label: 'Contraseña Actual *',
                        hint: 'Ingresa tu contraseña actual',
                        prefixIcon: Icons.lock_outline_rounded,
                        isPassword: true,
                        validator: AppValidators.requiredField,
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        controller: _newPasswordController,
                        label: 'Nueva Contraseña *',
                        hint: 'Mínimo 8 car., 1 mayús., 1 núm.',
                        prefixIcon: Icons.lock_reset_rounded,
                        isPassword: true,
                        validator: AppValidators.password,
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        controller: _confirmNewPasswordController,
                        label: 'Confirmar Nueva Contraseña *',
                        hint: 'Repite tu nueva contraseña',
                        prefixIcon: Icons.lock_reset_rounded,
                        isPassword: true,
                        validator: (val) => AppValidators.confirmPassword(
                          val,
                          _newPasswordController.text,
                        ),
                      ),
                      const SizedBox(height: 24),
                      PrimaryButton(
                        text: 'Actualizar Contraseña',
                        isLoading: auth.isLoading,
                        icon: Icons.check_circle_outline_rounded,
                        onPressed: _handleChangePassword,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
