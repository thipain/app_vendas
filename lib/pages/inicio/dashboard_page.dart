import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/permissoes.dart';
import '../../core/sessao.dart';
import '../../data/comanda_repository.dart';
import '../../data/dados.dart';
import '../../data/venda_repository.dart';
import '../../models/comanda.dart';
import '../../models/produto.dart';
import '../../models/venda.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/foto_produto.dart';
import '../../widgets/largura_maxima.dart';
import '../shell/app_shell.dart';
import 'comum.dart';

/// Visão geral: vendas do dia, comandas abertas, alertas de estoque e atalhos.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final Stream<List<Venda>> _vendasHoje;
  late final Stream<List<Comanda>> _comandas;

  @override
  void initState() {
    super.initState();
    final hoje = Periodo.hoje();
    _vendasHoje = VendaRepository().watchPeriodo(hoje.inicio, hoje.fim);
    _comandas = ComandaRepository().watchAbertas();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final eu = Sessao.instancia.atual;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LarguraMaxima(
            largura: 1100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Olá, ${primeiroNome(eu.nome)}.',
                          style: t.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          dataPorExtenso(DateTime.now()),
                          style: t.textTheme.bodyMedium?.copyWith(
                            color: t.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Nova venda'),
                      onPressed: () => AppShell.abrir(context, 'vendas'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GradeKpi(
                  children: [
                    StreamBuilder<List<Venda>>(
                      stream: _vendasHoje,
                      builder: (context, s) {
                        final concluidas = (s.data ?? const <Venda>[])
                            .where((v) => v.status == Venda.concluida)
                            .toList();
                        final total = concluidas.fold<double>(
                          0,
                          (a, v) => a + v.total,
                        );
                        return KpiCard(
                          titulo: 'Vendas de hoje',
                          valor: s.hasData ? formatarMoeda(total) : '...',
                          subtitulo: '${concluidas.length} pedidos concluídos',
                          icone: Icons.payments_outlined,
                        );
                      },
                    ),
                    StreamBuilder<List<Comanda>>(
                      stream: _comandas,
                      builder: (context, s) => KpiCard(
                        titulo: 'Comandas abertas',
                        valor: s.hasData ? '${s.data!.length}' : '...',
                        subtitulo: 'em consumo agora',
                        icone: Icons.receipt_long_outlined,
                      ),
                    ),
                    ValueListenableBuilder<List<Produto>>(
                      valueListenable: Dados.produtos,
                      builder: (context, _, _) => KpiCard(
                        titulo: 'Itens em alerta',
                        valor: '${Dados.produtosEmAlerta.length}',
                        subtitulo: 'estoque no mínimo ou abaixo',
                        icone: Icons.warning_amber_rounded,
                        cor: t.colorScheme.error,
                      ),
                    ),
                  ],
                ),
                LayoutBuilder(
                  builder: (context, c) {
                    const reposicao = _Reposicao();
                    const atalhos = _AcessoRapido();
                    if (c.maxWidth < 860) {
                      return const Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [reposicao, atalhos],
                      );
                    }
                    return const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: reposicao),
                        SizedBox(width: 16),
                        Expanded(flex: 2, child: atalhos),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Reposicao extends StatelessWidget {
  const _Reposicao();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloSecao(
          'Reposição necessária',
          acao: Sessao.instancia.pode(Permissao.estoque)
              ? TextButton(
                  onPressed: () => AppShell.abrir(context, 'estoque'),
                  child: const Text('Ver estoque →'),
                )
              : null,
        ),
        Card(
          margin: EdgeInsets.zero,
          child: ValueListenableBuilder<List<Produto>>(
            valueListenable: Dados.produtos,
            builder: (context, _, _) {
              final lista = Dados.produtosEmAlerta.take(8).toList();
              if (lista.isEmpty) {
                return const EstadoVazio(
                  icone: Icons.check_circle_outline,
                  titulo: 'Estoque em dia',
                );
              }
              return Column(
                children: [
                  for (final p in lista)
                    ListTile(
                      leading: FotoProduto(
                        nome: p.nome,
                        tamanho: 40,
                      ),
                      title: Text(p.nome),
                      subtitle: Text(
                        '${p.codigo.isEmpty ? 'Sem SKU' : p.codigo} · mínimo ${p.estoqueMinimo}',
                      ),
                      trailing: Text(
                        '${p.estoque} un.',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: p.zerado
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AcessoRapido extends StatelessWidget {
  const _AcessoRapido();

  @override
  Widget build(BuildContext context) {
    final s = Sessao.instancia;
    final atalhos = <(String, IconData, String)>[
      ('Iniciar venda', Icons.shopping_cart_outlined, 'vendas'),
      if (s.pode(Permissao.comandas))
        ('Nova comanda', Icons.receipt_long_outlined, 'comandas'),
      ('Retirada da equipe', Icons.local_drink_outlined, 'retiradas'),
      if (s.pode(Permissao.transformacoes))
        ('Montar ou desmanchar', Icons.call_split, 'transformacoes'),
      if (s.pode(Permissao.calculadora))
        ('Calculadora', Icons.calculate_outlined, 'calculadora'),
      ('Meu ponto', Icons.fingerprint, 'meu_ponto'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloSecao('Acesso rápido'),
        GradeKpi(
          larguraMinima: 180,
          children: [
            for (final (rotulo, icone, modulo) in atalhos)
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => AppShell.abrir(context, modulo),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          icone,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(rotulo)),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
