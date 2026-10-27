import 'package:flutter/material.dart';

/// Largura a partir da qual o app usa o layout de computador.
const larguraDesktop = 720.0;

/// Centraliza o conteúdo e limita a largura em telas grandes (PC), para que
/// listas e formulários não fiquem esticados de ponta a ponta.
class LarguraMaxima extends StatelessWidget {
  final double largura;
  final Widget child;

  const LarguraMaxima({super.key, this.largura = 800, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: largura),
        child: child,
      ),
    );
  }
}
