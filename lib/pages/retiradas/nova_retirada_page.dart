import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/regra_exception.dart';
import '../../core/sessao.dart';
import '../../data/dados.dart';
import '../../data/retirada_repository.dart';
import '../../data/venda_repository.dart';
import '../../models/produto.dart';
import '../../models/usuario.dart';
import '../../widgets/foto_produto.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/seletor.dart';

/// Formulário de nova retirada. Devolve o código da retirada registrada.
class NovaRetiradaPage extends StatefulWidget {
  const NovaRetiradaPage({super.key});

  @override
  State<NovaRetiradaPage> createState() => _NovaRetiradaPageState();
}

class _Linha {
  final Produto produto;
  int quantidade;
  _Linha(this.produto, this.quantidade);
}

class _NovaRetiradaPageState extends State<NovaRetiradaPage> {
  final _obs = TextEditingController();
  final _linhas = <_Linha>[];
  String? _funcionarioId;

  bool get _admin => Sessao.instancia.isAdmin;

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  /// Produto com o saldo mais recente (o estoque pode mudar enquanto a tela
  /// está aberta).
  Produto _atual(Produto p) => Dados.produtosPorId[p.id] ?? p;

  Future<void> _adicionar() async {
    final p = await selecionarProduto(
      context,
      titulo: 'Produto da retirada',
      exigirEstoque: true,
    );
    if (p == null || !mounted) return;
    if (_linhas.any((l) => l.produto.id == p.id)) {
      mostrarErro(
        context,
        const RegraException(
          'O mesmo produto foi informado mais de uma vez na operação.',
        ),
      );
      return;
    }
    setState(() => _linhas.add(_Linha(p, 1)));
  }

  Future<void> _digitarQuantidade(_Linha l) async {
    final texto = await pedirTexto(
      context,
      titulo: l.produto.nome,
      rotulo: 'Quantidade',
      inicial: '${l.quantidade}',
      maximo: 6,
    );
    if (texto == null || !mounted) return;
    final n = int.tryParse(texto);
    final max = _atual(l.produto).estoque;
    if (n == null || n < 1) {
      mostrarErro(
        context,
        const RegraException('Informe uma quantidade maior que zero.'),
      );
      return;
    }
    if (n > max) {
      mostrarErro(
        context,
        RegraException('${l.produto.nome}: há somente $max no estoque.'),
      );
      return;
    }
    setState(() => l.quantidade = n);
  }

  void _registrar() {
    final Usuario? funcionario = _admin
        ? Dados.equipe.value.where((u) => u.id == _funcionarioId).firstOrNull
        : Sessao.instancia.atual;
    if (funcionario == null) {
      mostrarErro(
        context,
        const RegraException('Funcionário não encontrado ou bloqueado.'),
      );
      return;
    }
    try {
      final id = RetiradaRepository().registrar(funcionario, [
        for (final l in _linhas) ItemCarrinho(_atual(l.produto), l.quantidade),
      ], _obs.text);
      Navigator.pop(
        context,
        id.length > 6 ? id.substring(0, 6).toUpperCase() : id,
      );
    } catch (e) {
      mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final total = _linhas.fold<double>(
      0,
      (s, l) => s + _atual(l.produto).preco * l.quantidade,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Nova retirada')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LarguraMaxima(
            largura: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_admin)
                  DropdownButtonFormField<String>(
                    initialValue: _funcionarioId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Funcionário *',
                    ),
                    items: [
                      for (final u in Dados.equipeAtiva)
                        DropdownMenuItem(
                          value: u.id,
                          child: Text(
                            '${u.nome} · ${u.email}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _funcionarioId = v),
                  )
                else
                  Card(
                    margin: EdgeInsets.zero,
                    color: t.colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'RETIRADA EM NOME DE ${Sessao.instancia.atual.nome.toUpperCase()}',
                        style: t.textTheme.titleSmall?.copyWith(
                          color: t.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text('Produtos', style: t.textTheme.titleMedium),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar produto'),
                      onPressed: _adicionar,
                    ),
                  ],
                ),
                if (_linhas.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Adicione ao menos um produto à retirada.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.colorScheme.outline),
                    ),
                  ),
                for (final l in _linhas) _linha(l),
                const SizedBox(height: 16),
                TextField(
                  controller: _obs,
                  maxLength: 255,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observação',
                    hintText: 'Ex.: consumo no intervalo',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total pelo preço de venda',
                        style: t.textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      formatarMoeda(total),
                      style: t.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Registrar retirada'),
                  onPressed: _registrar,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linha(_Linha l) {
    final p = _atual(l.produto);
    final max = p.estoque;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            FotoProduto(foto: p.foto, nome: p.nome, tamanho: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nome, overflow: TextOverflow.ellipsis),
                  Text(
                    '$max disponível(is) · ${formatarMoeda(p.preco)} cada',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Diminuir',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: l.quantidade > 1
                  ? () => setState(() => l.quantidade--)
                  : null,
            ),
            InkWell(
              onTap: () => _digitarQuantidade(l),
              child: SizedBox(
                width: 36,
                child: Text(
                  '${l.quantidade}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Aumentar',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: l.quantidade < max
                  ? () => setState(() => l.quantidade++)
                  : null,
            ),
            IconButton(
              tooltip: 'Remover',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _linhas.remove(l)),
            ),
          ],
        ),
      ),
    );
  }
}
