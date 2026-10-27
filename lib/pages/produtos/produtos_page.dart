import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/produto_repository.dart';
import '../../models/produto.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/pendente_icon.dart';
import 'produto_form_page.dart';
import '../../widgets/largura_maxima.dart';

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({super.key});

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

class _ProdutosPageState extends State<ProdutosPage> {
  final _repo = ProdutoRepository();
  late final _stream = _repo.watchAtivos();
  String _busca = '';

  void _abrirForm([Produto? produto]) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProdutoFormPage(produto: produto)),
    );
  }

  Future<void> _excluir(Produto p) async {
    final ok = await confirmar(
      context,
      titulo: 'Excluir produto',
      mensagem: 'Deseja excluir "${p.nome}"?',
      confirmarTexto: 'Excluir',
    );
    if (ok) _repo.excluir(p.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirForm,
        tooltip: 'Novo produto',
        child: const Icon(Icons.add),
      ),
      body: LarguraMaxima(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar por nome ou código',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _busca = v.toLowerCase()),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Produto>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Erro: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final produtos = snap.data!
                      .where(
                        (p) =>
                            p.nome.toLowerCase().contains(_busca) ||
                            p.codigo.toLowerCase().contains(_busca),
                      )
                      .toList();
                  if (produtos.isEmpty) {
                    return const Center(
                      child: Text('Nenhum produto cadastrado'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: produtos.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = produtos[i];
                      return ListTile(
                        title: Row(
                          children: [
                            Flexible(child: Text(p.nome)),
                            const SizedBox(width: 6),
                            PendenteIcon(pendente: p.pendente),
                          ],
                        ),
                        subtitle: Text(
                          [
                            if (p.codigo.isNotEmpty) 'Cód. ${p.codigo}',
                            'Estoque: ${p.estoque}',
                          ].join(' · '),
                          style: p.estoque <= 0
                              ? const TextStyle(color: Colors.red)
                              : null,
                        ),
                        trailing: Text(
                          formatarMoeda(p.preco),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        onTap: () => _abrirForm(p),
                        onLongPress: () => _excluir(p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
