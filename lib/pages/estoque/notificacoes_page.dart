import 'package:flutter/material.dart';

import '../../data/dados.dart';
import '../../models/produto.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/foto_produto.dart';
import '../../widgets/largura_maxima.dart';
import '../shell/app_shell.dart';
import 'estoque_widgets.dart';

/// Notificações de estoque: itens zerados e itens no mínimo.
class NotificacoesPage extends StatelessWidget {
  const NotificacoesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<List<Produto>>(
        valueListenable: Dados.produtos,
        builder: (context, todos, _) {
          int porNome(Produto a, Produto b) =>
              a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
          final ativos = todos.where((p) => p.ativo);
          final zerados = ativos.where((p) => p.estoque <= 0).toList()
            ..sort(porNome);
          final baixos =
              ativos
                  .where((p) => p.estoque > 0 && p.estoque <= p.estoqueMinimo)
                  .toList()
                ..sort((a, b) {
                  final c = a.estoque.compareTo(b.estoque);
                  return c != 0 ? c : porNome(a, b);
                });
          final lista = [...zerados, ...baixos];
          final t = Theme.of(context).textTheme;

          return LarguraMaxima(
            largura: 900,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Sinal(
                        titulo: 'ITENS ZERADOS',
                        valor: zerados.length,
                        descricao: 'Produtos ativos sem saldo',
                        icone: Icons.remove_shopping_cart_outlined,
                        cor: Colors.red.shade700,
                        onTap: () => AppShell.abrir(
                          context,
                          'estoque',
                          argumento: 'zerados',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Sinal(
                        titulo: 'ESTOQUE BAIXO',
                        valor: baixos.length,
                        descricao: 'No mínimo ou abaixo dele',
                        icone: Icons.trending_down,
                        cor: Colors.orange.shade800,
                        onTap: () => AppShell.abrir(
                          context,
                          'estoque',
                          argumento: 'baixo',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Reposição necessária', style: t.titleLarge),
                Text('${lista.length} notificações ativas', style: t.bodySmall),
                const SizedBox(height: 8),
                if (lista.isEmpty)
                  const EstadoVazio(
                    icone: Icons.check_circle_outline,
                    titulo: 'Estoque em dia',
                    mensagem:
                        'Nenhum produto ativo está zerado ou abaixo do mínimo.',
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final (i, p) in lista.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            leading: FotoProduto(nome: p.nome),
                            title: Text(p.nome),
                            subtitle: Text(
                              [
                                if (p.codigo.isNotEmpty) p.codigo,
                                'mínimo ${p.estoqueMinimo}',
                              ].join(' · '),
                            ),
                            trailing: p.estoque <= 0
                                ? Selo('Zerado', cor: Colors.red.shade700)
                                : Selo(
                                    '${p.estoque} restantes',
                                    cor: Colors.orange.shade800,
                                  ),
                            onTap: () => AppShell.abrir(
                              context,
                              'estoque',
                              argumento: p.estoque <= 0 ? 'zerados' : 'baixo',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Sinal extends StatelessWidget {
  final String titulo;
  final int valor;
  final String descricao;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  const _Sinal({
    required this.titulo,
    required this.valor,
    required this.descricao,
    required this.icone,
    required this.cor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icone, color: cor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titulo,
                      style: t.labelMedium?.copyWith(
                        color: cor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$valor',
                style: t.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(descricao, style: t.bodySmall),
              const SizedBox(height: 4),
              Text(
                'Ver produtos →',
                style: t.labelMedium?.copyWith(color: cor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
