import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/imagem.dart';
import '../../core/regra_exception.dart';
import '../../data/dados.dart';
import '../../data/produto_repository.dart';
import '../../models/produto.dart';
import '../../widgets/foto_produto.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../estoque/estoque_widgets.dart';

/// Cadastro e edição de produto (nome, SKU, preços, estoque, foto...).
class ProdutoFormPage extends StatefulWidget {
  final Produto? produto;
  const ProdutoFormPage({super.key, this.produto});

  @override
  State<ProdutoFormPage> createState() => _ProdutoFormPageState();
}

class _ProdutoFormPageState extends State<ProdutoFormPage> {
  static const _sugestoes = [
    'Cervejas',
    'Destilados',
    'Whiskies',
    'Energéticos',
    'Refrigerantes',
    'Conveniência',
  ];

  final _repo = ProdutoRepository();
  late final Produto? _original = widget.produto;
  bool get _editando => _original != null;

  late final _nome = TextEditingController(text: _original?.nome ?? '');
  late final _codigo = TextEditingController(text: _original?.codigo ?? '');
  late final _categoria = TextEditingController(
    text: _original?.categoria ?? '',
  );
  late final _preco = TextEditingController(
    text: _original == null ? '' : valorParaCampo(_original.preco),
  );
  late final _custo = TextEditingController(
    text: _original == null ? '' : custoParaCampo(_original.custo),
  );
  late final _unidade = TextEditingController(text: _original?.unidade ?? 'un');
  late final _estoque = TextEditingController(
    text: '${_original?.estoque ?? 0}',
  );
  late final _minimo = TextEditingController(
    text: '${_original?.estoqueMinimo ?? 0}',
  );
  final _motivo = TextEditingController();
  late String _foto = _original?.foto ?? '';

