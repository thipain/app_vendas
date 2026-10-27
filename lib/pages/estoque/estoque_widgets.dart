import 'package:flutter/material.dart';

import '../../models/produto.dart';

/// Etiqueta colorida (status, tipo de operação, lotes possíveis...).
class Selo extends StatelessWidget {
  final String texto;
  final Color cor;

  const Selo(this.texto, {super.key, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        texto,
        style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Status do produto como no sistema original:
/// Desativado, senão Zerado, senão Repor (estoque <= mínimo), senão Em dia.
class SeloStatusProduto extends StatelessWidget {
  final Produto produto;
  const SeloStatusProduto(this.produto, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = produto;
    if (!p.ativo) return const Selo('Desativado', cor: Colors.grey);
    if (p.estoque <= 0) return Selo('Zerado', cor: Colors.red.shade700);
    if (p.estoque <= p.estoqueMinimo) {
      return Selo('Repor', cor: Colors.orange.shade800);
    }
    return Selo('Em dia', cor: Colors.green.shade700);
  }
}

/// Barra de paginação: "Página X de Y · N registros" (oculta com 1 página).
class Paginacao extends StatelessWidget {
  final int pagina; // começa em 0
  final int totalPaginas;
  final int registros;
  final ValueChanged<int> onChanged;

  const Paginacao({
    super.key,
    required this.pagina,
    required this.totalPaginas,
    required this.registros,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPaginas <= 1) return const SizedBox.shrink();
    final inicio = (pagina - 2).clamp(0, totalPaginas - 1);
    final fim = (pagina + 2).clamp(0, totalPaginas - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              IconButton(
                tooltip: 'Anterior',
                onPressed: pagina > 0 ? () => onChanged(pagina - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              for (var i = inicio; i <= fim; i++)
                i == pagina
                    ? FilledButton(onPressed: null, child: Text('${i + 1}'))
                    : OutlinedButton(
                        onPressed: () => onChanged(i),
                        child: Text('${i + 1}'),
                      ),
              IconButton(
                tooltip: 'Próxima',
                onPressed: pagina < totalPaginas - 1
                    ? () => onChanged(pagina + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Página ${pagina + 1} de $totalPaginas · $registros registros',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Formata o custo com até 4 casas (mínimo 2): 12,5 → "12,50"; 1,2345.
String custoParaCampo(double valor) {
  var t = valor.toStringAsFixed(4);
  while (t.endsWith('0') && t.split('.').last.length > 2) {
    t = t.substring(0, t.length - 1);
  }
  return t.replaceAll('.', ',');
}
