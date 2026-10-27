import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/regra_exception.dart';
import '../../data/dados.dart';
import '../../data/transformacao_repository.dart';
import '../../models/transformacao.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/seletor.dart';

class _LinhaReceita {
  String? produtoId;
  String produtoNome;
  final TextEditingController quantidade;

  _LinhaReceita({this.produtoId, this.produtoNome = '', int qtd = 1})
    : quantidade = TextEditingController(text: '$qtd');
}

/// Cadastro/edição de uma regra de montagem ou desmanche.
class ReceitaFormPage extends StatefulWidget {
  final Receita? receita;
  const ReceitaFormPage({super.key, this.receita});

  @override
  State<ReceitaFormPage> createState() => _ReceitaFormPageState();
}

class _ReceitaFormPageState extends State<ReceitaFormPage> {
  final _repo = TransformacaoRepository();
  late final _nome = TextEditingController(text: widget.receita?.nome ?? '');
  late String _tipo = widget.receita?.tipo ?? Receita.composicao;
  late final List<_LinhaReceita> _entradas = _linhas(widget.receita?.entradas);
  late final List<_LinhaReceita> _saidas = _linhas(widget.receita?.saidas);

  static List<_LinhaReceita> _linhas(List<ItemReceita>? itens) {
    if (itens == null || itens.isEmpty) return [_LinhaReceita()];
    return [
      for (final i in itens)
        _LinhaReceita(
          produtoId: i.produtoId,
          produtoNome: i.produtoNome,
          qtd: i.quantidade,
        ),
    ];
  }

  @override
  void dispose() {
    _nome.dispose();
    for (final l in [..._entradas, ..._saidas]) {
      l.quantidade.dispose();
    }
    super.dispose();
  }

  void _mudarTipo(String tipo) {
    setState(() {
      _tipo = tipo;
      // Montagem gera 1 produto; desmanche consome 1 item.
      final lista = tipo == Receita.composicao ? _saidas : _entradas;
      while (lista.length > 1) {
        lista.removeLast().quantidade.dispose();
      }
    });
  }

  Future<void> _escolher(_LinhaReceita l) async {
    final p = await selecionarProduto(context);
    if (p == null) return;
    setState(() {
      l.produtoId = p.id;
      l.produtoNome = p.nome;
    });
  }

  List<ItemReceita>? _itens(List<_LinhaReceita> linhas) {
    final itens = <ItemReceita>[];
    for (final l in linhas) {
      final q = int.tryParse(l.quantidade.text.trim()) ?? 0;
      if (l.produtoId == null || q <= 0) {
        mostrarErro(
          context,
          const RegraException(
            'Selecione o produto e informe uma quantidade maior que zero.',
          ),
        );
        return null;
      }
      if (q > 100000) {
        mostrarErro(
          context,
          const RegraException(
            'A quantidade por lote deve ficar entre 1 e 100.000.',
          ),
        );
        return null;
      }
      itens.add(
        ItemReceita(
          produtoId: l.produtoId!,
          produtoNome: l.produtoNome,
          quantidade: q,
        ),
      );
    }
    return itens;
  }

  void _salvar() {
    final entradas = _itens(_entradas);
    if (entradas == null) return;
    final saidas = _itens(_saidas);
    if (saidas == null) return;
    final antiga = widget.receita;
    final receita = Receita(
      id: antiga?.id ?? '',
      nome: _nome.text.trim(),
      tipo: _tipo,
      ativo: antiga?.ativo ?? true,
      entradas: entradas,
      saidas: saidas,
    );
    final ok = executar(
      context,
      () => _repo.salvarReceita(receita, Dados.produtosPorId, antiga: antiga),
      sucesso: 'Operação salva. Ela já pode ser executada no estoque.',
    );
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final composicao = _tipo == Receita.composicao;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.receita == null ? 'Nova operação' : 'Editar regra'),
      ),
      body: LarguraMaxima(
        largura: 720,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _nome,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Nome da operação *',
                hintText: 'Ex.: Copão de energético, Fardo → latas',
              ),
            ),
            const SizedBox(height: 8),
            Text('Tipo', style: t.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: Receita.composicao,
                  icon: Icon(Icons.call_merge),
                  label: Text('Montagem'),
                ),
                ButtonSegment(
                  value: Receita.decomposicao,
                  icon: Icon(Icons.call_split),
                  label: Text('Desmanche'),
                ),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => _mudarTipo(s.first),
            ),
            const SizedBox(height: 6),
            Text(
              composicao
                  ? 'Montagem: vários itens consumidos geram exatamente 1 produto final.'
                  : 'Desmanche: exatamente 1 item agrupado gera um ou vários itens.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 20),
            _secao(
              titulo: 'Consome (entradas)',
              linhas: _entradas,
              podeAdicionar: composicao,
              textoAdicionar: 'Adicionar entrada',
            ),
            const SizedBox(height: 20),
            _secao(
              titulo: 'Gera (saídas)',
              linhas: _saidas,
              podeAdicionar: !composicao,
              textoAdicionar: 'Adicionar saída',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.check),
              label: const Text('Salvar operação'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secao({
    required String titulo,
    required List<_LinhaReceita> linhas,
    required bool podeAdicionar,
    required String textoAdicionar,
  }) {
    final t = Theme.of(context).textTheme;
    final porId = Dados.produtosPorId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: t.titleMedium),
        const SizedBox(height: 6),
        for (final (i, l) in linhas.indexed)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: () => _escolher(l),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.produtoId == null
                                    ? 'Selecionar produto'
                                    : [
                                        porId[l.produtoId]?.nome ??
                                            l.produtoNome,
                                        if (porId[l.produtoId]?.ativo == false)
                                          '— desativado',
                                      ].join(' '),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color:
                                      l.produtoId == null ||
                                          porId[l.produtoId]?.ativo == false
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: l.quantidade,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Qtd. por lote',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remover',
                    onPressed: linhas.length > 1
                        ? () => setState(
                            () => linhas.removeAt(i).quantidade.dispose(),
                          )
                        : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
        if (podeAdicionar)
          TextButton.icon(
            onPressed: () => setState(() => linhas.add(_LinhaReceita())),
            icon: const Icon(Icons.add),
            label: Text(textoAdicionar),
          ),
      ],
    );
  }
}
