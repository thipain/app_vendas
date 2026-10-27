import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/sessao.dart';
import '../../data/dados.dart';
import '../../data/retirada_repository.dart';
import '../../models/retirada.dart';
import '../../models/usuario.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/pendente_icon.dart';
import '../inicio/comum.dart';
import '../relatorios/pdf_relatorio.dart';
import 'nova_retirada_page.dart';

/// Consumo de produtos pelos funcionários: baixa o estoque sem mexer no caixa.
/// Funcionários veem só as próprias retiradas; o administrador vê todas,
/// escolhe o funcionário, vê custos, cancela e imprime o relatório.
class RetiradasPage extends StatefulWidget {
  const RetiradasPage({super.key});

  @override
  State<RetiradasPage> createState() => _RetiradasPageState();
}

/// Resumo de um funcionário no mês (somente retiradas ativas).
class _Resumo {
  final String nome;
  int retiradas = 0;
  int unidades = 0;
  double custo = 0;
  double venda = 0;
  _Resumo(this.nome);
}

class _RetiradasPageState extends State<RetiradasPage> {
  final _repo = RetiradaRepository();
  late DateTime _mes;
  late Stream<List<Retirada>> _stream;
  String? _funcionarioId;

  bool get _admin => Sessao.instancia.isAdmin;

  @override
  void initState() {
    super.initState();
    final h = DateTime.now();
    _definirMes(DateTime(h.year, h.month));
  }

  void _definirMes(DateTime mes) {
    _mes = mes;
    final p = Periodo.mes(mes.year, mes.month);
    _stream = _repo.watchPeriodo(p.inicio, p.fim);
  }

  void _mudarMes(int delta) =>
      setState(() => _definirMes(DateTime(_mes.year, _mes.month + delta)));

  List<Retirada> _filtrar(List<Retirada> todas) {
    final uid = _admin ? _funcionarioId : Sessao.instancia.atual.id;
    if (uid == null) return todas;
    return todas.where((r) => r.funcionarioId == uid).toList();
  }

  List<_Resumo> _resumo(List<Retirada> ativas) {
    final mapa = <String, _Resumo>{};
    for (final r in ativas) {
      final s = mapa.putIfAbsent(
        r.funcionarioId,
        () => _Resumo(r.funcionarioNome),
      );
      s.retiradas++;
      s.unidades += r.unidades;
      s.custo += r.totalCusto;
      s.venda += r.totalVenda;
    }
    return mapa.values.toList()..sort((a, b) => b.venda.compareTo(a.venda));
  }

