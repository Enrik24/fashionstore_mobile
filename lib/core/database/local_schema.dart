import 'package:sqflite_sqlcipher/sqflite.dart';

// [EXAMEN-2] Esquema SQLite local v1 (CU17).
// La base tiene una fila global reservada para el control de migraciones y
// conserva el tenant_id en todos los datos de negocio.
class LocalSchema {
  const LocalSchema._();

  // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): v3 devoluciones y v4 compensaciones.
  static const int version = 4;
  static const String databaseName = 'fashionstore_movil.db';
  static const int reservedGlobalTenantId = 0;
  static const String schemaMetaKey = '__esquema__';

  static const List<String> tablas = <String>[
    'meta',
    'sesion',
    'configuracion',
    'permisos',
    'bitacora_local',
    'productos',
    'variantes',
    'stock',
    'sucursales',
    'categorias',
    'tallas',
    'colores',
    'clientes',
    'carrito',
    'items_carrito',
    'ordenes_locales',
    'items_orden_local',
    'reservas_locales',
    'items_reserva_local',
    'ventas_locales',
    'items_venta_local',
    'operaciones',
    'pagos',
    'conflictos',
    'comprobantes',
    // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): v3 + v4.
    'devoluciones_locales',
    'items_devolucion_local',
    'compensaciones',
  ];

  /// Tablas cuyos datos se eliminan por tenant.
  static const List<String> tablasPorTenant = <String>[
    'meta',
    'sesion',
    'configuracion',
    'permisos',
    'bitacora_local',
    'productos',
    'variantes',
    'stock',
    'sucursales',
    'categorias',
    'tallas',
    'colores',
    'clientes',
    'carrito',
    'items_carrito',
    'ordenes_locales',
    'items_orden_local',
    'reservas_locales',
    'items_reserva_local',
    'ventas_locales',
    'items_venta_local',
    'operaciones',
    'pagos',
    'conflictos',
    'comprobantes',
    // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): v3 + v4.
    'devoluciones_locales',
    'items_devolucion_local',
    'compensaciones',
  ];

  static const List<String> indices = <String>[
    'idx_meta_tenant',
    'idx_sesion_tenant',
    'idx_configuracion_tenant',
    'idx_permisos_tenant',
    'idx_bitacora_fecha',
    'idx_bitacora_tipo',
    'idx_bitacora_tenant',
    'idx_productos_tenant',
    'idx_productos_updated_at',
    'idx_productos_categoria',
    'idx_productos_nombre',
    'idx_variantes_producto',
    'idx_variantes_tenant',
    'idx_variantes_sku',
    'idx_stock_sucursal',
    'idx_stock_variante',
    'idx_sucursales_tenant',
    'idx_sucursales_estado',
    'idx_categorias_tenant',
    'idx_tallas_tenant',
    'idx_colores_tenant',
    'idx_clientes_tenant',
    'idx_clientes_nit',
    'idx_clientes_nombre',
    'idx_carrito_tenant',
    'idx_carrito_estado',
    'idx_items_carrito_carrito',
    'idx_items_carrito_variante',
    'idx_ordenes_estado',
    'idx_ordenes_tenant',
    'idx_ordenes_expira',
    'idx_items_orden_orden',
    'idx_items_orden_variante',
    'idx_reservas_estado',
    'idx_reservas_tenant',
    'idx_items_reserva_reserva',
    'idx_items_reserva_variante',
    'idx_ventas_tenant',
    'idx_ventas_sucursal',
    'idx_ventas_fecha',
    'idx_items_venta_venta',
    'idx_items_venta_variante',
    'idx_operaciones_estado',
    'idx_operaciones_secuencia',
    'idx_operaciones_tipo',
    'idx_pagos_estado',
    'idx_pagos_tenant',
    'idx_pagos_expiracion',
    'idx_conflictos_resuelto',
    'idx_conflictos_tenant',
    'idx_comprobantes_temporal',
    'idx_comprobantes_tenant',
    // [EXAMEN-2] Fase 3 (CU13/CU18/CU19): v3 + v4.
    'idx_devoluciones_tenant',
    'idx_devoluciones_estado',
    'idx_devoluciones_orden',
    'idx_devoluciones_tipo',
    'idx_items_devolucion_uuid',
    'idx_items_devolucion_detalle',
    'idx_compensaciones_estado',
    'idx_compensaciones_tenant',
    'idx_compensaciones_operacion',
    'uq_compensaciones_operacion',
  ];

