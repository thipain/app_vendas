import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/sistema_repository.dart';
import '../../models/loja.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../inicio/comum.dart';
import 'admin_comum.dart';

/// Visão geral do negócio: situação das lojas e receita das mensalidades.
class VisaoGeralPage extends StatefulWidget {
  final ValueChanged<String> onEntrarLoja;

  const VisaoGeralPage({super.key, required this.onEntrarLoja});

  @override
  State<VisaoGeralPage> createState() => _VisaoGeralPageState();
}

class _VisaoGeralPageState extends State<VisaoGeralPage> {
  final _repo = SistemaRepository();
  late final Stream<List<Loja>> _lojas = _repo.watchLojas();
  late final Periodo _mes = Periodo.mes(
    DateTime.now().year,
    DateTime.now().month,
  );
  late final Stream<List<PagamentoLoja>> _pagamentos = _repo.watchPagamentos(
    _mes.inicio,
    _mes.fim,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Loja>>(
        stream: _lojas,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _conteudo(context, snap.data!);
        },
      ),
    );
  }

  Widget _conteudo(BuildContext context, List<Loja> lojas) {
    final agora = DateTime.now();
    final sit = {for (final l in lojas) l.id: l.situacao(agora)};
    int conta(bool Function(SituacaoLoja s) f) =>
        lojas.where((l) => f(sit[l.id]!)).length;

    final ativas = conta((s) => !s.travada);
    final emDia = conta((s) => s == SituacaoLoja.emDia);
    final vencendo = conta((s) => s == SituacaoLoja.vencendo);
    final atrasadas = conta((s) => s == SituacaoLoja.atrasada);
    final travadas = conta((s) => s.travada);
    final emTeste = conta((s) => s == SituacaoLoja.emTeste);
    final previstas = lojas.where(
      (l) =>
          sit[l.id] != SituacaoLoja.travadaManual &&
          l.pagoAte != null &&
          !l.emTeste,
    );
    final receitaPrevista = previstas.fold<double>(
      0,
      (s, l) => s + l.valorMensal,
    );

    final proximas = lojas.where((l) {
      final s = sit[l.id]!;
      final d = l.diasParaVencer(agora);
      return (s == SituacaoLoja.vencendo || s == SituacaoLoja.emTeste) &&
          d != null &&
          d < Loja.diasAviso;
    }).toList()..sort((a, b) => a.pagoAte!.compareTo(b.pagoAte!));
    final inadimplentes =
        lojas
            .where(
              (l) =>
                  sit[l.id] == SituacaoLoja.atrasada ||
                  sit[l.id] == SituacaoLoja.travadaPagamento,
            )
            .toList()
          ..sort((a, b) => a.pagoAte!.compareTo(b.pagoAte!));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        LarguraMaxima(
          largura: 1100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                dataPorExtenso(agora),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TituloSecao('Lojas (${lojas.length})'),
              GradeKpi(
                larguraMinima: 200,
                children: [
                  KpiCard(
                    titulo: 'Ativas',
                    valor: '$ativas',
                    subtitulo: 'com acesso liberado',
                    icone: Icons.storefront,
                  ),
                  KpiCard(
                    titulo: 'Em dia',
                    valor: '$emDia',
                    icone: Icons.check_circle_outline,
                    cor: Colors.green.shade700,
                  ),
                  KpiCard(
                    titulo: 'Vencendo',
                    valor: '$vencendo',
                    subtitulo: 'em menos de ${Loja.diasAviso} dias',
                    icone: Icons.schedule,
                    cor: Colors.amber.shade800,
                  ),
                  KpiCard(
                    titulo: 'Atrasadas',
                    valor: '$atrasadas',
                    subtitulo: 'em carência',
                    icone: Icons.warning_amber,
                    cor: Colors.amber.shade800,
                  ),
                  KpiCard(
                    titulo: 'Travadas',
                    valor: '$travadas',
                    icone: Icons.lock_outline,
                    cor: Theme.of(context).colorScheme.error,
                  ),
                  KpiCard(
                    titulo: 'Em teste',
                    valor: '$emTeste',
                    subtitulo: 'teste grátis',
                    icone: Icons.hourglass_top,
                    cor: Colors.green.shade700,
                  ),
                ],
              ),
              TituloSecao('Receita · ${nomeMesAno(agora)}'),
              StreamBuilder<List<PagamentoLoja>>(
                stream: _pagamentos,
                builder: (context, p) {
                  final pags = p.data ?? const <PagamentoLoja>[];
                  final recebido = pags.fold<double>(0, (s, x) => s + x.valor);
                  return GradeKpi(
                    larguraMinima: 280,
                    children: [
                      KpiCard(
                        titulo: 'Receita mensal prevista',
                        valor: formatarMoeda(receitaPrevista),
                        subtitulo: '${previstas.length} loja(s) pagante(s)',
                        icone: Icons.trending_up,
                      ),
                      KpiCard(
                        titulo: 'Recebido no mês',
                        valor: p.hasError
                            ? '—'
                            : !p.hasData
                            ? '...'
                            : formatarMoeda(recebido),
                        subtitulo: p.hasError
                            ? 'Erro: ${p.error}'
                            : '${pags.length} pagamento(s)',
                        icone: Icons.payments_outlined,
                        cor: Colors.green.shade700,
                      ),
                    ],
                  );
                },
              ),
              TituloSecao(
                'Vencendo nos próximos ${Loja.diasAviso} dias (${proximas.length})',
              ),
              if (proximas.isEmpty)
                const _Vazio('Nenhuma loja vencendo nos próximos dias.')
              else
                _ListaLojas(proximas, widget.onEntrarLoja),
              TituloSecao(
                'Atrasadas / travadas por pagamento (${inadimplentes.length})',
              ),
              if (inadimplentes.isEmpty)
                const _Vazio('Nenhuma loja com pagamento atrasado.')
              else
                _ListaLojas(inadimplentes, widget.onEntrarLoja),
            ],
          ),
        ),
      ],
    );
  }
}

class _Vazio extends StatelessWidget {
  final String texto;

  const _Vazio(this.texto);

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.thumb_up_alt_outlined),
      title: Text(texto),
    ),
  );
}

/// Lista de lojas com situação e ações rápidas de cobrança.
class _ListaLojas extends StatelessWidget {
  final List<Loja> lojas;
  final ValueChanged<String> onEntrarLoja;

  const _ListaLojas(this.lojas, this.onEntrarLoja);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (final l in lojas) ...[
            if (l != lojas.first) const Divider(height: 1),
            ListTileLojaCobranca(loja: l, onEntrarLoja: onEntrarLoja),
          ],
        ],
      ),
    );
  }
}