  Future<void> _nova() async {
    final codigo = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const NovaRetiradaPage()));
    if (codigo != null && mounted) {
      avisar(
        context,
        'Retirada #$codigo registrada no nome do funcionário e baixada do estoque.',
      );
    }
  }

  Future<void> _cancelar(Retirada r) async {
    final motivo = await pedirTexto(
      context,
      titulo: 'Cancelar retirada #${r.codigo}',
      rotulo: 'Motivo do cancelamento',
      confirmar: 'Cancelar e devolver ao estoque',
      minimo: 5,
      ajuda: 'Os produtos voltam para o estoque.',
    );
    if (motivo == null || !mounted) return;
    executar(
      context,
      () => _repo.cancelar(r, motivo, Dados.produtosPorId),
      sucesso: 'Retirada cancelada e produtos devolvidos ao estoque.',
    );
  }

  String get _nomeFiltro {
    if (!_admin) return Sessao.instancia.atual.nome;
    if (_funcionarioId == null) return 'Todos os funcionários';
    return Dados.equipe.value
            .where((u) => u.id == _funcionarioId)
            .firstOrNull
            ?.nome ??
        'Funcionário';
  }

  Future<void> _imprimir(List<Retirada> lista) async {
    final ativas = lista.where((r) => r.isAtiva).toList();
    final resumo = _resumo(ativas);
    final f = DateFormat('dd/MM/yyyy HH:mm');
    try {
      await imprimirRelatorio(
        titulo: 'Retiradas de funcionários',
        subtitulo: '${nomeMesAno(_mes)} - $_nomeFiltro',
        conteudo: () => [
          pdfIndicadores([
            ('Retiradas', '${ativas.length}'),
            ('Unidades', '${ativas.fold<int>(0, (s, r) => s + r.unidades)}'),
            (
              'Custo para a adega',
              formatarMoeda(ativas.fold<double>(0, (s, r) => s + r.totalCusto)),
            ),
            (
              'Valor pelo preço de venda',
              formatarMoeda(ativas.fold<double>(0, (s, r) => s + r.totalVenda)),
            ),
          ]),
          pdfTituloSecao('Resumo por funcionário'),
          pdfTabela(
            ['Funcionário', 'Retiradas', 'Itens', 'Custo', 'Preço de venda'],
            [
              for (final s in resumo)
                [
                  s.nome,
                  '${s.retiradas}',
                  '${s.unidades}',
                  formatarMoeda(s.custo),
                  formatarMoeda(s.venda),
                ],
            ],
            direita: {1, 2, 3, 4},
          ),
          pdfTituloSecao('Retiradas do mês'),
          pdfTabela(
            [
              '#',
              'Data',
              'Funcionário',
              'Produtos',
              'Custo',
              'Venda',
              'Status',
            ],
            [
              for (final r in lista.take(100))
                [
                  r.codigo,
                  f.format(r.data),
                  r.funcionarioNome,
                  r.itens
                      .map((i) => '${i.quantidade}x ${i.produtoNome}')
                      .join(', '),
                  formatarMoeda(r.totalCusto),
                  formatarMoeda(r.totalVenda),
                  r.isAtiva ? 'Ativa' : 'Cancelada',
                ],
            ],
            direita: {4, 5},
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nova,
        icon: const Icon(Icons.add),
        label: const Text('Nova retirada'),
      ),
      body: StreamBuilder<List<Retirada>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return EstadoVazio(
              icone: Icons.error_outline,
              titulo: 'Não foi possível carregar as retiradas',
              mensagem: '${snap.error}',
            );
          }
          final lista = _filtrar(snap.data ?? const []);
          final ativas = lista.where((r) => r.isAtiva).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              LarguraMaxima(
                largura: 1000,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Aviso(),
                    const SizedBox(height: 12),
                    _filtros(lista),
                    const SizedBox(height: 12),
                    if (!snap.hasData)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      _indicadores(ativas),
                      if (_admin) ..._secaoResumo(ativas),
                      const TituloSecao('Histórico do mês'),
                      if (lista.isEmpty)
                        const EstadoVazio(
                          icone: Icons.local_drink_outlined,
                          titulo: 'Nenhuma retirada neste mês',
                        )
                      else
                        for (final r in lista.take(100))
                          _CartaoRetirada(
                            retirada: r,
                            admin: _admin,
                            onCancelar: () => _cancelar(r),
                          ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filtros(List<Retirada> lista) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Mês de referência',
            isDense: true,
            contentPadding: EdgeInsets.fromLTRB(4, 8, 4, 4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Mês anterior',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _mudarMes(-1),
              ),
              SizedBox(
                width: 150,
                child: Text(nomeMesAno(_mes), textAlign: TextAlign.center),
              ),
              IconButton(
                tooltip: 'Próximo mês',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _mudarMes(1),
              ),
            ],
          ),
        ),
        if (_admin) ...[
          ValueListenableBuilder<List<Usuario>>(
            valueListenable: Dados.equipe,
            builder: (context, equipe, _) {
              final ativos = equipe.where((u) => u.ativo).toList();
              final valor = ativos.any((u) => u.id == _funcionarioId)
                  ? _funcionarioId
                  : null;
              return SizedBox(
                width: 280,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(valor),
                  initialValue: valor,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Funcionário',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Todos os funcionários'),
                    ),
                    for (final u in ativos)
                      DropdownMenuItem(
                        value: u.id,
                        child: Text(u.nome, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _funcionarioId = v),
                ),
              );
            },
          ),
          if (_funcionarioId != null)
            TextButton(
              onPressed: () => setState(() => _funcionarioId = null),
              child: const Text('Limpar funcionário'),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir relatório'),
            onPressed: () => _imprimir(lista),
          ),
        ],
      ],
    );
  }

  Widget _indicadores(List<Retirada> ativas) {
    final unidades = ativas.fold<int>(0, (s, r) => s + r.unidades);
    return GradeKpi(
      children: [
        KpiCard(
          titulo: 'Retiradas em ${nomeMesAno(_mes)}',
          valor: '${ativas.length}',
          subtitulo: '$unidades unidade(s) consumida(s)',
          icone: Icons.local_drink_outlined,
        ),
        if (_admin)
          KpiCard(
            titulo: 'Custo para a adega',
            valor: formatarMoeda(
              ativas.fold<double>(0, (s, r) => s + r.totalCusto),
            ),
            icone: Icons.inventory_2_outlined,
          ),
        KpiCard(
          titulo: 'Valor pelo preço de venda',
          valor: formatarMoeda(
            ativas.fold<double>(0, (s, r) => s + r.totalVenda),
          ),
          icone: Icons.sell_outlined,
        ),
      ],
    );
  }

  List<Widget> _secaoResumo(List<Retirada> ativas) {
    final resumo = _resumo(ativas);
    return [
      const TituloSecao('Resumo por funcionário'),
      Card(
        margin: EdgeInsets.zero,
        child: resumo.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nenhuma retirada ativa no mês.'),
              )
            : Column(
                children: [
                  for (final s in resumo)
                    ListTile(
                      leading: CircleAvatar(child: Text(iniciais(s.nome))),
                      title: Text(s.nome),
                      subtitle: Text(
                        '${s.retiradas} retirada(s) · ${s.unidades} item(ns) · custo ${formatarMoeda(s.custo)}',
                      ),
                      trailing: Text(
                        formatarMoeda(s.venda),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
      ),
    ];
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: c.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.info_outline, color: c.onTertiaryContainer),
        title: Text(
          'Retirada não é venda',
          style: TextStyle(
            color: c.onTertiaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'O consumo fica registrado no nome do funcionário e o estoque é '
          'baixado, mas o caixa não é movimentado.',
          style: TextStyle(color: c.onTertiaryContainer),
        ),
      ),
    );
  }
}

