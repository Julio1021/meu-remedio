import 'package:intl/intl.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// 'yyyy-MM-dd' para uma data local.
String dateKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// 'yyyy-MM-ddTHH:mm' (horário de parede local, precisão de minuto).
String dtKey(DateTime d) => '${dateKey(d)}T${_two(d.hour)}:${_two(d.minute)}';

DateTime parseDateKey(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime parseDtKey(String s) {
  final parts = s.split('T');
  final d = parseDateKey(parts[0]);
  final t = parts.length > 1 ? parts[1].split(':') : ['0', '0'];
  return DateTime(d.year, d.month, d.day, int.parse(t[0]), int.parse(t[1]));
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 'HH:mm' -> (hora, minuto)
(int, int) parseHm(String s) {
  final p = s.split(':');
  return (int.parse(p[0]), int.parse(p[1]));
}

String hm(int h, int m) => '${_two(h)}:${_two(m)}';

String fmtDate(DateTime d) => DateFormat('dd/MM/yyyy', 'pt_BR').format(d);
String fmtTime(DateTime d) => DateFormat('HH:mm', 'pt_BR').format(d);
String fmtDateTime(DateTime d) => DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(d);
String fmtLongDate(DateTime d) {
  final s = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

String fmtWeekdayShort(DateTime d) {
  const n = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
  return n[d.weekday - 1];
}

const weekdayNames = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];
const weekdayLetters = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];

/// Quantidade sem casas decimais desnecessárias, com vírgula decimal.
String fmtQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll('.', ',');
}

double? parseQty(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

String fmtDuration(Duration d) {
  final neg = d.isNegative;
  final a = d.abs();
  String out;
  if (a.inMinutes < 1) {
    out = 'menos de 1 min';
  } else if (a.inHours < 1) {
    out = '${a.inMinutes} min';
  } else if (a.inDays < 1) {
    final m = a.inMinutes % 60;
    out = m == 0 ? '${a.inHours} h' : '${a.inHours} h ${m} min';
  } else {
    out = '${a.inDays} ${a.inDays == 1 ? 'dia' : 'dias'}';
  }
  return neg ? 'há $out' : 'em $out';
}

String greeting(DateTime now) {
  if (now.hour < 12) return 'Bom dia';
  if (now.hour < 18) return 'Boa tarde';
  return 'Boa noite';
}
