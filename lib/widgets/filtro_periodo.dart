import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Intervalo de dias inteiros: [inicio] às 00:00 até o fim do dia [ultimoDia].
class Periodo {
  final DateTime inicio;
  final DateTime ultimoDia;

  Periodo(DateTime de, DateTime ate)
    : inicio = DateTime(de.year, de.month, de.day),
      ultimoDia = DateTime(ate.year, ate.month, ate.day);

  /// Fim exclusivo (00:00 do dia seguinte ao último), para as consultas.
  DateTime get fim => ultimoDia.add(const Duration(days: 1));

  factory Periodo.hoje() {
    final h = DateTime.now();
    return Periodo(h, h);
  }

  factory Periodo.mesAtual() {
    final h = DateTime.now();
    return Periodo(DateTime(h.year, h.month), h);
  }

  factory Periodo.mes(int ano, int mes) =>
      Periodo(DateTime(ano, mes), DateTime(ano, mes + 1, 0));

  bool contem(DateTime d) => !d.isBefore(inicio) && d.isBefore(fim);

  String get descricao {
    final f = DateFormat('dd/MM/yyyy');
    return inicio == ultimoDia
        ? f.format(inicio)
        : '${f.format(inicio)} a ${f.format(ultimoDia)}';
  }
}

/// Botão que mostra o período e abre o seletor de datas.
class FiltroPeriodo extends StatelessWidget {
  final Periodo periodo;
  final ValueChanged<Periodo> onChanged;

  const FiltroPeriodo({
    super.key,
    required this.periodo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.date_range),
      label: Text(periodo.descricao),
      onPressed: () async {
        final r = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          initialDateRange: DateTimeRange(
            start: periodo.inicio,
            end: periodo.ultimoDia,
          ),
        );
        if (r != null) onChanged(Periodo(r.start, r.end));
      },
    );
  }
}

/// Mensagem centralizada para listas vazias.
class EstadoVazio extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? mensagem;

  const EstadoVazio({
    super.key,
    required this.icone,
    required this.titulo,
    this.mensagem,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: t.colorScheme.outline),
            const SizedBox(height: 12),
            Text(titulo, style: t.textTheme.titleMedium),
            if (mensagem != null) ...[
              const SizedBox(height: 4),
              Text(mensagem!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
