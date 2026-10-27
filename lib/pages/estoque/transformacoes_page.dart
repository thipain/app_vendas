import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/permissoes.dart';
import '../../core/sessao.dart';
import '../../data/dados.dart';
import '../../data/transformacao_repository.dart';
import '../../models/produto.dart';
import '../../models/transformacao.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/pendente_icon.dart';
import '../shell/app_shell.dart';
import 'estoque_widgets.dart';
import 'receita_form_page.dart';

/// Quantos lotes podem ser executados com o saldo atual dos insumos.
int lotesPossiveis(Receita r, Map<String, Produto> produtos) {
  if (r.entradas.isEmpty) return 0;
  var maximo = 1 << 30;
  for (final i in r.entradas) {
    final p = produtos[i.produtoId];
    if (p == null || i.quantidade <= 0) return 0;
    final n = p.estoque <= 0 ? 0 : p.estoque ~/ i.quantidade;
    if (n < maximo) maximo = n;
  }
  return maximo;
}

/// Montagem e desmanche: regras reutilizáveis que convertem produtos.
class TransformacoesPage extends StatefulWidget {
  const TransformacoesPage({super.key});

  @override
  State<TransformacoesPage> createState() => _TransformacoesPageState();
}

class _TransformacoesPageState extends State<TransformacoesPage> {
  static final _formato = DateFormat('dd/MM/yyyy HH:mm');

  final _repo = TransformacaoRepository();
  late final _receitas = _repo.watchReceitas();
  late final _operacoes = _repo.watchOperacoes(limite: 30);
  bool _ativas = true;

