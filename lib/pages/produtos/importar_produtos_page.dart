import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/importacao_produtos.dart';
import '../../data/dados.dart';
import '../../data/produto_repository.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';

/// Cadastro de vários produtos de uma vez a partir de uma planilha: colando
/// as linhas copiadas do Excel ou abrindo um arquivo CSV.
class ImportarProdutosPage extends StatefulWidget {
  const ImportarProdutosPage({super.key});

  @override
  State<ImportarProdutosPage> createState() => _ImportarProdutosPageState();
}

class _ImportarProdutosPageState extends State<ImportarProdutosPage> {
  final _texto = TextEditingController();
  List<LinhaImportacao> _linhas = const [];

  static const _exemplo =
      'nome;codigo;categoria;preco;custo;estoque;minimo;unidade\n'
      'Cerveja Lata 350ml;7891149103102;Cervejas;4,50;2,60;180;48;un\n'
      'Gelo em Cubos 5kg;7898000000001;Conveniência;14,90;7,00;20;8;pct';

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  void _ler() {
    final existentes = {
      for (final p in Dados.produtos.value) p.codigo.trim().toLowerCase(),
    }..remove('');
    setState(() {
      _linhas = lerPlanilhaProdutos(_texto.text, codigosExistentes: existentes);
    });
  }

  Future<void> _abrirArquivo() async {
    try {
      final arquivo = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt', 'tsv'],
      );
      if (arquivo == null) return;
      final bytes = await arquivo.readAsBytes();
      // CSV salvo pelo Excel em português costuma vir em Latin-1.
      String conteudo;
      try {
        conteudo = utf8.decode(bytes);
      } on FormatException {
        conteudo = latin1.decode(bytes);
      }
      _texto.text = conteudo.replaceFirst('﻿', '');
      _ler();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  void _importar() {
    final validas = _linhas.where((l) => l.valida).toList();
    if (validas.isEmpty) return;
    final repo = ProdutoRepository();
    var feitos = 0;
    try {
      for (final l in validas) {
        repo.criar(l.produto!, estoqueInicial: l.estoqueInicial);
        feitos++;
      }
    } catch (e) {
      mostrarErro(context, e);
    }
    if (feitos == 0) return;
    avisar(
      context,
      '$feitos produto(s) importado(s). O saldo inicial de cada um está no '
      'histórico do estoque.',
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final validas = _linhas.where((l) => l.valida).length;
    final erros = _linhas.length - validas;
    return Scaffold(
      appBar: AppBar(title: const Text('Importar produtos')),
      bottomNavigationBar: _linhas.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: validas == 0 ? null : _importar,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.download_done),
                  label: Text(
                    validas == 0
                        ? 'Nenhum produto válido'
                        : 'Importar $validas produto(s)'
                              '${erros > 0 ? ' (ignorar $erros com erro)' : ''}',
                  ),
                ),
              ),
            ),
      body: LarguraMaxima(
        largura: 900,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              color: t.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Como importar', style: t.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    const Text(
                      '1. Monte a planilha com as colunas: nome, código, '
                      'categoria, preço, custo, estoque, mínimo e unidade '
                      '(nesta ordem, ou com essa primeira linha de títulos).\n'
                      '2. Selecione as linhas no Excel, copie e cole abaixo, '
                      'ou abra um arquivo CSV.\n'
                      '3. Confira a prévia e toque em Importar.',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Produtos com código já cadastrado são ignorados. '
                      'Preços aceitam vírgula (4,50).',
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _texto,
              minLines: 6,
              maxLines: 14,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Cole aqui as linhas da planilha',
                hintText: _exemplo,
                alignLabelWithHint: true,
              ),
              onChanged: (_) => _ler(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _abrirArquivo,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Abrir arquivo CSV'),
                ),
                TextButton.icon(
                  onPressed: () {
                    _texto.text = _exemplo;
                    _ler();
                  },
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('Ver exemplo'),
                ),
                if (_texto.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      _texto.clear();
                      setState(() => _linhas = const []);
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('Limpar'),
                  ),
              ],
            ),
            if (_linhas.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Prévia: $validas pronto(s) para importar'
                '${erros > 0 ? ' · $erros com erro' : ''}',
                style: t.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final l in _linhas)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  color: l.valida ? null : t.colorScheme.errorContainer,
                  child: ListTile(
                    dense: true,
                    leading: Text(
                      '${l.numero}',
                      style: t.textTheme.labelMedium,
                    ),
                    title: Text(
                      l.valida
                          ? l.produto!.nome
                          : 'Linha ${l.numero}: ${l.erro}',
                    ),
                    subtitle: l.valida
                        ? Text(
                            '${l.produto!.codigo} · ${l.produto!.categoria} · '
                            'custo ${formatarMoeda(l.produto!.custo)} · '
                            'estoque ${l.estoqueInicial} ${l.produto!.unidade} '
                            '(mín. ${l.produto!.estoqueMinimo})',
                          )
                        : null,
                    trailing: l.valida
                        ? Text(
                            formatarMoeda(l.produto!.preco),
                            style: t.textTheme.titleSmall,
                          )
                        : const Icon(Icons.error_outline),
                  ),
                ),
              const SizedBox(height: 80),
            ],
          ],
        ),
      ),
    );
  }
}
