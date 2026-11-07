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
