import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/widgets/custom_app_bar.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nombreCtrl;
  late TextEditingController _apellidoCtrl;
  late TextEditingController _telefonoCtrl;
  late TextEditingController _direccionCtrl;
  late TextEditingController _correoCtrl;
  late TextEditingController _nitCiCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    final profile = auth.clienteProfile;

    _nombreCtrl = TextEditingController(text: profile?.nombre ?? user?.nombre ?? '');
    _apellidoCtrl = TextEditingController(text: profile?.apellido ?? user?.apellido ?? '');
    _telefonoCtrl = TextEditingController(text: profile?.telefono ?? user?.telefono ?? '');
    _direccionCtrl = TextEditingController(text: profile?.direccionEnvio ?? '');
    _correoCtrl = TextEditingController(text: user?.correo ?? profile?.correo ?? '');
    _nitCiCtrl = TextEditingController(text: profile?.nitCi ?? '');
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _apellidoCtrl.dispose();
    _telefonoCtrl.dispose();
    _direccionCtrl.dispose();
    _correoCtrl.dispose();
    _nitCiCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final auth = context.read<AuthProvider>();

    final success = await auth.updateProfile(
      nombre: _nombreCtrl.text.trim(),
      apellido: _apellidoCtrl.text.trim(),
      telefono: _telefonoCtrl.text.trim(),
      direccionEnvio: _direccionCtrl.text.trim(),
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil actualizado correctamente'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.errorMessage ?? 'Error al actualizar perfil'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBar(
        title: 'Editar Perfil',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderAvatar(),
              const SizedBox(height: 24),
              _buildSectionTitle('Información Personal'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _nombreCtrl,
                label: 'Nombre',
                icon: Icons.person_outline,
                validator: (val) => val == null || val.trim().isEmpty ? 'El nombre es obligatorio' : null,
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _apellidoCtrl,
                label: 'Apellido',
                icon: Icons.person_outline,
                validator: (val) => val == null || val.trim().isEmpty ? 'El apellido es obligatorio' : null,
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _correoCtrl,
                label: 'Correo Electrónico',
                icon: Icons.email_outlined,
                readOnly: true,
                helperText: 'El correo electrónico no se puede modificar',
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _nitCiCtrl,
                label: 'NIT / CI',
                icon: Icons.badge_outlined,
                readOnly: true,
                helperText: 'Identificación tributaria registrada',
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Contacto y Envío'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _telefonoCtrl,
                label: 'Teléfono / WhatsApp',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _direccionCtrl,
                label: 'Dirección de Entrega Predeterminada',
                icon: Icons.location_on_outlined,
                maxLines: 2,
                helperText: 'Se usará como dirección por defecto en tus compras',
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSaving ? null : _handleSave,
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'Guardar Cambios',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderAvatar() {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    return Center(
      child: Stack(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                user?.initials ?? 'FS',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.playfairDisplay(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool readOnly = false,
    String? helperText,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.inter(
        fontSize: 14,
        color: readOnly ? AppColors.textLight : AppColors.textDark,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textLight),
        helperText: helperText,
        helperStyle: GoogleFonts.inter(fontSize: 11, color: AppColors.textLight),
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: readOnly ? Colors.grey.shade100 : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }
}
