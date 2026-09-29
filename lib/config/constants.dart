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
  static const String epInteligenciaRecomendaciones = '/inteligencia/recomendaciones';
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

  // API Endpoints - Public Promotions (informativo en móvil)
  static const String epPromocionesActivas = '/public/promociones/activas';

  // API Endpoints - Push Notifications (CU13, FCM)
  static const String epNotificacionesDispositivos =
      '/notificaciones/dispositivos';

  // Assets paths
  static const String imageLogo = 'assets/images/logo.png';
  static const String imagePlaceholder = 'assets/images/placeholder.png';
}
