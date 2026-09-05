class AppValidators {
  static String? requiredField(String? value, [String message = 'Este campo es obligatorio']) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  static String? name(String? value, [String fieldName = 'El nombre']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName es obligatorio';
    }
    if (value.trim().length < 2) {
      return '$fieldName debe tener al menos 2 caracteres';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El correo electrónico es obligatorio';
    }
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Ingresa un correo electrónico válido';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'La contraseña es obligatoria';
    }
    if (value.length < 8) {
      return 'La contraseña debe tener al menos 8 caracteres';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Debe incluir al menos una letra mayúscula';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Debe incluir al menos un número';
    }
    return null;
  }

  static String? confirmPassword(String? value, String originalPassword) {
    if (value == null || value.isEmpty) {
      return 'Confirma tu contraseña';
    }
    if (value != originalPassword) {
      return 'Las contraseñas no coinciden';
    }
    return null;
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El teléfono es obligatorio';
    }
    final cleanPhone = value.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    if (cleanPhone.length < 7) {
      return 'Ingresa un número de teléfono válido (mínimo 7 dígitos)';
    }
    return null;
  }

  static String? nitCi(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El NIT o CI es obligatorio';
    }
    if (value.trim().length < 4) {
      return 'El NIT o CI debe tener al menos 4 caracteres';
    }
    return null;
  }
}
