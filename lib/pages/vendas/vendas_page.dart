import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/venda_repository.dart';
import '../../models/venda.dart';
import '../../widgets/pendente_icon.dart';
import 'nova_venda_page.dart';
import 'venda_detalhe_page.dart';

class VendasPage extends StatefulWidget {
  const VendasPage({super.key});

  @override
  State<VendasPage> createState() => _VendasPageState();
}

class _VendasPageState extends State<VendasPage> {
  late final _stream = VendaRepository().watchRecentes();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NovaVendaPage()),
        ),
        icon: const Icon(Icons.point_of_sale),
        label: const Text('Nova venda'),
      ),
      body: StreamBuilder<List<Venda>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final vendas = snap.data!;
          if (vendas.isEmpty) {
            return const Center(child: Text('Nenhuma venda registrada'));
          }

          final hoje = DateTime.now();
          final totalHoje = vendas
              .where((v) =>
                  !v.isCancelada &&
                  v.data.year == hoje.year &&
                  v.data.month == hoje.month &&
                  v.data.day == hoje.day)
              .fold<double>(0, (s, v) => s + v.total);

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: vendas.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return ListTile(
                  tileColor: Theme.of(context).colorScheme.primaryContainer,
                  leading: const Icon(Icons.today),
                  title: const Text('Vendido hoje'),
                  trailing: Text(
                    formatarMoeda(totalHoje),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                );
              }
              final v = vendas[i - 1];
              final estiloCancelada = v.isCancelada
                  ? const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.grey,
                    )
                  : null;
              return ListTile(
                title: Row(children: [
                  Flexible(
                    child: Text(
                      v.clienteNome ?? 'Consumidor final',
                      style: estiloCancelada,
                    ),
                  ),
                  const SizedBox(width: 6),
                  PendenteIcon(pendente: v.pendente),
                ]),
                subtitle: Text(
                  '${formatarDataHora(v.data)} · ${v.formaPagamento}'
                  '${v.isCancelada ? ' · CANCELADA' : ''}',
                ),
                trailing: Text(
                  formatarMoeda(v.total),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.merge(estiloCancelada),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VendaDetalhePage(vendaId: v.id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
