import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/venda_repository.dart';
import '../../models/venda.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../inicio/comum.dart';
import 'pdf_relatorio.dart';

/// Faturamento, custo, lucro e margem das vendas concluídas no período.
class RelatoriosPage extends StatefulWidget {
  const RelatoriosPage({super.key});

  @override
  State<RelatoriosPage> createState() => _RelatoriosPageState();
}

class _Forma {
  final String nome;
  double total = 0;
  int lancamentos = 0;
  _Forma(this.nome);
}

class _ProdutoLucro {
  final String nome;
  int quantidade = 0;
  double receita = 0;
  double custo = 0;
  double get lucro => receita - custo;
  _ProdutoLucro(this.nome);
}

/// Números do relatório, calculados a partir das vendas concluídas.
class _Resultado {
  final int vendas;
  final double liquido;
  final double custo;
  final double descontos;
  final List<_Forma> formas;
  final List<_ProdutoLucro> produtos;

  _Resultado._(
    this.vendas,
    this.liquido,
    this.custo,
    this.descontos,
    this.formas,
    this.produtos,
  );

  double get lucro => liquido - custo;
  double get margem => liquido > 0 ? lucro / liquido * 100 : 0;
  String get margemTexto =>
      '${margem.toStringAsFixed(1).replaceAll('.', ',')}%';

  factory _Resultado.de(List<Venda> todas) {
    final vendas = todas.where((v) => v.status == Venda.concluida).toList();
    var liquido = 0.0, custo = 0.0, descontos = 0.0;
    final formas = <String, _Forma>{};
    final produtos = <String, _ProdutoLucro>{};
    for (final v in vendas) {
      liquido += v.total;
      descontos += v.desconto;
      if (v.pagamentos.isEmpty) {
        // Vendas antigas, sem a lista de pagamentos: usa a forma única.
        final f = formas.putIfAbsent(
          v.formaPagamento.isEmpty ? 'Não informado' : v.formaPagamento,
          () => _Forma(
            v.formaPagamento.isEmpty ? 'Não informado' : v.formaPagamento,
          ),
        );
        f.total += v.total;
        f.lancamentos++;
      } else {
        for (final p in v.pagamentos) {
          final f = formas.putIfAbsent(p.forma, () => _Forma(p.forma));
          f.total += p.valor;
          f.lancamentos++;
        }
      }
      final fator = v.subtotal > 0 ? v.total / v.subtotal : 0.0;
      for (final i in v.itens) {
        custo += i.custoTotal;
        final p = produtos.putIfAbsent(i.nome, () => _ProdutoLucro(i.nome));
        p.quantidade += i.quantidade;
        p.receita += i.subtotal * fator;
        p.custo += i.custoTotal;
      }
    }
    return _Resultado._(
      vendas.length,
      liquido,
      custo,
      descontos,
      formas.values.toList()..sort((a, b) => b.total.compareTo(a.total)),
      (produtos.values.toList()..sort((a, b) => b.receita.compareTo(a.receita)))
          .take(12)
          .toList(),
    );
  }
}

class _RelatoriosPageState extends State<RelatoriosPage> {
  late Periodo _periodo;
  late Stream<List<Venda>> _stream;

  @override
  void initState() {
    super.initState();
    _definir(Periodo.mesAtual());
  }

  void _definir(Periodo p) {
    _periodo = p;
    _stream = VendaRepository().watchPeriodo(p.inicio, p.fim);
  }

