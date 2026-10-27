import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/venda_repository.dart';
import '../../models/venda.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/largura_maxima.dart';

class VendaDetalhePage extends StatefulWidget {
  final String vendaId;
  const VendaDetalhePage({super.key, required this.vendaId});

  @override
  State<VendaDetalhePage> createState() => _VendaDetalhePageState();
}

class _VendaDetalhePageState extends State<VendaDetalhePage> {
  final _repo = VendaRepository();
  late final _stream = _repo.watch(widget.vendaId);

  Future<void> _cancelar(Venda venda) async {
    final ok = await confirmar(
      context,
      titulo: 'Cancelar venda',
      mensagem: 'Os itens voltarão para o estoque. Deseja cancelar esta venda?',
      confirmarTexto: 'Cancelar venda',
    );
    if (ok) _repo.cancelar(venda);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes da venda')),
      body: LarguraMaxima(
        child: StreamBuilder<Venda?>(
          stream: _stream,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final v = snap.data!;
            final texto = Theme.of(context).textTheme;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (v.isCancelada)
                  const Card(
                    color: Colors.red,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'VENDA CANCELADA',
                        style: TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (v.pendente)
                  const ListTile(
                    leading: Icon(Icons.schedule, color: Colors.orange),
                    title: Text('Aguardando sincronização com o servidor'),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.clienteNome ?? 'Consumidor final'),
                  subtitle: Text(
                    '${formatarDataHora(v.data)}\n'
                    'Pagamento: ${v.formaPagamento}'
                    '${v.vendedorEmail.isEmpty ? '' : '\nVendedor: ${v.vendedorEmail}'}',
                  ),
                  isThreeLine: true,
                ),
                const Divider(),
                Text('Itens', style: texto.titleMedium),
                for (final item in v.itens)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.nome),
                    subtitle: Text(
                      '${item.quantidade} x ${formatarMoeda(item.precoUnitario)}',
                    ),
                    trailing: Text(formatarMoeda(item.subtotal)),
                  ),
                const Divider(),
                _linha('Subtotal', formatarMoeda(v.subtotal)),
                if (v.desconto > 0)
                  _linha('Desconto', '- ${formatarMoeda(v.desconto)}'),
                _linha(
                  'Total',
                  formatarMoeda(v.total),
                  estilo: texto.titleLarge,
                ),
                const SizedBox(height: 24),
                if (!v.isCancelada)
                  OutlinedButton.icon(
                    onPressed: () => _cancelar(v),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancelar venda'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _linha(String rotulo, String valor, {TextStyle? estilo}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(rotulo, style: estilo),
        Text(valor, style: estilo),
      ],
    ),
  );
}