  static Future<void> crearV1(DatabaseExecutor db) async {
    // [EXAMEN-2] La definiciÃ³n se ejecuta con IF NOT EXISTS para que una
    // migraciÃ³n interrumpida pueda repetirse sin perder datos.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        clave TEXT NOT NULL,
        tenant_id INTEGER NOT NULL,
        dispositivo_id TEXT,
        usuario_id INTEGER,
        secuencia_local INTEGER NOT NULL DEFAULT 0,
        sello_descarga TEXT,
        cursor_catalogo TEXT,
        version_esquema INTEGER NOT NULL DEFAULT 1,
        fecha_actualizacion TEXT NOT NULL,
        PRIMARY KEY (clave, tenant_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sesion (
        clave TEXT NOT NULL,
        tenant_id INTEGER NOT NULL,
        token_offline TEXT,
        expira_en TEXT,
        intentos_fallidos INTEGER NOT NULL DEFAULT 0,
        pin_configurado INTEGER NOT NULL DEFAULT 0,
        fecha_actualizacion TEXT NOT NULL,
        PRIMARY KEY (clave, tenant_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS configuracion (
        clave TEXT NOT NULL,
        tenant_id INTEGER NOT NULL,
        valor TEXT,
        moneda TEXT,
        impuestos TEXT,
        clave_publica_stripe TEXT,
        banderas_plan TEXT,
        fecha_actualizacion TEXT NOT NULL,
        PRIMARY KEY (clave, tenant_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS permisos (
        clave TEXT NOT NULL,
        tenant_id INTEGER NOT NULL,
        rol TEXT,
        permisos TEXT,
        fecha_actualizacion TEXT NOT NULL,
        PRIMARY KEY (clave, tenant_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bitacora_local (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id INTEGER NOT NULL,
        fecha TEXT NOT NULL,
        tipo TEXT NOT NULL,
        mensaje TEXT,
        datos TEXT
      )
    ''');

    for (final indice in indices) {
      switch (indice) {
        case 'idx_meta_tenant':
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_meta_tenant ON meta(tenant_id)',
          );
        case 'idx_sesion_tenant':
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_sesion_tenant ON sesion(tenant_id)',
          );
        case 'idx_configuracion_tenant':
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_configuracion_tenant ON configuracion(tenant_id)',
          );
        case 'idx_permisos_tenant':
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_permisos_tenant ON permisos(tenant_id)',
          );
        case 'idx_bitacora_fecha':
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_bitacora_fecha ON bitacora_local(fecha)',
          );
        case 'idx_bitacora_tipo':
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_bitacora_tipo ON bitacora_local(tipo)',
          );
        case 'idx_bitacora_tenant':
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_bitacora_tenant ON bitacora_local(tenant_id)',
          );
      }
    }
  }

  /// [EXAMEN-2] Crea las 15 tablas de negocio de la versiÃ³n 2.
  static Future<void> crearV2(DatabaseExecutor db) async {
    // [EXAMEN-2] La v1 no tenía una columna genérica para valores de meta.
    // Se agrega de forma idempotente para conservar instalaciones existentes.
    final columnasMeta = await db.rawQuery('PRAGMA table_info(meta)');
    if (!columnasMeta.any((columna) => columna['name'] == 'valor')) {
      await db.execute('ALTER TABLE meta ADD COLUMN valor TEXT');
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS productos (
        id INTEGER PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, sku TEXT, nombre TEXT NOT NULL, descripcion TEXT,
        categoria_id INTEGER, imagen_url TEXT, imagenes TEXT,
        precio REAL NOT NULL DEFAULT 0, precio_oferta REAL,
        precio_referencia REAL, estado TEXT NOT NULL DEFAULT 'ACTIVO',
        version INTEGER NOT NULL DEFAULT 1, updated_at TEXT, deleted_at TEXT,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS variantes (
        id INTEGER PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, producto_id INTEGER NOT NULL, talla_id INTEGER,
        color_id INTEGER, sku_variante TEXT NOT NULL, precio REAL NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1, updated_at TEXT, deleted_at TEXT,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock (
        variante_id INTEGER NOT NULL, sucursal_id INTEGER NOT NULL,
        tenant_id INTEGER NOT NULL, dispositivo_id TEXT, usuario_id INTEGER,
        cantidad INTEGER NOT NULL DEFAULT 0, updated_at TEXT,
        fecha_actualizacion TEXT NOT NULL, PRIMARY KEY (variante_id, sucursal_id, tenant_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sucursales (
        id INTEGER PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, nombre TEXT NOT NULL, direccion TEXT, telefono TEXT,
        horario TEXT, latitud REAL, longitud REAL, estado TEXT NOT NULL DEFAULT 'ACTIVA',
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categorias (
        id INTEGER PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, nombre TEXT NOT NULL, estado TEXT NOT NULL DEFAULT 'ACTIVA',
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tallas (
        id INTEGER PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, nombre TEXT NOT NULL, estado TEXT NOT NULL DEFAULT 'ACTIVA',
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS colores (
        id INTEGER PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, nombre TEXT NOT NULL, codigo TEXT,
        estado TEXT NOT NULL DEFAULT 'ACTIVO', fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clientes (
        id INTEGER PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, nit_ci TEXT, nombre TEXT NOT NULL, telefono TEXT,
        correo TEXT, estado TEXT NOT NULL DEFAULT 'ACTIVO',
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await _crearTablasComercioV2(db);
    await _crearIndicesV2(db);
    // [EXAMEN-2] Si una beta previa ya tenía la v2, se completan columnas
    // nuevas sin borrar datos ni incrementar la versión global.
    await _asegurarColumnas(db, 'productos', <String, String>{
      'sku': 'TEXT',
      'imagenes': 'TEXT',
      'precio': 'REAL NOT NULL DEFAULT 0',
      'precio_oferta': 'REAL',
      'estado': "TEXT NOT NULL DEFAULT 'ACTIVO'",
      // [EXAMEN-2] C2.3/C2.4 (§3.6, §5.3): tipo de tela y composición solo lectura.
      'tipo_tela_id': 'INTEGER',
      'tipo_tela_nombre': 'TEXT',
      'composicion': 'TEXT',
    });
    await _asegurarColumnas(db, 'variantes', <String, String>{
      // [EXAMEN-2] C2.3: precio_variante (§5.3).
      'precio_variante': 'REAL',
    });
    await _asegurarColumnas(db, 'stock', <String, String>{
      // [EXAMEN-2] C2.3: cantidad reservada y stock mínimo (§5.3).
      'cantidad_reservada': 'INTEGER NOT NULL DEFAULT 0',
      'stock_minimo': 'INTEGER NOT NULL DEFAULT 0',
    });
    await _asegurarColumnas(db, 'pagos', <String, String>{
      // [EXAMEN-2] C2.3/C2.5: PaymentIntent y último intento (§5.7).
      'stripe_payment_intent_id': 'TEXT',
      'fecha_ultimo_intento': 'TEXT',
    });
    await _asegurarColumnas(db, 'operaciones', <String, String>{
      // [EXAMEN-2] C2.3: fechas del contrato §9.5 (§5.10).
      'fecha_ultimo_intento': 'TEXT',
      'fecha_recepcion_servidor': 'TEXT',
      'error_detalle': 'TEXT',
    });
    await _asegurarColumnas(db, 'conflictos', <String, String>{
      // [EXAMEN-2] C2.3: detalle/resolución (§5.10).
      'detalle_json': 'TEXT',
      'fecha': 'TEXT',
      'resuelto_por': 'TEXT',
    });
    await _asegurarColumnas(db, 'carrito', <String, String>{
      'cliente_id': 'INTEGER',
      'es_offline': 'INTEGER NOT NULL DEFAULT 1',
      'estado_sincronizacion': "TEXT NOT NULL DEFAULT 'PENDIENTE'",
      'descuento_aplicado': 'REAL NOT NULL DEFAULT 0',
      'cupon_codigo': 'TEXT',
    });
    await _asegurarColumnas(db, 'ventas_locales', <String, String>{
      'cajero_id': 'INTEGER',
      'es_offline': 'INTEGER NOT NULL DEFAULT 1',
      'estado_sincronizacion': 'TEXT',
    });
    await _asegurarColumnas(db, 'items_venta_local', <String, String>{
      'producto_nombre': 'TEXT',
    });
  }

  static Future<void> _asegurarColumnas(
    DatabaseExecutor db,
    String tabla,
    Map<String, String> definiciones,
  ) async {
    final existentes = await db.rawQuery('PRAGMA table_info($tabla)');
    final nombres = existentes.map((fila) => fila['name']).toSet();
    for (final entrada in definiciones.entries) {
      if (!nombres.contains(entrada.key)) {
        await db.execute(
          'ALTER TABLE $tabla ADD COLUMN ${entrada.key} ${entrada.value}',
        );
      }
    }
  }

  static Future<void> _crearTablasComercioV2(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS carrito (
        uuid_carrito TEXT PRIMARY KEY, tenant_id INTEGER NOT NULL,
        dispositivo_id TEXT, usuario_id INTEGER, cliente_id INTEGER,
        estado TEXT NOT NULL DEFAULT 'ACTIVO', es_offline INTEGER NOT NULL DEFAULT 1,
        estado_sincronizacion TEXT NOT NULL DEFAULT 'PENDIENTE',
        subtotal REAL NOT NULL DEFAULT 0, impuestos REAL NOT NULL DEFAULT 0,
        descuento_aplicado REAL NOT NULL DEFAULT 0, total REAL NOT NULL DEFAULT 0,
        moneda TEXT, cupon_codigo TEXT, sello_descarga TEXT,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS items_carrito (
        id INTEGER PRIMARY KEY AUTOINCREMENT, uuid_carrito TEXT NOT NULL,
        tenant_id INTEGER NOT NULL, dispositivo_id TEXT, usuario_id INTEGER,
        variante_producto_id INTEGER NOT NULL, cantidad INTEGER NOT NULL,
        precio_unitario REAL NOT NULL DEFAULT 0, subtotal REAL NOT NULL DEFAULT 0,
        stock_conocido INTEGER, fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ordenes_locales (
        uuid_orden TEXT PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, estado TEXT NOT NULL, cliente_id INTEGER,
        subtotal REAL NOT NULL DEFAULT 0, impuestos REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0, moneda TEXT, uuid_carrito TEXT,
        expira_en TEXT, datos_json TEXT, fecha_registro_local TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS items_orden_local (
        id INTEGER PRIMARY KEY AUTOINCREMENT, uuid_orden TEXT NOT NULL,
        tenant_id INTEGER NOT NULL, dispositivo_id TEXT, usuario_id INTEGER,
        variante_producto_id INTEGER NOT NULL, cantidad INTEGER NOT NULL,
        precio_unitario REAL NOT NULL DEFAULT 0, subtotal REAL NOT NULL DEFAULT 0,
        stock_conocido INTEGER, fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reservas_locales (
        uuid_reserva TEXT PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, estado TEXT NOT NULL, cliente_id INTEGER,
        producto_id INTEGER, variante_id INTEGER, cantidad INTEGER NOT NULL DEFAULT 1,
        total REAL NOT NULL DEFAULT 0, fecha_reserva TEXT, expira_en TEXT,
        datos_json TEXT, fecha_registro_local TEXT NOT NULL, fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS items_reserva_local (
        id INTEGER PRIMARY KEY AUTOINCREMENT, uuid_reserva TEXT NOT NULL,
        tenant_id INTEGER NOT NULL, dispositivo_id TEXT, usuario_id INTEGER,
        variante_producto_id INTEGER NOT NULL, cantidad INTEGER NOT NULL DEFAULT 1,
        precio_unitario REAL NOT NULL DEFAULT 0, subtotal REAL NOT NULL DEFAULT 0,
        stock_conocido INTEGER, fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ventas_locales (
        uuid_offline TEXT PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, sucursal_id INTEGER NOT NULL, cliente_id INTEGER,
        cajero_id INTEGER, es_offline INTEGER NOT NULL DEFAULT 1,
        estado TEXT NOT NULL, estado_sincronizacion TEXT,
        subtotal REAL NOT NULL DEFAULT 0,
        impuestos REAL NOT NULL DEFAULT 0, total REAL NOT NULL DEFAULT 0,
        monto_recibido REAL NOT NULL DEFAULT 0, cambio REAL NOT NULL DEFAULT 0,
        metodo_pago TEXT, datos_json TEXT, fecha_registro_local TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS items_venta_local (
        id INTEGER PRIMARY KEY AUTOINCREMENT, uuid_offline TEXT NOT NULL,
        tenant_id INTEGER NOT NULL, dispositivo_id TEXT, usuario_id INTEGER,
        variante_producto_id INTEGER NOT NULL, cantidad INTEGER NOT NULL,
        precio_unitario REAL NOT NULL DEFAULT 0, subtotal REAL NOT NULL DEFAULT 0,
        producto_nombre TEXT, stock_conocido INTEGER, fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS operaciones (
        uuid_operacion TEXT PRIMARY KEY, tenant_id INTEGER NOT NULL,
        dispositivo_id TEXT NOT NULL, usuario_id INTEGER, sucursal_id INTEGER,
        secuencia_local INTEGER NOT NULL, tipo_operacion TEXT NOT NULL,
        estado_sincronizacion TEXT NOT NULL, payload_json TEXT NOT NULL,
        fecha_registro_local TEXT NOT NULL, fecha_envio TEXT, fecha_confirmacion TEXT,
        intentos INTEGER NOT NULL DEFAULT 0, proximo_intento TEXT, ultimo_error TEXT,
        resultado_json TEXT, fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pagos (
        uuid_pago TEXT PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, uuid_orden TEXT, estado TEXT NOT NULL, monto REAL NOT NULL DEFAULT 0,
        moneda TEXT, fecha_expiracion TEXT, intentos INTEGER NOT NULL DEFAULT 0,
        ultimo_error TEXT, idempotency_key TEXT, fecha_registro_local TEXT NOT NULL,
        fecha_confirmacion TEXT, datos_json TEXT, fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conflictos (
        id INTEGER PRIMARY KEY AUTOINCREMENT, tenant_id INTEGER NOT NULL,
        dispositivo_id TEXT, usuario_id INTEGER, uuid_operacion TEXT, tipo TEXT NOT NULL,
        motivo TEXT NOT NULL, datos_local TEXT, datos_central TEXT, accion TEXT,
        estado TEXT NOT NULL DEFAULT 'PENDIENTE', resuelto INTEGER NOT NULL DEFAULT 0,
        fecha_registro_local TEXT NOT NULL, fecha_resolucion TEXT,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS comprobantes (
        uuid_offline TEXT PRIMARY KEY, tenant_id INTEGER NOT NULL, dispositivo_id TEXT,
        usuario_id INTEGER, tipo_operacion TEXT NOT NULL, ruta_archivo TEXT,
        nombre_archivo TEXT, mime_type TEXT, es_temporal INTEGER NOT NULL DEFAULT 1,
        datos_json TEXT, fecha_registro_local TEXT NOT NULL, fecha_actualizacion TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _crearIndicesV2(DatabaseExecutor db) async {
    const definiciones = <String, String>{
      'idx_productos_tenant': 'productos(tenant_id)',
      'idx_productos_updated_at': 'productos(updated_at)',
      'idx_productos_categoria': 'productos(categoria_id)',
      'idx_productos_nombre': 'productos(nombre)',
      'idx_variantes_producto': 'variantes(producto_id)',
      'idx_variantes_tenant': 'variantes(tenant_id)',
      'idx_variantes_sku': 'variantes(sku_variante)',
      'idx_stock_sucursal': 'stock(sucursal_id)',
      'idx_stock_variante': 'stock(variante_id)',
      'idx_sucursales_tenant': 'sucursales(tenant_id)',
      'idx_sucursales_estado': 'sucursales(estado)',
      'idx_categorias_tenant': 'categorias(tenant_id)',
      'idx_tallas_tenant': 'tallas(tenant_id)',
      'idx_colores_tenant': 'colores(tenant_id)',
      'idx_clientes_tenant': 'clientes(tenant_id)',
      'idx_clientes_nit': 'clientes(nit_ci)',
      'idx_clientes_nombre': 'clientes(nombre)',
      'idx_carrito_tenant': 'carrito(tenant_id)',
      'idx_carrito_estado': 'carrito(estado)',
      'idx_items_carrito_carrito': 'items_carrito(uuid_carrito)',
      'idx_items_carrito_variante': 'items_carrito(variante_producto_id)',
      'idx_ordenes_estado': 'ordenes_locales(estado)',
      'idx_ordenes_tenant': 'ordenes_locales(tenant_id)',
      'idx_ordenes_expira': 'ordenes_locales(expira_en)',
      'idx_items_orden_orden': 'items_orden_local(uuid_orden)',
      'idx_items_orden_variante': 'items_orden_local(variante_producto_id)',
      'idx_reservas_estado': 'reservas_locales(estado)',
      'idx_reservas_tenant': 'reservas_locales(tenant_id)',
      'idx_items_reserva_reserva': 'items_reserva_local(uuid_reserva)',
      'idx_items_reserva_variante': 'items_reserva_local(variante_producto_id)',
      'idx_ventas_tenant': 'ventas_locales(tenant_id)',
      'idx_ventas_sucursal': 'ventas_locales(sucursal_id)',
      'idx_ventas_fecha': 'ventas_locales(fecha_registro_local)',
      'idx_items_venta_venta': 'items_venta_local(uuid_offline)',
      'idx_items_venta_variante': 'items_venta_local(variante_producto_id)',
      'idx_operaciones_estado': 'operaciones(estado_sincronizacion)',
      'idx_operaciones_secuencia': 'operaciones(secuencia_local)',
      'idx_operaciones_tipo': 'operaciones(tipo_operacion)',
      'idx_pagos_estado': 'pagos(estado)',
      'idx_pagos_tenant': 'pagos(tenant_id)',
      'idx_pagos_expiracion': 'pagos(fecha_expiracion)',
      'idx_conflictos_resuelto': 'conflictos(resuelto)',
      'idx_conflictos_tenant': 'conflictos(tenant_id)',
      'idx_comprobantes_temporal': 'comprobantes(es_temporal)',
      'idx_comprobantes_tenant': 'comprobantes(tenant_id)',
    };
    for (final entrada in definiciones.entries) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS ${entrada.key} ON ${entrada.value}',
      );
    }
  }

  /// [EXAMEN-2] v3: devoluciones y reposiciones creadas sin conexion (CU13/CU18).
  /// Idempotente y sin borrar datos de v2: usa IF NOT EXISTS y no DROP.
  static Future<void> crearV3(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS devoluciones_locales (
        uuid_offline TEXT PRIMARY KEY,
        tenant_id INTEGER NOT NULL,
        dispositivo_id TEXT,
        usuario_id INTEGER,
        orden_origen_id INTEGER,
        numero_comprobante_origen TEXT,
        numero_solicitud TEXT,
        numero_reposicion TEXT,
        tipo TEXT NOT NULL DEFAULT 'DEVOLUCION',
        motivo TEXT,
        motivo_detalle TEXT,
        estado TEXT NOT NULL,
        estado_sincronizacion TEXT,
        es_offline INTEGER NOT NULL DEFAULT 1,
        diferencia_precio REAL NOT NULL DEFAULT 0,
        tipo_diferencia TEXT,
        monto_pagado_diferencia REAL NOT NULL DEFAULT 0,
        saldo_favor REAL NOT NULL DEFAULT 0,
        monto_reembolso REAL NOT NULL DEFAULT 0,
        fecha_limite_cambio TEXT,
        cliente_id INTEGER,
        sucursal_id INTEGER,
        nota_devolucion_url TEXT,
        nota_reposicion_url TEXT,
        datos_json TEXT,
        fecha_registro_local TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS items_devolucion_local (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid_offline TEXT NOT NULL,
        tenant_id INTEGER NOT NULL,
        dispositivo_id TEXT,
        usuario_id INTEGER,
        detalle_orden_id INTEGER,
        variante_producto_id INTEGER NOT NULL,
        variante_cambio_id INTEGER,
        producto_id INTEGER,
        cantidad INTEGER NOT NULL DEFAULT 1,
        precio_unitario REAL NOT NULL DEFAULT 0,
        precio_variante_nueva REAL,
        diferencia REAL NOT NULL DEFAULT 0,
        subtotal_diferencia REAL NOT NULL DEFAULT 0,
        estado_item TEXT NOT NULL DEFAULT 'PENDIENTE',
        producto_nombre TEXT,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    // [EXAMEN-2] v3: columnas de Fase 3 que pueden faltar en beta previa.
    await _asegurarColumnas(db, 'devoluciones_locales', <String, String>{
      'numero_comprobante_origen': 'TEXT',
      'numero_reposicion': 'TEXT',
      'tipo': "TEXT NOT NULL DEFAULT 'DEVOLUCION'",
      'diferencia_precio': 'REAL NOT NULL DEFAULT 0',
      'tipo_diferencia': 'TEXT',
      'monto_pagado_diferencia': 'REAL NOT NULL DEFAULT 0',
      'saldo_favor': 'REAL NOT NULL DEFAULT 0',
      'monto_reembolso': 'REAL NOT NULL DEFAULT 0',
      'fecha_limite_cambio': 'TEXT',
      'nota_devolucion_url': 'TEXT',
      'nota_reposicion_url': 'TEXT',
    });
    await _crearIndicesV3(db);
  }

  /// [EXAMEN-2] v4: tipo/numero_reposicion + compensaciones (CU19).
  /// Si la Fase 3 llega despues de v3, aplica en la misma iteracion.
  static Future<void> crearV4(DatabaseExecutor db) async {
    await crearV3(db);
    await _asegurarColumnas(db, 'devoluciones_locales', <String, String>{
      'tipo': "TEXT NOT NULL DEFAULT 'DEVOLUCION'",
      'numero_reposicion': 'TEXT',
    });
    await db.execute('''
      CREATE TABLE IF NOT EXISTS compensaciones (
        id INTEGER PRIMARY KEY,
        tenant_id INTEGER NOT NULL,
        dispositivo_id TEXT,
        usuario_id INTEGER,
        operacion_offline_id INTEGER,
        uuid_operacion TEXT,
        orden_id INTEGER,
        cliente_id INTEGER,
        monto REAL NOT NULL DEFAULT 0,
        moneda TEXT,
        tipo TEXT NOT NULL,
        estado TEXT NOT NULL,
        referencia_externa TEXT,
        motivo TEXT,
        notificado_cliente INTEGER NOT NULL DEFAULT 0,
        error_detalle TEXT,
        resuelto_por TEXT,
        fecha_creacion TEXT,
        fecha_completado TEXT,
        fecha_resolucion TEXT,
        datos_json TEXT,
        fecha_actualizacion TEXT NOT NULL
      )
    ''');
    await _crearIndicesV4(db);
  }

  static Future<void> _crearIndicesV3(DatabaseExecutor db) async {
    const definiciones = <String, String>{
      'idx_devoluciones_tenant': 'devoluciones_locales(tenant_id)',
      'idx_devoluciones_estado': 'devoluciones_locales(estado)',
      'idx_devoluciones_orden': 'devoluciones_locales(orden_origen_id)',
      'idx_devoluciones_tipo': 'devoluciones_locales(tipo)',
      'idx_items_devolucion_uuid': 'items_devolucion_local(uuid_offline)',
      'idx_items_devolucion_detalle':
          'items_devolucion_local(detalle_orden_id)',
    };
    for (final entrada in definiciones.entries) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS ${entrada.key} ON ${entrada.value}',
      );
    }
  }

  static Future<void> _crearIndicesV4(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_compensaciones_estado ON compensaciones(estado)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_compensaciones_tenant ON compensaciones(tenant_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_compensaciones_operacion ON compensaciones(uuid_operacion)',
    );
    // [EXAMEN-2] CU19: una sola compensacion por operacion rechazada.
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_compensaciones_operacion ON compensaciones(operacion_offline_id)',
    );
  }
}
