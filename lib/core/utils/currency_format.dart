// [EXAMEN-2] C2.8/C1.4: formato de moneda del tenant (plan §15.1, §4.3).
class CurrencyFormat {
  const CurrencyFormat._();

  /// Formatea un monto con la moneda del paquete offline (BOB/Bs. por defecto).
  static String format(double monto, {String moneda = 'BOB'}) {
    final m = moneda.trim().toUpperCase();
    final simbolos = <String, String>{
      'BOB': 'Bs.',
      'USD': r'$',
      'EUR': '€',
      'PEN': 'S/',
      'CLP': r'$',
    };
    final simbolo = simbolos[m] ?? m;
    final signo = monto < 0 ? '-' : '';
    final valor = monto.abs();
    final partes = valor.toStringAsFixed(2).split('.');
    final enteros = partes[0];
    final decimales = partes.length > 1 ? partes[1] : '00';
    final buffer = StringBuffer();
    for (var i = 0; i < enteros.length; i++) {
      if (i > 0 && (enteros.length - i) % 3 == 0) buffer.write('.');
      buffer.write(enteros[i]);
    }
    return '$signo$simbolo $buffer,$decimales';
  }

  static String simbolo(String moneda) {
    final m = moneda.trim().toUpperCase();
    return <String, String>{
      'BOB': 'Bs.',
      'USD': r'$',
      'EUR': '€',
      'PEN': 'S/',
      'CLP': r'$',
    }[m] ?? m;
  }
}
