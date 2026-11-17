# fashionstore_mobile

> **Examen 2 — plataforma objetivo: solo Android (D-MOV-22, plan v1.2).**
> - `minSdk 21+`, permisos `INTERNET`, `CAMERA` (POS `mobile_scanner`), `POST_NOTIFICATIONS` (FCM Android 13+).
> - `release` usa firma `debug` **solo para demo**; el APK/AAB de entrega requiere keystore propio.
> - Cifrado local con `sqflite_sqlcipher` (Keystore) + verificación en emulador/dispositivo Android. `ios/` sin build exigido.

## Estado (11/11/2026 — cierre de brechas completo)

- **Alcance:** los 11 casos de uso «Web / Móvil» (CU05–CU09, CU13, CU15–CU19). Los CU solo Web (CU01–CU04, CU10–CU12, CU14, CU20) viven en `fashionstore-frontend/` y no tocan esta app.
- **Calidad:** `flutter test` → **187/187** en verde; `dart analyze` → **0 incidencias**; `flutter build apk --debug` → correcto tras cada ola del cierre.
- **Esquema local:** v5 (`requiere_revision`, `cantidad_no_confirmada`, libro `movimientos_inventario`, índice único de compensaciones) con migración idempotente sin pérdida de datos.
- **Código muerto:** 0 en `lib/` (inventario B2.1 del plan verificado por símbolo).
- **Pendiente único:** revisión manual de los 11 flujos en emulador Android, con y sin red.

## Arquitectura offline (resumen)

- Base cifrada `sqflite_sqlcipher` con clave en `flutter_secure_storage` (`core/database/`), migraciones v1→v5.
- Cola FIFO idempotente (`Idempotency-Key` por lote, deduplicación por `uuid_operacion`, RN-005) con orden por `secuencia_local` (RN-010): `core/services/offline_queue_service.dart` + `sync_engine_service.dart` (contrato documentado en su cabecera).
- Libro de movimientos local para trazabilidad de inventario offline (RN-021): `core/database/repositories/local_return_repository.dart`.
- Clasificador de conflictos con el contrato del backend (`datos_resultado`): `core/utils/conflict_classifier.dart`.
- Descarga de paquete offline con cuota, sello y actualización incremental (CU05): `core/services/offline_catalog_service.dart`.
- Pago diferido con idempotencia, expiración y reintento (CU16): `core/services/pending_payment_service.dart`. La app nunca ejecuta pagos por pasarela (RN-008) ni persiste `client_secret` (RNF-15).

## Documentación del proyecto

- `../plan-cierre-brechas-movil-examen2.md` — plan de cierre de brechas con trazabilidad CU → tarea y registro de avance por ola.
- `../avance-implementacion-movil-examen2.md` — avance general, suites de pruebas, decisiones y desviaciones.

## Build

```bash
flutter pub get
dart analyze          # 0 incidencias
flutter test          # 187/187
flutter build apk --debug
# opcional: --dart-define=STRIPE_PUBLISHABLE_KEY=... (la clave pública del tenant, si existe, tiene prioridad en runtime)
```
