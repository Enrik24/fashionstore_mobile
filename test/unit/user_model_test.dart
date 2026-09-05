import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_mobile/core/models/user_model.dart';

void main() {
  group('UserModel and TokenResponse Serialization Tests', () {
    test('TokenResponse fromJson and toJson', () {
      final json = {
        'access_token': 'jwt_access_123',
        'refresh_token': 'jwt_refresh_456',
        'token_type': 'bearer',
      };

      final token = TokenResponse.fromJson(json);
      expect(token.accessToken, 'jwt_access_123');
      expect(token.refreshToken, 'jwt_refresh_456');
      expect(token.tokenType, 'bearer');
      expect(token.toJson(), json);
    });

    test('UserModel parsing and properties', () {
      final json = {
        'id': 1,
        'nombre': 'Carlos',
        'apellido': 'Gomez',
        'correo': 'carlos@test.com',
        'telefono': '71234567',
        'estado': 'ACTIVO',
        'fecha_registro': '2026-03-01T10:00:00Z',
        'roles': [
          {'id': 1, 'nombre': 'Administrador', 'descripcion': 'Superuser'},
        ],
      };

      final user = UserModel.fromJson(json);
      expect(user.id, 1);
      expect(user.fullName, 'Carlos Gomez');
      expect(user.initials, 'CG');
      expect(user.isAdmin, isTrue);
      expect(user.isClient, isFalse);
      expect(user.roles.length, 1);
      expect(user.roles.first.nombre, 'Administrador');
    });

    test('ClienteProfile parsing', () {
      final json = {
        'id': 10,
        'nit_ci': '8492019',
        'direccion_envio': 'Av. Principal #456',
        'nombre': 'Ana',
        'apellido': 'Vargas',
        'correo': 'ana@test.com',
        'telefono': '79876543',
        'fecha_registro': '2026-03-02T12:00:00Z',
      };

      final profile = ClienteProfile.fromJson(json);
      expect(profile.id, 10);
      expect(profile.nitCi, '8492019');
      expect(profile.direccionEnvio, 'Av. Principal #456');
      expect(profile.fullName, 'Ana Vargas');
    });
  });
}
