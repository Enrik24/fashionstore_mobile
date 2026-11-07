import '../../config/constants.dart';
import '../services/cart_service.dart';

/// [EXAMEN-2] C2.5 (§7.6) CU15: guarda para UI (mensaje §19 del plan).
bool carritoOfflineGuard(CartService servicio, {void Function(String)? onBloqueo}) {
  if (!servicio.habilitarCarritoOffline) {
    onBloqueo?.call(CartService.mensajeCarritoOfflineDeshabilitado);
    return false;
  }
  return true;
}

/// Endpoint canónico del carrito offline (sin literales).
String get endpointCarritoOffline => AppConstants.epCarritoOffline;
