import 'package:flutter/material.dart';

import '../../data/cliente_repository.dart';
import '../../models/cliente.dart';
import '../../widgets/confirmar.dart';

class ClienteFormPage extends StatefulWidget {
  final Cliente? cliente;
  const ClienteFormPage({super.key, this.cliente});

  @override
  State<ClienteFormPage> createState() => _ClienteFormPageState();
}

class _ClienteFormPageState extends State<ClienteFormPage> {
  final _form = GlobalKey<FormState>();
  final _repo = ClienteRepository();
  late final _nome = TextEditingController(text: widget.cliente?.nome);
  late final _documento = TextEditingController(text: widget.cliente?.documento);
  late final _telefone = TextEditingController(text: widget.cliente?.telefone);
  late final _email = TextEditingController(text: widget.cliente?.email);
  late final _endereco = TextEditingController(text: widget.cliente?.endereco);

  bool get _editando => widget.cliente != null;

  @override
  void dispose() {
    for (final c in [_nome, _documento, _telefone, _email, _endereco]) {
      c.dispose();
    }
    super.dispose();
  }

  void _salvar() {
    if (!_form.currentState!.validate()) return;
    _repo.salvar(Cliente(
      id: widget.cliente?.id ?? '',
      nome: _nome.text.trim(),
      documento: _documento.text.trim(),
      telefone: _telefone.text.trim(),
      email: _email.text.trim(),
      endereco: _endereco.text.trim(),
    ));
    Navigator.pop(context);
  }

  Future<void> _excluir() async {
    final ok = await confirmar(
      context,
      titulo: 'Excluir cliente',
      mensagem: 'Deseja excluir "${widget.cliente!.nome}"? '
          'As vendas já feitas para ele não serão apagadas.',
      confirmarTexto: 'Excluir',
    );
    if (!ok || !mounted) return;
    _repo.excluir(widget.cliente!.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar cliente' : 'Novo cliente'),
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
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _documento,
              decoration: const InputDecoration(labelText: 'CPF / CNPJ'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telefone,
              decoration: const InputDecoration(labelText: 'Telefone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'E-mail'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _endereco,
              decoration: const InputDecoration(labelText: 'Endereço'),
              maxLines: 2,
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
