import 'package:flutter_test/flutter_test.dart';
import 'package:fashionstore_mobile/core/utils/validators.dart';

void main() {
  group('AppValidators Unit Tests', () {
    test('requiredField returns error if string is null or empty', () {
      expect(AppValidators.requiredField(null), isNotNull);
      expect(AppValidators.requiredField(''), isNotNull);
      expect(AppValidators.requiredField('   '), isNotNull);
      expect(AppValidators.requiredField('Hola'), isNull);
    });

    test('name validator checks minimum length of 2', () {
      expect(AppValidators.name(''), isNotNull);
      expect(AppValidators.name('A'), isNotNull);
      expect(AppValidators.name('Carlos'), isNull);
    });

    test('email validator checks valid and invalid email formats', () {
      expect(AppValidators.email(''), isNotNull);
      expect(AppValidators.email('invalido'), isNotNull);
      expect(AppValidators.email('correo@'), isNotNull);
      expect(AppValidators.email('correo@dominio'), isNotNull);
      expect(AppValidators.email('usuario@fashionstore.com'), isNull);
      expect(AppValidators.email('cliente.vip@test.org'), isNull);
    });

    test('password validator enforces 8+ chars, uppercase, and digit', () {
      expect(AppValidators.password(''), isNotNull);
      expect(AppValidators.password('corta1A'), isNotNull); // 7 chars
      expect(AppValidators.password('minuscula123'), isNotNull); // no uppercase
      expect(AppValidators.password('MAYUSCULAABC'), isNotNull); // no digit
      expect(AppValidators.password('Password123'), isNull); // Valid
      expect(AppValidators.password('Admin2026!'), isNull); // Valid
    });

    test('confirmPassword validator ensures match', () {
      expect(AppValidators.confirmPassword('Pass123', 'Pass456'), isNotNull);
      expect(AppValidators.confirmPassword('Pass123', 'Pass123'), isNull);
    });

    test('phone validator checks minimum length of 7 digits', () {
      expect(AppValidators.phone('123'), isNotNull);
      expect(AppValidators.phone('71234567'), isNull);
      expect(AppValidators.phone('+591 71234567'), isNull);
    });

    test('nitCi validator checks minimum length of 4 chars', () {
      expect(AppValidators.nitCi('12'), isNotNull);
      expect(AppValidators.nitCi('8492019'), isNull);
    });
  });
}
