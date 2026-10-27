import 'package:flutter/material.dart';

/// Pequenos utilitários de texto e widgets compartilhados pelas telas de
/// painel, retiradas, relatórios e ponto.

const _meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

const _diasSemana = [
  'segunda-feira',
  'terça-feira',
  'quarta-feira',
  'quinta-feira',
  'sexta-feira',
  'sábado',
  'domingo',
];

String _maiuscula(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// "Outubro de 2026".
String nomeMesAno(DateTime d) =>
    '${_maiuscula(_meses[d.month - 1])} de ${d.year}';

/// "Terça-feira, 27 de outubro de 2026".
String dataPorExtenso(DateTime d) => _maiuscula(
  '${_diasSemana[d.weekday - 1]}, ${d.day} de ${_meses[d.month - 1]} de ${d.year}',
);

/// Duas primeiras letras do nome, em maiúsculas (avatar).
String iniciais(String nome) {
  final n = nome.trim();
  if (n.isEmpty) return '?';
  return (n.length >= 2 ? n.substring(0, 2) : n).toUpperCase();
}

String primeiroNome(String nome) {
  final n = nome.trim();
  if (n.isEmpty) return '';
  return n.split(RegExp(r'\s+')).first;
}

/// Indicador numérico (KPI) em cartão.
class KpiCard extends StatelessWidget {
  final String titulo;
  final String valor;
  final String? subtitulo;
  final IconData icone;
  final Color? cor;

  const KpiCard({
    super.key,
    required this.titulo,
    required this.valor,
    this.subtitulo,
    required this.icone,
    this.cor,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: (cor ?? t.colorScheme.primary).withValues(
                alpha: 0.12,
              ),
              foregroundColor: cor ?? t.colorScheme.primary,
              child: Icon(icone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: t.textTheme.labelLarge?.copyWith(
                      color: t.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      valor,
                      style: t.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (subtitulo != null)
                    Text(subtitulo!, style: t.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Distribui cartões em colunas conforme a largura disponível.
class GradeKpi extends StatelessWidget {
  final List<Widget> children;
  final double larguraMinima;

  const GradeKpi({super.key, required this.children, this.larguraMinima = 240});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const espaco = 12.0;
        var colunas = (c.maxWidth / larguraMinima).floor().clamp(
          1,
          children.length,
        );
        if (colunas < 1) colunas = 1;
        final largura = (c.maxWidth - espaco * (colunas - 1)) / colunas;
        return Wrap(
          spacing: espaco,
          runSpacing: espaco,
          children: [
            for (final w in children) SizedBox(width: largura, child: w),
          ],
        );
      },
    );
  }
}

/// Título de seção com ação opcional à direita.
class TituloSecao extends StatelessWidget {
  final String titulo;
  final Widget? acao;

  const TituloSecao(this.titulo, {super.key, this.acao});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?acao,
        ],
      ),
    );
  }
}

/// Selo colorido curto (ex.: Ativa / Cancelada).
class Selo extends StatelessWidget {
  final String texto;
  final bool positivo;

  const Selo(this.texto, {super.key, this.positivo = true});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final fundo = positivo ? c.primaryContainer : c.errorContainer;
    final frente = positivo ? c.onPrimaryContainer : c.onErrorContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: frente,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
