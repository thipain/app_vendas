import 'package:flutter/material.dart';

/// Pequeno indicador exibido em itens de lista ainda não sincronizados.
class PendenteIcon extends StatelessWidget {
  final bool pendente;
  const PendenteIcon({super.key, required this.pendente});

  @override
  Widget build(BuildContext context) {
    if (!pendente) return const SizedBox.shrink();
    return const Tooltip(
      message: 'Aguardando sincronização',
      child: Icon(Icons.schedule, size: 16, color: Colors.orange),
    );
  }
}
