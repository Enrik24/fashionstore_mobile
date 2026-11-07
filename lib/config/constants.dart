class AppConstants {
  // Storage keys
  static const String keyAccessToken = 'fs_access_token';
  static const String keyRefreshToken = 'fs_refresh_token';
  static const String keyUserData = 'fs_user_data';
  static const String keyClientData = 'fs_client_data';
  static const String keyThemeMode = 'fs_theme_mode';
  static const String keyRememberEmail = 'fs_remember_email';

  // API Endpoints - Auth & Client
  static const String epLogin = '/auth/login';
  static const String epRegister = '/auth/register';
  static const String epLogout = '/auth/logout';
  static const String epRefresh = '/auth/refresh';
  static const String epMe = '/auth/me';
  static const String epChangePassword = '/auth/change-password';
  // API Endpoints - Client Profile & History
  static const String epClientProfile = '/cliente/perfil';
  static const String epClientDireccion = '/cliente/direccion';
  static const String epHistorialCompras = '/cliente/historial-compras';
  static const String epHistorialReservas = '/cliente/historial-reservas';

  // API Endpoints - Public Catalog & Stock
  static const String epPublicCatalogo = '/public/catalogo';
  static const String epPublicProductos = '/public/productos';
  static const String epPublicBuscar = '/public/productos/buscar';
  static const String epPublicDisponibilidad = '/public/disponibilidad';

  // API Endpoints - Catalog Filter Entities
  static const String epCategorias = '/categorias/';
  static const String epTemporadas = '/temporadas/';
  static const String epTallas = '/tallas/';
  static const String epColores = '/colores/';

  // API Endpoints - Cart
  static const String epCarrito = '/carrito/';
  static const String epCarritoItems = '/carrito/items';

  // API Endpoints - Reservations
  static const String epReservas = '/reservas/';
  static const String epMisReservas = '/reservas/mis-reservas';

  // API Endpoints - Orders & Payments
  static const String epOrdenes = '/ordenes/';
  static const String epStripeCheckout = '/pagos/stripe/crear-checkout';
  static const String epStripeConfirmar = '/pagos/stripe/confirmar-retorno';
  static const String epPaypalCrearOrden = '/pagos/paypal/crear-orden';
  static const String epPaypalCapturar = '/pagos/paypal/capturar';
  static const String epTransaccionesOrden = '/pagos/transacciones/orden';

  // API Endpoints - Intelligence / AI
  static const String epInteligenciaRecomendaciones =
      '/inteligencia/recomendaciones';
  static const String epInteligenciaAsistente = '/inteligencia/asistente-chat';
  static const String epVestidorVirtual = '/inteligencia/vestidor-virtual';
  static const String epInteligenciaTendencias = '/inteligencia/tendencias';

  // API Endpoints - Branches
  static const String epSucursales = '/sucursales/';

  // API Endpoints - Favorites (CU25)
  static const String epFavoritos = '/favoritos/';
  static const String epFavoritosIds = '/favoritos/ids';

  // API Endpoints - Reviews (CU26)
  static const String epValoraciones = '/valoraciones/';

  // API Endpoints - Coupons (CU27)
  static const String epCuponesValidar = '/cupones/validar';
  static const String epCuponesDisponibles = '/cupones/disponibles';
  static const String epCarritoAplicarCupon = '/carrito/aplicar-cupon';
  static const String epCarritoRemoverCupon = '/carrito/remover-cupon';

  // API Endpoints - Returns & Exchanges (CU28)
  static const String epDevoluciones = '/devoluciones/';
  static const String epMisDevoluciones = '/devoluciones/mis-solicitudes';

  // [EXAMEN-2] Endpoints N3 — Devolución pura offline (CU13).
  static const String epDevolucionesCambio = '/devoluciones/cambio';
  static const String epDevolucionesVenta = '/devoluciones/venta';
  static const String epDevolucionesValidarPlazo = '/devoluciones/validar-plazo';
  static const String epDevolucionesNota = '/devoluciones';
  static const String epDevolucionesPendientesOffline =
      '/devoluciones/pendientes-offline';

  // [EXAMEN-2] Endpoints N3 — Reposición offline (CU18).
  static const String epDevolucionesReposicion =
      '/devoluciones/reposicion';
  static const String epDevolucionesReposiciones =
      '/devoluciones/reposiciones';
  static const String epDevolucionesNotaReposicion = '/devoluciones';
  static const String epDevolucionesAlternativasTalla =
      '/devoluciones/alternativas-talla';
  static const String epDevolucionesNotificarAlternativa = '/devoluciones';

  // [EXAMEN-2] Endpoints N3 — Compensación en modo cajero (CU19).
  static const String epOfflineCompensaciones = '/offline/compensaciones';
  static const String epOfflineCompensacionesResumen =
      '/offline/compensaciones/resumen';

  // [EXAMEN-2] Endpoints N3 — Notificaciones del cliente (CU18/CU19).
  static const String epNotificacionesMis = '/notificaciones/mis-notificaciones';
  static const String epNotificacionesLeida = '/notificaciones';

  // API Endpoints - Public Promotions (informativo en móvil)
  static const String epPromocionesActivas = '/public/promociones/activas';

  // API Endpoints - Push Notifications (CU13, FCM)
  static const String epNotificacionesDispositivos =
      '/notificaciones/dispositivos';

  // [EXAMEN-2] Endpoints de dispositivos, sesión y configuración offline (Fase 1).
  static const String epOfflineDispositivos = '/offline/dispositivos';
  static const String epOfflineSesionPin = '/offline/sesion/pin';
  static const String epOfflineSesionIniciar = '/offline/sesion/iniciar';
  static const String epOfflineSesionRenovar = '/offline/sesion/renovar';
  static const String epOfflineSesionCerrar = '/offline/sesion/cerrar';
  static const String epOfflineSesionEstado = '/offline/sesion/estado';
  static const String epOfflineConfiguracion = '/offline/configuracion';
  // [EXAMEN-2] Ping real de servidor; se incorpora en la Fase 2.
  static const String epOfflineVersion = '/offline/version';
  // [EXAMEN-2] C2.4/C2.8: endpoints Fase 2 (§15.2). Centralizados, sin literales en servicios.
  static const String epOfflinePaquete = '/offline/paquete';
  static const String epOfflineCatalogo = '/offline/catalogo';
  static const String epOfflineStock = '/offline/stock';
  static const String epOfflineClientes = '/offline/clientes';
  static const String epOfflinePromociones = '/offline/promociones';
  static const String epOfflineDescargasRegistrar =
      '/offline/descargas/registrar';
  static const String epOfflineSync = '/offline/sync';
  static const String epOfflineOperaciones = '/offline/operaciones';
  static const String epOfflineResumen = '/offline/resumen';
  static const String epOfflineConflictos = '/offline/conflictos';
  static const String epCarritoOffline = '/carrito/offline';
  static const String epPagosDiferidos = '/pagos/diferidos';
  static const String epPagosPendientesCount = '/pagos/pendientes/count';
  static const String epWsSync = '/ws/sync';
  static const String epWsPagos = '/ws/pagos';

  // Assets paths
  static const String imageLogo = 'assets/images/logo.png';
  static const String imagePlaceholder = 'assets/images/placeholder.png';
}