  Future<void> _imprimir(_Resultado r) async {
    try {
      await imprimirRelatorio(
        titulo: 'Relatório de vendas e lucro',
        subtitulo: 'Período: ${_periodo.descricao}',
        conteudo: () => [
          pdfIndicadores([
            ('Faturamento líquido', formatarMoeda(r.liquido)),
            ('Vendas concluídas', '${r.vendas}'),
            ('Custo dos produtos', formatarMoeda(r.custo)),
          ]),
          pdfIndicadores([
            ('Lucro bruto estimado', formatarMoeda(r.lucro)),
            ('Margem bruta', r.margemTexto),
            ('Descontos', formatarMoeda(r.descontos)),
          ]),
          pdfTituloSecao('Por forma de pagamento'),
          pdfTabela(
            ['Forma', 'Lançamentos', 'Total'],
            [
              for (final f in r.formas)
                [f.nome, '${f.lancamentos}', formatarMoeda(f.total)],
            ],
            direita: {1, 2},
          ),
          pdfTituloSecao('Lucro por produto (12 maiores faturamentos)'),
          pdfTabela(
            ['Produto', 'Qtd.', 'Receita', 'Custo', 'Lucro'],
            [
              for (final p in r.produtos)
                [
                  p.nome,
                  '${p.quantidade}',
                  formatarMoeda(p.receita),
                  formatarMoeda(p.custo),
                  formatarMoeda(p.lucro),
                ],
            ],
            direita: {1, 2, 3, 4},
          ),
        ],
      );
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Venda>>(
        stream: _stream,
        builder: (context, s) {
          final r = s.hasData ? _Resultado.de(s.data!) : null;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LarguraMaxima(
                largura: 1100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FiltroPeriodo(
                          periodo: _periodo,
                          onChanged: (p) => setState(() => _definir(p)),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Imprimir'),
                          onPressed: r == null ? null : () => _imprimir(r),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Somente vendas concluídas entram no relatório.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    if (s.hasError)
                      EstadoVazio(
                        icone: Icons.error_outline,
                        titulo: 'Não foi possível carregar as vendas',
                        mensagem: '${s.error}',
                      )
                    else if (r == null)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      ..._conteudo(r),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _conteudo(_Resultado r) {
    final t = Theme.of(context);
    return [
      GradeKpi(
        larguraMinima: 200,
        children: [
          KpiCard(
            titulo: 'Faturamento líquido',
            valor: formatarMoeda(r.liquido),
            subtitulo: '${r.vendas} vendas concluídas',
            icone: Icons.payments_outlined,
          ),
          KpiCard(
            titulo: 'Custo dos produtos',
            valor: formatarMoeda(r.custo),
            subtitulo: 'custo registrado na venda',
            icone: Icons.inventory_2_outlined,
          ),
          KpiCard(
            titulo: 'Lucro bruto estimado',
            valor: formatarMoeda(r.lucro),
            subtitulo: 'faturamento − custo',
            icone: Icons.trending_up,
            cor: r.lucro < 0 ? t.colorScheme.error : null,
          ),
          KpiCard(
            titulo: 'Margem',
            valor: r.margemTexto,
            subtitulo: 'de margem bruta sobre vendas',
            icone: Icons.percent,
          ),
          KpiCard(
            titulo: 'Descontos',
            valor: formatarMoeda(r.descontos),
            subtitulo: 'concedidos no período',
            icone: Icons.discount_outlined,
          ),
        ],
      ),
      LayoutBuilder(
        builder: (context, c) {
          final formas = _formas(r);
          final produtos = _produtos(r);
          if (c.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [formas, produtos],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: formas),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: produtos),
            ],
          );
        },
      ),
    ];
  }

  Widget _formas(_Resultado r) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const TituloSecao('Por forma de pagamento'),
      Card(
        margin: EdgeInsets.zero,
        child: r.formas.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nenhuma venda no período.'),
              )
            : Column(
                children: [
                  for (final f in r.formas)
                    ListTile(
                      title: Text(f.nome),
                      subtitle: Text('${f.lancamentos} lançamentos'),
                      trailing: Text(
                        formatarMoeda(f.total),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
      ),
    ],
  );

  Widget _produtos(_Resultado r) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloSecao('Lucro por produto'),
        Card(
          margin: EdgeInsets.zero,
          child: r.produtos.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nenhum produto vendido no período.'),
                )
              : Column(
                  children: [
                    for (final p in r.produtos)
                      ListTile(
                        title: Text(p.nome),
                        subtitle: Text(
                          '${p.quantidade} un. · custo ${formatarMoeda(p.custo)}',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatarMoeda(p.lucro),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: p.lucro < 0
                                    ? t.colorScheme.error
                                    : Colors.green.shade700,
                              ),
                            ),
                            Text(
                              'receita ${formatarMoeda(p.receita)}',
                              style: t.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
