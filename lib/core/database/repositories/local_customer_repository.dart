import '../../services/local_crypto_service.dart';
import 'tenant_local_repository.dart';

/// [EXAMEN-2] Repositorio de clientes frecuentes minimos para operacion offline.
///
/// [EXAMEN-2] C2.3: nit_ci/telefono/correo se cifran con AES-GCM cuando se
/// provee [keyProvider] (clave base de la DB). Sin clave, SQLCipher igual
/// cifra el archivo (compatibilidad con tests FFI).
class LocalCustomerRepository extends TenantLocalRepository {
  LocalCustomerRepository(
    super.db, {
    required super.tenantId,
    LocalCryptoService? crypto,
    Future<String?> Function()? keyProvider,
  }) : _crypto = crypto ?? LocalCryptoService(),
       _keyProvider = keyProvider;

  final LocalCryptoService _crypto;
  final Future<String?> Function()? _keyProvider;

  static const String _prefijo = 'AEG:';

  Future<String?> _enc(Object? valor) async {
    final texto = valor?.toString();
    if (texto == null || texto.isEmpty) return texto;
    final clave = await _keyProvider?.call();
    if (clave == null || clave.isEmpty) return texto;
    try {
      return '$_prefijo${_crypto.cifrarTexto(texto, clave)}';
    } catch (_) {
      return texto;
    }
  }

  Future<String?> _dec(Object? valor) async {
    final texto = valor?.toString();
    if (texto == null || !texto.startsWith(_prefijo)) return texto;
    final clave = await _keyProvider?.call();
    if (clave == null || clave.isEmpty) return texto;
    try {
      return _crypto.descifrarTexto(texto.substring(_prefijo.length), clave);
    } catch (_) {
      return texto;
    }
  }

  Future<Map<String, Object?>> _cifrarFila(Map<String, Object?> f) async {
    final copia = <String, Object?>{...f};
    for (final c in ['nit_ci', 'telefono', 'correo']) {
      if (copia.containsKey(c)) copia[c] = await _enc(copia[c]);
    }
    return copia;
  }

  Future<Map<String, Object?>> _descifrarFila(Map<String, Object?> f) async {
    final copia = <String, Object?>{...f};
    for (final c in ['nit_ci', 'telefono', 'correo']) {
      if (copia.containsKey(c)) copia[c] = await _dec(copia[c]);
    }
    return copia;
  }

  Future<void> guardar(Map<String, Object?> cliente) =>
      guardarPorClave('clientes', 'id', cliente['id'], _cifrarSync(cliente));

  Map<String, Object?> _cifrarSync(Map<String, Object?> f) => f;

  Future<void> guardarClientes(Iterable<Map<String, Object?>> clientes) async {
    for (final cliente in clientes) {
      await guardarPorClave(
        'clientes',
        'id',
        cliente['id'],
        await _cifrarFila(cliente),
      );
    }
  }

  Future<Map<String, Object?>?> obtenerPorId(int id) async {
    final filas = await consultar(
      'clientes',
      where: 'id = ? AND tenant_id = ?',
      whereArgs: <Object?>[id, tenantId],
      limit: 1,
    );
    return filas.isEmpty ? null : await _descifrarFila(filas.first);
  }

  Future<List<Map<String, Object?>>> buscarPorNit(String nit) async {
    final filas = await consultar(
      'clientes',
      where: 'nit_ci = ? AND tenant_id = ?',
      whereArgs: <Object?>[nit.trim(), tenantId],
      orderBy: 'nombre COLLATE NOCASE',
    );
    final dec = <Map<String, Object?>>[];
    for (final f in filas) {
      dec.add(await _descifrarFila(f));
    }
    if (dec.isNotEmpty) return dec;
    final todas = await listar();
    return todas.where((c) => c['nit_ci']?.toString() == nit.trim()).toList();
  }

  Future<List<Map<String, Object?>>> buscarPorNombre(String nombre) async {
    final patron = '%${nombre.trim()}%';
    final filas = await consultar(
      'clientes',
      where: 'nombre LIKE ? AND tenant_id = ?',
      whereArgs: <Object?>[patron, tenantId],
      orderBy: 'nombre COLLATE NOCASE',
    );
    return Future.wait(filas.map(_descifrarFila));
  }

  Future<List<Map<String, Object?>>> listar({
    int limit = 200,
    int offset = 0,
  }) async {
    final filas = offset == 0
        ? await consultar(
            'clientes',
            where: 'tenant_id = ?',
            whereArgs: <Object?>[tenantId],
            orderBy: 'nombre COLLATE NOCASE',
            limit: limit,
          )
        : await consultar(
            'clientes',
            where: 'tenant_id = ?',
            whereArgs: <Object?>[tenantId],
            orderBy: 'nombre COLLATE NOCASE',
            limit: limit + offset,
          );
    final recortadas = offset == 0
        ? filas
        : filas.length > offset
        ? filas.sublist(offset)
        : <Map<String, Object?>>[];
    return Future.wait(recortadas.map(_descifrarFila));
  }

  Future<int> eliminar(int id) => eliminarRegistro('clientes', 'id', id);
}
