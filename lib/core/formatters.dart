import 'package:intl/intl.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _dataHora = DateFormat('dd/MM/yyyy HH:mm');

String formatarMoeda(num valor) => _moeda.format(valor);

String formatarDataHora(DateTime data) => _dataHora.format(data);

/// Converte "1.234,56" ou "1234.56" em double.
double? lerValor(String texto) {
  var t = texto.trim().replaceAll(r'R$', '').replaceAll(' ', '');
  if (t.isEmpty) return null;
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t);
}

/// Exibe um double no formato usado nos campos de texto ("1234,56").
String valorParaCampo(double valor) =>
    valor.toStringAsFixed(2).replaceAll('.', ',');