  void _abrirForm([Receita? receita]) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ReceitaFormPage(receita: receita)),
  );

  Future<void> _desativar(Receita r) async {
    final ok = await confirmar(
      context,
      titulo: 'Desativar operação',
      mensagem:
          'Desativar "${r.nome}"? Ela deixa de poder ser executada, '
          'mas pode ser reativada depois.',
      confirmarTexto: 'Desativar',
    );
    if (!ok || !mounted) return;
    executar(
      context,
      () => _repo.definirAtivo(r, false),
      sucesso: 'Operação desativada.',
    );
  }

  void _reativar(Receita r) => executar(
    context,
    () => _repo.definirAtivo(r, true),
    sucesso: 'Operação reativada.',
  );

  Future<void> _executar(Receita r) async {
    final maximo = lotesPossiveis(r, Dados.produtosPorId);
    if (maximo <= 0) return;
    final resultado = await showDialog<(int, String)>(
      context: context,
      builder: (_) => _ExecutarDialog(receita: r, maximo: maximo),
    );
    if (resultado == null || !mounted) return;
    final (lotes, obs) = resultado;
    executar(
      context,
      () => _repo.executar(r, lotes, obs, Dados.produtosPorId),
      sucesso:
          '${r.nome} executada em $lotes lote(s). Todos os saldos foram atualizados.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= larguraDesktop;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirForm,
        icon: const Icon(Icons.add),
        label: const Text('Nova operação'),
      ),
      body: ValueListenableBuilder<List<Produto>>(
        valueListenable: Dados.produtos,
        builder: (context, _, _) => StreamBuilder<List<Receita>>(
          stream: _receitas,
          builder: (context, snap) {
            final produtos = Dados.produtosPorId;
            final receitas =
                (snap.data ?? const <Receita>[])
                    .where((r) => r.ativo == _ativas)
                    .toList()
                  ..sort((a, b) {
                    final c = a.tipo.compareTo(b.tipo);
                    return c != 0
                        ? c
                        : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
                  });
            return LarguraMaxima(
              largura: 1200,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: [
                  _explicacao(),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Ativas')),
                        ButtonSegment(value: false, label: Text('Desativadas')),
                      ],
                      selected: {_ativas},
                      onSelectionChanged: (s) =>
                          setState(() => _ativas = s.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (snap.hasError)
                    Text('Erro ao carregar: ${snap.error}')
                  else if (!snap.hasData)
                    const Center(child: CircularProgressIndicator())
                  else if (receitas.isEmpty)
                    EstadoVazio(
                      icone: Icons.call_split,
                      titulo: _ativas
                          ? 'Nenhuma operação ativa'
                          : 'Nenhuma operação desativada',
                      mensagem: _ativas
                          ? 'Crie uma regra de montagem ou desmanche para converter produtos no estoque.'
                          : null,
                    )
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final r in receitas)
                          SizedBox(
                            width: desktop ? 372 : double.infinity,
                            child: _card(r, produtos),
                          ),
                      ],
                    ),
                  const SizedBox(height: 24),
                  _execucoes(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _explicacao() {
    final t = Theme.of(context).textTheme;
    final cores = Theme.of(context).colorScheme;
    Widget bloco(IconData icone, String titulo, String texto) => Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cores.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: t.titleSmall?.copyWith(
                    color: cores.onSecondaryContainer,
                  ),
                ),
                Text(
                  texto,
                  style: t.bodySmall?.copyWith(
                    color: cores.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cores.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bloco(
            Icons.call_merge,
            'Montagem',
            'Vários itens geram exatamente 1 produto final (ex.: gelo + dose + energético → copo).',
          ),
          const SizedBox(width: 12),
          bloco(
            Icons.call_split,
            'Desmanche',
            'Exatamente 1 item agrupado gera um ou vários itens (ex.: fardo → unidades).',
          ),
        ],
      ),
    );
  }

  Widget _card(Receita r, Map<String, Produto> produtos) {
    final t = Theme.of(context).textTheme;
    final lotes = lotesPossiveis(r, produtos);
    Widget lista(String titulo, List<ItemReceita> itens) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: t.labelSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        for (final i in itens)
          Text(
            '${i.quantidade}× ${produtos[i.produtoId]?.nome ?? i.produtoNome} '
            '(saldo ${produtos[i.produtoId]?.estoque ?? 0})',
          ),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.nome,
                    style: t.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PendenteIcon(pendente: r.pendente),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Selo(
                  r.tipoNome,
                  cor: r.isComposicao ? Colors.indigo : Colors.teal.shade700,
                ),
                if (r.ativo)
                  lotes > 0
                      ? Selo(
                          '$lotes lote(s) possível(is)',
                          cor: Colors.green.shade700,
                        )
                      : Selo('Sem insumo suficiente', cor: Colors.red.shade700),
              ],
            ),
            const SizedBox(height: 10),
            lista('CONSOME', r.entradas),
            const SizedBox(height: 8),
            lista('GERA', r.saidas),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: r.ativo
                  ? [
                      FilledButton.icon(
                        onPressed: lotes > 0 ? () => _executar(r) : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Executar operação'),
                      ),
                      TextButton(
                        onPressed: () => _abrirForm(r),
                        child: const Text('Editar regra'),
                      ),
                      TextButton(
                        onPressed: () => _desativar(r),
                        child: const Text('Desativar'),
                      ),
                    ]
                  : [
                      FilledButton.tonal(
                        onPressed: () => _reativar(r),
                        child: const Text('Reativar operação'),
                      ),
                      TextButton(
                        onPressed: () => _abrirForm(r),
                        child: const Text('Editar regra'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _execucoes() {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Últimas execuções', style: t.titleLarge)),
            if (Sessao.instancia.pode(Permissao.movimentacoes))
              TextButton(
                onPressed: () => AppShell.abrir(context, 'movimentacoes'),
                child: const Text('Ver movimentações'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<OperacaoEstoque>>(
          stream: _operacoes,
          builder: (context, snap) {
            if (snap.hasError) return Text('Erro ao carregar: ${snap.error}');
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final ops = snap.data!;
            if (ops.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Nenhuma operação executada ainda.'),
              );
            }
            return Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, o) in ops.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      title: Row(
                        children: [
                          Flexible(child: Text(o.receitaNome)),
                          const SizedBox(width: 4),
                          PendenteIcon(pendente: o.pendente),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${o.tipoNome} · ${o.lotes} lote(s) · #${o.id.length > 8 ? o.id.substring(0, 8).toUpperCase() : o.id}',
                          ),
                          for (final it in o.itens)
                            Text(
                              '${it.direcao == 'entrada' ? '−' : '+'}${it.quantidade} ${it.produtoNome}',
                              style: TextStyle(
                                color: it.direcao == 'entrada'
                                    ? Colors.red.shade700
                                    : Colors.green.shade700,
                              ),
                            ),
                          if (o.observacao.isNotEmpty) Text(o.observacao),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_formato.format(o.data), style: t.bodySmall),
                          Text(
                            o.usuarioNome.isEmpty ? 'Sistema' : o.usuarioNome,
                            style: t.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ExecutarDialog extends StatefulWidget {
  final Receita receita;
  final int maximo;

  const _ExecutarDialog({required this.receita, required this.maximo});

  @override
  State<_ExecutarDialog> createState() => _ExecutarDialogState();
}

class _ExecutarDialogState extends State<_ExecutarDialog> {
  final _lotes = TextEditingController(text: '1');
  final _obs = TextEditingController();

  int get _maximo => widget.maximo.clamp(1, 100000);
  int get _valor => (int.tryParse(_lotes.text.trim()) ?? 0);

  @override
  void dispose() {
    _lotes.dispose();
    _obs.dispose();
    super.dispose();
  }

  void _mudar(int delta) {
    final n = (_valor + delta).clamp(1, _maximo);
    setState(() => _lotes.text = '$n');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.receita;
    final produtos = Dados.produtosPorId;
    final lotes = _valor;
    final valido = lotes >= 1 && lotes <= _maximo;
    final t = Theme.of(context).textTheme;
    Widget linha(ItemReceita i, bool sai) {
      final p = produtos[i.produtoId];
      final qtd = i.quantidade * (valido ? lotes : 0);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                '${sai ? '−' : '+'}$qtd',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: sai ? Colors.red.shade700 : Colors.green.shade700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                '${p?.nome ?? i.produtoNome} '
                '(saldo ${p?.estoque ?? 0} → ${(p?.estoque ?? 0) + (sai ? -qtd : qtd)})',
              ),
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      title: Text('Executar: ${r.nome}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton.outlined(
                    onPressed: lotes > 1 ? () => _mudar(-1) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lotes,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Quantidade de lotes',
                        helperText: 'De 1 a $_maximo',
                        errorText: _lotes.text.isEmpty || valido
                            ? null
                            : 'Informe de 1 a $_maximo lote(s)',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: lotes < _maximo ? () => _mudar(1) : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _obs,
                maxLength: 255,
                decoration: const InputDecoration(labelText: 'Observação'),
              ),
              const SizedBox(height: 8),
              Text(
                'SAI DO ESTOQUE',
                style: t.labelSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              for (final i in r.entradas) linha(i, true),
              const SizedBox(height: 8),
              Text(
                'ENTRA NO ESTOQUE',
                style: t.labelSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              for (final i in r.saidas) linha(i, false),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: valido
              ? () => Navigator.pop(context, (lotes, _obs.text.trim()))
              : null,
          child: const Text('Executar operação'),
        ),
      ],
    );
  }
}
