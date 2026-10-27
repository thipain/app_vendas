import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/dados.dart';
import '../../data/estoque.dart';
import '../../models/movimento_estoque.dart';
import '../../models/produto.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/pendente_icon.dart';
import '../../widgets/seletor.dart';
import 'estoque_widgets.dart';

/// Histórico do estoque: toda alteração de saldo, somente leitura.
class MovimentacoesPage extends StatefulWidget {
  const MovimentacoesPage({super.key});

  @override
  State<MovimentacoesPage> createState() => _MovimentacoesPageState();
}

class _MovimentacoesPageState extends State<MovimentacoesPage> {
  static const _porPagina = 75;
  static final _formato = DateFormat('dd/MM/yyyy HH:mm:ss');

  Periodo _periodo = Periodo(
    DateTime.now().subtract(const Duration(days: 29)),
    DateTime.now(),
  );
  late Stream<List<MovimentoEstoque>> _stream = _abrir();
  Produto? _produto;
  String? _tipo;
  int _pagina = 0;

  Stream<List<MovimentoEstoque>> _abrir() =>
      Estoque.watchPeriodo(_periodo.inicio, _periodo.fim);

  Future<void> _escolherProduto() async {
    final p = await selecionarProduto(
      context,
      titulo: 'Filtrar por produto',
      incluirInativos: true,
    );
    if (p != null) {
      setState(() {
        _produto = p;
        _pagina = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LarguraMaxima(
        largura: 1000,
        child: StreamBuilder<List<MovimentoEstoque>>(
          stream: _stream,
          builder: (context, snap) {
            final filtros = _filtros();
            if (snap.hasError) {
              return ListView(
                children: [
                  filtros,
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Erro ao carregar: ${snap.error}'),
                  ),
                ],
              );
            }
            if (!snap.hasData) {
              return Column(
                children: [
                  filtros,
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              );
            }
            final lista = snap.data!
                .where(
                  (m) =>
                      (_produto == null || m.produtoId == _produto!.id) &&
                      (_tipo == null || m.tipo == _tipo),
                )
                .toList();
            final paginas = (lista.length / _porPagina).ceil();
            final pagina = paginas == 0 ? 0 : _pagina.clamp(0, paginas - 1);
            final itens = lista
                .skip(pagina * _porPagina)
                .take(_porPagina)
                .toList();
            final porId = Dados.produtosPorId;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: filtros),
                if (lista.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EstadoVazio(
                      icone: Icons.swap_vert,
                      titulo: 'Nenhuma movimentação encontrada',
                      mensagem: 'Altere os filtros ou o período.',
                    ),
                  )
                else ...[
                  SliverList.separated(
                    itemCount: itens.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _item(itens[i], porId),
                  ),
                  SliverToBoxAdapter(
                    child: Paginacao(
                      pagina: pagina,
                      totalPaginas: paginas,
                      registros: lista.length,
                      onChanged: (p) => setState(() => _pagina = p),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _produto == null
              ? OutlinedButton.icon(
                  onPressed: _escolherProduto,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Todos os produtos'),
                )
              : InputChip(
                  avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text(
                    [
                      _produto!.nome,
                      if (_produto!.codigo.isNotEmpty) _produto!.codigo,
                    ].join(' · '),
                  ),
                  onPressed: _escolherProduto,
                  onDeleted: () => setState(() {
                    _produto = null;
                    _pagina = 0;
                  }),
                ),
          DropdownButton<String?>(
            value: _tipo,
            hint: const Text('Todos os tipos'),
            onChanged: (v) => setState(() {
              _tipo = v;
              _pagina = 0;
            }),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Todos os tipos'),
              ),
              for (final e in MovimentoEstoque.nomes.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
          ),
          FiltroPeriodo(
            periodo: _periodo,
            onChanged: (p) => setState(() {
              _periodo = p;
              _pagina = 0;
              _stream = _abrir();
            }),
          ),
        ],
      ),
    );
  }

  Widget _item(MovimentoEstoque m, Map<String, Produto> porId) {
    final t = Theme.of(context).textTheme;
    final positivo = m.quantidade > 0;
    final cor = positivo ? Colors.green.shade700 : Colors.red.shade700;
    final codigo = porId[m.produtoId]?.codigo ?? '';
    final responsavel = m.usuarioNome.isEmpty ? 'Sistema' : m.usuarioNome;
    return ListTile(
      leading: SizedBox(
        width: 64,
        child: Text(
          '${positivo ? '+' : ''}${m.quantidade}',
          textAlign: TextAlign.center,
          style: t.titleMedium?.copyWith(
            color: cor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              codigo.isEmpty ? m.produtoNome : '${m.produtoNome} · $codigo',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          PendenteIcon(pendente: m.pendente),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: m.tipoNome,
                  style: TextStyle(color: cor, fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ' · Saldo ${m.estoqueAntes} → '),
                TextSpan(
                  text: '${m.estoqueDepois}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Text(
            [
              _formato.format(m.data),
              responsavel,
              if (m.motivo.isNotEmpty) m.motivo,
            ].join(' · '),
          ),
        ],
      ),
      isThreeLine: true,
    );
  }
}
