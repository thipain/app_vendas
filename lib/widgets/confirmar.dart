import 'package:flutter/material.dart';

Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensagem,
  String confirmarTexto = 'Confirmar',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensagem),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmarTexto),
        ),
      ],
    ),
  );
  return ok ?? false;
}
