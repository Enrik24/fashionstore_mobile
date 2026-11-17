// [EXAMEN-2] C1.4: fechas relativas es-BO para sincronización.
class RelativeDateFormat {
  const RelativeDateFormat._();

  static String relative(DateTime? fecha) {
    if (fecha == null) return '—';
    final diff = DateTime.now().difference(fecha);
    if (diff.inSeconds < 60) return 'recién ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 30) return 'hace ${diff.inDays} días';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }

  static String absolute(DateTime? fecha) {
    if (fecha == null) return '—';
    final f = fecha.toLocal();
    return '${f.day}/${f.month}/${f.year} ${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
  }
}

/// [FIX-UI] Cuenta regresiva legible para pagos diferidos (CU16).
///
/// Antes se mostraban los minutos totales (`1439:16` para 23 h 59 m). Ahora:
/// `23 h 59 min`, `1 d 2 h` o `MM:SS` cuando queda menos de una hora.
class CountdownFormat {
  const CountdownFormat._();

  static String legible(Duration? restante) {
    if (restante == null) return 'Sin vencimiento';
    if (restante <= Duration.zero) return 'Vencido';
    if (restante.inHours >= 24) {
      return '${restante.inDays} d ${restante.inHours.remainder(24)} h';
    }
    if (restante.inHours >= 1) {
      return '${restante.inHours} h ${restante.inMinutes.remainder(60)} min';
    }
    final minutos = restante.inMinutes.toString().padLeft(2, '0');
    final segundos = restante.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutos:$segundos';
  }
}
