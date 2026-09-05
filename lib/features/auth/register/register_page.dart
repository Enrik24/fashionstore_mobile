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

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _apellidoController = TextEditingController();
  final _correoController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _nitCiController = TextEditingController();
  final _direccionController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _acceptTerms = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _correoController.dispose();
    _telefonoController.dispose();
    _nitCiController.dispose();
    _direccionController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      AppNotifications.showError(
        context,
        'Por favor completa todos los campos requeridos correctamente.',
      );
      return;
    }

    if (!_acceptTerms) {
      AppNotifications.showError(
        context,
        'Debes aceptar los términos y condiciones para continuar.',
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      nombre: _nombreController.text.trim(),
      apellido: _apellidoController.text.trim(),
      correo: _correoController.text.trim(),
      telefono: _telefonoController.text.trim(),
      nitCi: _nitCiController.text.trim(),
      direccionEnvio: _direccionController.text.trim(),
      contrasena: _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      AppNotifications.showSuccess(
        context,
        '¡Cuenta creada exitosamente! Bienvenido a FashionStore.',
      );
      context.go('/home');
    } else {
      AppNotifications.showError(
        context,
        auth.errorMessage ?? 'Error al registrar la cuenta. Verifica los datos.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.primary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Registro de Cliente',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Crea tu cuenta',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Completa tus datos para disfrutar de reservas y compras exclusivas.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Form card
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
                      // Name & Surname row
                      Row(
                        children: [
                          Expanded(
                            child: CustomTextField(
                              controller: _nombreController,
                              label: 'Nombre *',
                              hint: 'Carlos',
                              prefixIcon: Icons.person_outline_rounded,
                              textCapitalization: TextCapitalization.words,
                              validator: (val) => AppValidators.name(val, 'El nombre'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomTextField(
                              controller: _apellidoController,
                              label: 'Apellido *',
                              hint: 'Gómez',
                              prefixIcon: Icons.person_outline_rounded,
                              textCapitalization: TextCapitalization.words,
                              validator: (val) => AppValidators.name(val, 'El apellido'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Email
                      CustomTextField(
                        controller: _correoController,
                        label: 'Correo Electrónico *',
                        hint: 'ejemplo@correo.com',
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: AppValidators.email,
                      ),
                      const SizedBox(height: 16),

                      // NIT/CI & Phone Row
                      Row(
                        children: [
                          Expanded(
                            child: CustomTextField(
                              controller: _nitCiController,
                              label: 'NIT / CI *',
                              hint: '8492019',
                              prefixIcon: Icons.badge_outlined,
                              keyboardType: TextInputType.text,
                              validator: AppValidators.nitCi,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomTextField(
                              controller: _telefonoController,
                              label: 'Teléfono *',
                              hint: '71234567',
                              prefixIcon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              validator: AppValidators.phone,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Shipping Address (optional)
                      CustomTextField(
                        controller: _direccionController,
                        label: 'Dirección de Entrega (Opcional)',
                        hint: 'Av. Las Palmeras #123, Zona Norte',
                        prefixIcon: Icons.location_on_outlined,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 16),

                      // Password
                      CustomTextField(
                        controller: _passwordController,
                        label: 'Contraseña *',
                        hint: 'Mínimo 8 car., 1 mayús., 1 núm.',
                        prefixIcon: Icons.lock_outline_rounded,
                        isPassword: true,
                        validator: AppValidators.password,
                      ),
                      const SizedBox(height: 16),

                      // Confirm Password
                      CustomTextField(
                        controller: _confirmPasswordController,
                        label: 'Confirmar Contraseña *',
                        hint: 'Repite tu contraseña',
                        prefixIcon: Icons.lock_outline_rounded,
                        isPassword: true,
                        validator: (val) => AppValidators.confirmPassword(
                          val,
                          _passwordController.text,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Terms & Conditions Checkbox
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _acceptTerms,
                              activeColor: AppColors.accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _acceptTerms = val ?? false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Acepto los términos y condiciones y políticas de privacidad de FashionStore.',
                              style: TextStyle(
                                fontSize: 12,
                                color: _acceptTerms ? AppColors.textPrimary : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Submit Button
                      PrimaryButton(
                        text: 'Crear mi Cuenta',
                        isLoading: auth.isLoading,
                        icon: Icons.person_add_outlined,
                        onPressed: _handleRegister,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Login Prompt
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '¿Ya tienes una cuenta?',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text(
                      'Iniciar Sesión',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
