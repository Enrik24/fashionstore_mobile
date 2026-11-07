import 'dart:convert';

import 'package:fashionstore_mobile/core/services/local_crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // [EXAMEN-2] Pruebas de PBKDF2-HMAC-SHA256 y AES-GCM para CU17.
  group('LocalCryptoService', () {
    test('genera una clave base aleatoria de 32 bytes', () {
      final crypto = LocalCryptoService();
      final primera = crypto.generarClaveBase();
      final segunda = crypto.generarClaveBase();

      expect(base64Url.decode(primera), hasLength(32));
      expect(base64Url.decode(segunda), hasLength(32));
      expect(primera, isNot(segunda));
    });

    test('deriva la misma clave con el mismo PIN y salt', () {
      final crypto = LocalCryptoService(iteracionesPbkdf2: 1000);
      final salt = crypto.generarSalt();

      final primera = crypto.derivarDesdePin('135790', salt);
      final segunda = crypto.derivarDesdePin('135790', salt);

      expect(primera, hasLength(32));
      expect(primera, orderedEquals(segunda));
    });

    test('hashea y verifica el PIN sin almacenar el PIN', () {
      final crypto = LocalCryptoService(iteracionesPbkdf2: 1000);
      final salt = crypto.generarSalt();
      final hash = crypto.hashearPin('135790', salt);

      expect(hash, isNot(contains('135790')));
      expect(crypto.verificarPin('135790', hash, salt), isTrue);
      expect(crypto.verificarPin('135791', hash, salt), isFalse);
    });

    test('cifra y descifra campos sensibles con AES-GCM', () {
      final crypto = LocalCryptoService();
      final clave = crypto.generarClaveBase();
      const secreto = 'token-offline-muy-sensible';

      final cifrado = crypto.cifrarTexto(secreto, clave);
      final descifrado = crypto.descifrarTexto(cifrado, clave);

      expect(cifrado, isNot(contains(secreto)));
      expect(descifrado, secreto);
    });

    test('rechaza un ciphertext AES-GCM alterado', () {
      final crypto = LocalCryptoService();
      final clave = crypto.generarClaveBase();
      final cifrado = crypto.cifrarTexto('dato sensible', clave);
      final bytes = base64Url.decode(cifrado);
      bytes[bytes.length - 1] ^= 0x01;

      expect(
        () => crypto.descifrarTexto(base64UrlEncode(bytes), clave),
        throwsA(isA<Exception>()),
      );
    });

    test('genera UUID v4 únicos', () {
      final crypto = LocalCryptoService();
      final primero = crypto.generarUuid();
      final segundo = crypto.generarUuid();

      expect(primero, isNot(segundo));
      expect(primero, matches(RegExp(r'^[0-9a-f-]{36}$')));
    });
  });
}
