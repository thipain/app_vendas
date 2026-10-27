import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/produto_repository.dart';
import '../../models/produto.dart';
import '../../widgets/confirmar.dart';

class ProdutoFormPage extends StatefulWidget {
  final Produto? produto;
  const ProdutoFormPage({super.key, this.produto});

  @override
  State<ProdutoFormPage> createState() => _ProdutoFormPageState();
}

class _ProdutoFormPageState extends State<ProdutoFormPage> {
  final _form = GlobalKey<FormState>();
  final _repo = ProdutoRepository();
  late final _nome = TextEditingController(text: widget.produto?.nome);
  late final _codigo = TextEditingController(text: widget.produto?.codigo);
  late final _preco = TextEditingController(
      text: widget.produto == null ? '' : valorParaCampo(widget.produto!.preco));
  late final _estoque =
      TextEditingController(text: widget.produto?.estoque.toString() ?? '0');

  bool get _editando => widget.produto != null;

  @override
  void dispose() {
    _nome.dispose();
    _codigo.dispose();
    _preco.dispose();
    _estoque.dispose();
    super.dispose();
  }

  void _salvar() {
    if (!_form.currentState!.validate()) return;
    _repo.salvar(Produto(
      id: widget.produto?.id ?? '',
      nome: _nome.text.trim(),
      codigo: _codigo.text.trim(),
      preco: lerValor(_preco.text)!,
      estoque: int.parse(_estoque.text.trim()),
    ));
    Navigator.pop(context);
  }

  Future<void> _excluir() async {
    final ok = await confirmar(
      context,
      titulo: 'Excluir produto',
      mensagem: 'Deseja excluir "${widget.produto!.nome}"?',
      confirmarTexto: 'Excluir',
    );
    if (!ok || !mounted) return;
    _repo.excluir(widget.produto!.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar produto' : 'Novo produto'),
        actions: [
          if (_editando)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: _excluir,
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Nome *'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codigo,
              decoration:
                  const InputDecoration(labelText: 'Código / código de barras'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _preco,
              decoration:
                  const InputDecoration(labelText: 'Preço *', prefixText: r'R$ '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final valor = lerValor(v ?? '');
                if (valor == null) return 'Informe um preço válido';
                if (valor < 0) return 'O preço não pode ser negativo';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _estoque,
              decoration: const InputDecoration(labelText: 'Estoque'),
              keyboardType: TextInputType.number,
              validator: (v) => int.tryParse(v?.trim() ?? '') == null
                  ? 'Informe um número inteiro'
                  : null,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save),
              label: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