  @override
  void dispose() {
    for (final c in [
      _nome,
      _codigo,
      _categoria,
      _preco,
      _custo,
      _unidade,
      _estoque,
      _minimo,
      _motivo,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _estoqueAlterado =>
      _editando && int.tryParse(_estoque.text.trim()) != _original!.estoque;

  List<String> get _categorias {
    final s = <String>{..._sugestoes};
    for (final p in Dados.produtos.value) {
      if (p.categoria.trim().isNotEmpty) s.add(p.categoria.trim());
    }
    return s.toList();
  }

  Future<void> _escolherFoto({bool camera = false}) async {
    try {
      final f = await escolherImagem(camera: camera);
      if (f != null && mounted) setState(() => _foto = f);
    } catch (_) {
      if (mounted) avisar(context, 'Use JPG, PNG ou WEBP de até 5 MB.');
    }
  }

  void _salvar() {
    final nome = _nome.text.trim();
    final codigo = _codigo.text.trim();
    final categoria = _categoria.text.trim();
    final unidade = _unidade.text.trim();
    final motivo = _motivo.text.trim();

    String? erro;
    final preco = lerValor(_preco.text);
    final custo = lerValor(_custo.text) ?? 0;
    final estoque = int.tryParse(_estoque.text.trim());
    final minimo = int.tryParse(_minimo.text.trim());

    if (nome.isEmpty ||
        codigo.isEmpty ||
        categoria.isEmpty ||
        unidade.isEmpty) {
      erro = 'Preencha nome, SKU, categoria e unidade.';
    } else if (nome.length > 160 ||
        codigo.length > 60 ||
        categoria.length > 100 ||
        unidade.length > 40 ||
        motivo.length > 255) {
      erro = 'Um dos campos ultrapassa o tamanho permitido.';
    } else if (preco == null || estoque == null || minimo == null) {
      erro = 'Informe preços e quantidades válidos.';
    } else if (preco < 0 || custo < 0 || estoque < 0 || minimo < 0) {
      erro = 'Preços e quantidades não podem ser negativos.';
    } else if (Dados.produtos.value.any(
      (p) =>
          p.id != _original?.id &&
          p.codigo.trim().toLowerCase() == codigo.toLowerCase(),
    )) {
      erro = 'O SKU informado já existe.';
    } else if (_estoqueAlterado && motivo.length < 5) {
      erro =
          'Informe o motivo do ajuste de estoque com pelo menos 5 caracteres.';
    }
    if (erro != null) {
      mostrarErro(context, RegraException(erro));
      return;
    }

    final dados = Produto(
      id: _original?.id ?? '',
      nome: nome,
      codigo: codigo,
      categoria: categoria,
      preco: (preco! * 100).round() / 100,
      custo: (custo * 10000).round() / 10000,
      estoque: _original?.estoque ?? 0,
      estoqueMinimo: minimo!,
      unidade: unidade,
      foto: _foto,
      ativo: _original?.ativo ?? true,
    );

    final ok = _editando
        ? executar(context, () {
            final antes = _original!;
            _repo.editar(antes, dados);
            if (_estoqueAlterado) {
              // Parte do saldo atual (pode ter mudado com vendas enquanto o
              // formulário estava aberto).
              final atual =
                  Dados.produtosPorId[antes.id]?.estoque ?? antes.estoque;
              _repo.ajustarEstoque(
                dados.copyWith(estoque: atual),
                estoque!,
                motivo,
              );
            }
          }, sucesso: 'Produto atualizado.')
        : executar(
            context,
            () => _repo.criar(dados, estoqueInicial: estoque!),
            sucesso: 'Produto cadastrado.',
          );
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final android = defaultTargetPlatform == TargetPlatform.android;
    final inteiro = [FilteringTextInputFormatter.digitsOnly];
    const decimal = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar produto' : 'Novo produto'),
      ),
      body: LarguraMaxima(
        largura: 640,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                FotoProduto(foto: _foto, nome: _nome.text, tamanho: 88),
                const SizedBox(width: 16),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _escolherFoto,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          _foto.isEmpty ? 'Escolher foto' : 'Trocar foto',
                        ),
                      ),
                      if (android)
                        OutlinedButton.icon(
                          onPressed: () => _escolherFoto(camera: true),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Câmera'),
                        ),
                      if (_foto.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => setState(() => _foto = ''),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remover foto'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Foto opcional (JPG, PNG ou WEBP).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nome,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome *'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _codigo,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Código / SKU *',
                helperText: 'Código interno ou código de barras',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _categoria,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: 'Categoria *',
                suffixIcon: PopupMenuButton<String>(
                  tooltip: 'Sugestões',
                  icon: const Icon(Icons.arrow_drop_down),
                  onSelected: (v) => setState(() => _categoria.text = v),
                  itemBuilder: (_) => [
                    for (final c in _categorias)
                      PopupMenuItem(value: c, child: Text(c)),
                  ],
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _preco,
                    keyboardType: decimal,
                    decoration: const InputDecoration(
                      labelText: 'Preço de venda *',
                      prefixText: 'R\$ ',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _custo,
                    keyboardType: decimal,
                    decoration: const InputDecoration(
                      labelText: 'Preço de custo *',
                      prefixText: 'R\$ ',
                      helperText: 'Até 4 casas decimais',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unidade,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Unidade *',
                hintText: 'Ex.: 350ml, un, cx',
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _estoque,
                    keyboardType: TextInputType.number,
                    inputFormatters: inteiro,
                    decoration: InputDecoration(
                      labelText: _editando
                          ? 'Estoque (saldo) *'
                          : 'Estoque inicial *',
                      helperText: _editando
                          ? 'Alterar gera um ajuste no histórico'
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minimo,
                    keyboardType: TextInputType.number,
                    inputFormatters: inteiro,
                    decoration: const InputDecoration(
                      labelText: 'Alerta mínimo *',
                    ),
                  ),
                ),
              ],
            ),
            if (_estoqueAlterado) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _motivo,
                maxLength: 255,
                decoration: InputDecoration(
                  labelText: 'Motivo do ajuste de estoque *',
                  helperText:
                      'Saldo de ${_original!.estoque} para ${_estoque.text.trim()} · mínimo 5 caracteres',
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.check),
              label: Text(
                _editando ? 'Salvar alterações' : 'Cadastrar produto',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
