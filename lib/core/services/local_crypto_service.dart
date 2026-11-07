import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:uuid/uuid.dart';

/// [EXAMEN-2] Criptografía local de CU17.
///
/// Usa PBKDF2-HMAC-SHA256 para derivar el hash del PIN y AES-GCM para
/// cifrar campos sensibles. El PIN nunca se persiste en claro.
class LocalCryptoService {
  LocalCryptoService({
    this.iteracionesPbkdf2 = 120000,
    this.longitudClave = 32,
    Uuid? uuid,
    Random? random,
  }) : _uuid = uuid ?? const Uuid(),
       _random = random ?? Random.secure();

  final int iteracionesPbkdf2;
  final int longitudClave;
  final Uuid _uuid;
  final Random _random;

  /// Genera una clave aleatoria de 32 bytes, codificada en Base64.
  String generarClaveBase() {
    return base64UrlEncode(_bytesAleatorios(longitudClave));
  }

  /// Genera un salt aleatorio de 16 bytes, codificado en Base64.
  String generarSalt() {
    return base64UrlEncode(_bytesAleatorios(16));
  }

  /// Deriva una clave secundaria desde el PIN con PBKDF2-HMAC-SHA256.
  Uint8List derivarDesdePin(String pin, String saltBase64) {
    if (pin.isEmpty) {
      throw ArgumentError.value(pin, 'pin', 'El PIN no puede estar vacío.');
    }
    final salt = _decodificarBase64(saltBase64, 'salt');
    final derivador = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iteracionesPbkdf2, longitudClave));
    final salida = Uint8List(longitudClave);
    derivador.deriveKey(Uint8List.fromList(utf8.encode(pin)), 0, salida, 0);
    return salida;
  }

  /// Hashea el PIN con PBKDF2-HMAC-SHA256 y un salt propio.
  String hashearPin(String pin, String saltBase64) {
    return base64UrlEncode(derivarDesdePin(pin, saltBase64));
  }

  /// Verifica el PIN con comparación de tiempo constante.
  bool verificarPin(String pin, String hashBase64, String saltBase64) {
    try {
      final esperado = _decodificarBase64(hashBase64, 'hash');
      final calculado = derivarDesdePin(pin, saltBase64);
      if (esperado.length != calculado.length) return false;
      var diferencia = 0;
      for (var i = 0; i < esperado.length; i++) {
        diferencia |= esperado[i] ^ calculado[i];
      }
      return diferencia == 0;
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  /// Cifra texto con AES-256-GCM.
  ///
  /// El resultado Base64 contiene nonce (12 bytes), ciphertext y tag (16 bytes).
  /// [clave] acepta una clave Base64 o sus bytes crudos.
  String cifrarTexto(String texto, Object clave) {
    final bytesClave = _claveComoBytes(clave);
    if (bytesClave.length != 32) {
      throw ArgumentError.value(clave, 'clave', 'AES-256 requiere 32 bytes.');
    }
    final nonce = _bytesAleatorios(12);
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      true,
      AEADParameters(KeyParameter(bytesClave), 128, nonce, Uint8List(0)),
    );
    final cifrado = cipher.process(Uint8List.fromList(utf8.encode(texto)));
    final salida = Uint8List(nonce.length + cifrado.length);
    salida.setRange(0, nonce.length, nonce);
    salida.setRange(nonce.length, salida.length, cifrado);
    return base64UrlEncode(salida);
  }

  /// Descifra un texto produced por [cifrarTexto].
  String descifrarTexto(String textoCifrado, Object clave) {
    final bytesClave = _claveComoBytes(clave);
    if (bytesClave.length != 32) {
      throw ArgumentError.value(clave, 'clave', 'AES-256 requiere 32 bytes.');
    }
    final paquete = _decodificarBase64(textoCifrado, 'textoCifrado');
    if (paquete.length < 28) {
      throw const FormatException('Paquete AES-GCM inválido.');
    }
    final nonce = Uint8List.sublistView(paquete, 0, 12);
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      false,
      AEADParameters(KeyParameter(bytesClave), 128, nonce, Uint8List(0)),
    );
    final descifrado = cipher.process(Uint8List.sublistView(paquete, 12));
    return utf8.decode(descifrado);
  }

  /// Genera un UUID v4 para operaciones locales.
  String generarUuid() => _uuid.v4();

  Uint8List _bytesAleatorios(int longitud) {
    final bytes = Uint8List(longitud);
    for (var i = 0; i < longitud; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  Uint8List _claveComoBytes(Object clave) {
    if (clave is Uint8List) return clave;
    if (clave is List<int>) return Uint8List.fromList(clave);
    if (clave is String) return _decodificarBase64(clave, 'clave');
    throw ArgumentError.value(clave, 'clave', 'Tipo de clave no soportado.');
  }

  Uint8List _decodificarBase64(String valor, String nombre) {
    try {
      return base64Url.decode(valor);
    } on FormatException {
      try {
        return base64.decode(valor);
      } on FormatException {
        throw FormatException('Valor Base64 inválido: $nombre');
      }
    }
  }
}