class _CartaoRetirada extends StatelessWidget {
  final Retirada retirada;
  final bool admin;
  final VoidCallback onCancelar;

  const _CartaoRetirada({
    required this.retirada,
    required this.admin,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final r = retirada;
    final t = Theme.of(context);
    final f = DateFormat('dd/MM/yyyy HH:mm');
    final obs = r.observacao.isEmpty ? '' : ' · ${r.observacao}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '#${r.codigo} · ${r.funcionarioNome}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PendenteIcon(pendente: r.pendente),
          ],
        ),
        subtitle: Text(
          '${f.format(r.data)} · ${r.itens.length} produto(s)$obs',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatarMoeda(r.totalVenda),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                decoration: r.isAtiva ? null : TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(height: 4),
            Selo(r.isAtiva ? 'Ativa' : 'Cancelada', positivo: r.isAtiva),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 20,
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columns: [
                const DataColumn(label: Text('Produto')),
                const DataColumn(label: Text('Quantidade'), numeric: true),
                if (admin)
                  const DataColumn(label: Text('Custo un.'), numeric: true),
                const DataColumn(label: Text('Venda un.'), numeric: true),
                const DataColumn(label: Text('Total venda'), numeric: true),
              ],
              rows: [
                for (final i in r.itens)
                  DataRow(
                    cells: [
                      DataCell(Text(i.produtoNome)),
                      DataCell(Text('${i.quantidade}')),
                      if (admin) DataCell(Text(formatarMoeda(i.custoUnitario))),
                      DataCell(Text(formatarMoeda(i.precoUnitario))),
                      DataCell(Text(formatarMoeda(i.totalVenda))),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (r.observacao.isNotEmpty) Text('Observação: ${r.observacao}'),
          Text(
            'Registrada por ${r.registradoPorNome}',
            style: t.textTheme.bodySmall,
          ),
          if (admin)
            Text(
              'Custo total: ${formatarMoeda(r.totalCusto)}',
              style: t.textTheme.bodySmall,
            ),
          if (!r.isAtiva) ...[
            const SizedBox(height: 8),
            Text(
              'Cancelada por ${r.canceladaPorNome ?? '-'}'
              '${r.canceladaEm == null ? '' : ' em ${f.format(r.canceladaEm!)}'}',
              style: TextStyle(color: t.colorScheme.error),
            ),
            if ((r.motivoCancelamento ?? '').isNotEmpty)
              Text('Motivo: ${r.motivoCancelamento}'),
          ] else if (admin) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.colorScheme.error,
                ),
                icon: const Icon(Icons.undo),
                label: const Text('Cancelar e devolver ao estoque'),
                onPressed: onCancelar,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
