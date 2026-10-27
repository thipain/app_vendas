import 'package:flutter/material.dart';

import '../../data/cliente_repository.dart';
import '../../models/cliente.dart';
import '../../widgets/pendente_icon.dart';
import 'cliente_form_page.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  late final _stream = ClienteRepository().watchTodos();
  String _busca = '';

  void _abrirForm([Cliente? cliente]) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClienteFormPage(cliente: cliente)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirForm,
        tooltip: 'Novo cliente',
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nome, telefone ou documento',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _busca = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Cliente>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Erro: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final clientes = snap.data!
                    .where((c) =>
                        c.nome.toLowerCase().contains(_busca) ||
                        c.telefone.contains(_busca) ||
                        c.documento.contains(_busca))
                    .toList();
                if (clientes.isEmpty) {
                  return const Center(child: Text('Nenhum cliente cadastrado'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: clientes.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = clientes[i];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(c.nome.isEmpty ? '?' : c.nome[0].toUpperCase()),
                      ),
                      title: Row(children: [
                        Flexible(child: Text(c.nome)),
                        const SizedBox(width: 6),
                        PendenteIcon(pendente: c.pendente),
                      ]),
                      subtitle: Text(
                        [c.telefone, c.documento]
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                      ),
                      onTap: () => _abrirForm(c),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
