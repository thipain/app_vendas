import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/sistema_repository.dart';
import '../../models/loja.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../inicio/comum.dart';
import 'admin_comum.dart';
import 'loja_detalhe_page.dart';

/// Pagamentos de mensalidade recebidos no período e lojas inadimplentes.
class MensalidadesPage extends StatefulWidget {
  final ValueChanged<String> onEntrarLoja;

  const MensalidadesPage({super.key, required this.onEntrarLoja});

  @override
  State<MensalidadesPage> createState() => _MensalidadesPageState();
}

class _MensalidadesPageState extends State<MensalidadesPage> {
  final _repo = SistemaRepository();
  late final Stream<List<Loja>> _lojas = _repo.watchLojas();
  // Termina hoje: o seletor de datas não aceita datas futuras.
  Periodo _periodo = Periodo.mesAtual();
  late Stream<List<PagamentoLoja>> _pagamentos = _consultar();

  Stream<List<PagamentoLoja>> _consultar() =>
      _repo.watchPagamentos(_periodo.inicio, _periodo.fim);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Loja>>(
        stream: _lojas,
        builder: (context, lojasSnap) {
          final lojas = lojasSnap.data ?? const <Loja>[];
          final porId = {for (final l in lojas) l.id: l};
          final agora = DateTime.now();
          final inadimplentes = lojas.where((l) {
            final s = l.situacao(agora);
            return s == SituacaoLoja.atrasada ||
                s == SituacaoLoja.travadaPagamento;
          }).toList()..sort((a, b) => a.pagoAte!.compareTo(b.pagoAte!));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              LarguraMaxima(
                largura: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FiltroPeriodo(
                        periodo: _periodo,
                        onChanged: (p) => setState(() {
                          _periodo = p;
                          _pagamentos = _consultar();
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<List<PagamentoLoja>>(
                      stream: _pagamentos,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Text('Erro: ${snap.error}');
                        }
                        if (!snap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final pags = snap.data!;
                        final total = pags.fold<double>(
                          0,
                          (s, p) => s + p.valor,
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GradeKpi(
                              children: [
                                KpiCard(
                                  titulo: 'Total recebido',
                                  valor: formatarMoeda(total),
                                  subtitulo: _periodo.descricao,
                                  icone: Icons.payments_outlined,
                                  cor: Colors.green.shade700,
                                ),
                                KpiCard(
                                  titulo: 'Pagamentos',
                                  valor: '${pags.length}',
                                  subtitulo:
                                      '${pags.map((p) => p.lojaId).toSet().length} loja(s)',
                                  icone: Icons.receipt_long_outlined,
                                ),
                              ],
                            ),
                            TituloSecao('Pagamentos (${pags.length})'),
                            if (pags.isEmpty)
                              const EstadoVazio(
                                icone: Icons.receipt_long_outlined,
                                titulo: 'Nenhum pagamento no período',
                              )
                            else
                              Card(
                                margin: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    for (final p in pags) ...[
                                      if (p != pags.first)
                                        const Divider(height: 1),
                                      LinhaPagamento(
                                        p,
                                        onTap: porId[p.lojaId] == null
                                            ? null
                                            : () => abrirLoja(
                                                context,
                                                porId[p.lojaId]!,
                                                widget.onEntrarLoja,
                                              ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    TituloSecao('Inadimplentes (${inadimplentes.length})'),
                    if (lojasSnap.hasError)
                      Text('Erro: ${lojasSnap.error}')
                    else if (!lojasSnap.hasData)
                      const Center(child: CircularProgressIndicator())
                    else if (inadimplentes.isEmpty)
                      const Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: Icon(Icons.thumb_up_alt_outlined),
                          title: Text('Nenhuma loja com pagamento atrasado.'),
                        ),
                      )
                    else
                      Card(
                        margin: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (final l in inadimplentes) ...[
                              if (l != inadimplentes.first)
                                const Divider(height: 1),
                              ListTileLojaCobranca(
                                loja: l,
                                onEntrarLoja: widget.onEntrarLoja,
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
