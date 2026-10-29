import 'package:flutter/material.dart';

import '../data/usuario_repository.dart';
import 'mensagens.dart';

/// Avisa que o e-mail já tinha conta no sistema (de uma loja excluída, por
/// exemplo): a senha digitada no cadastro foi ignorada e a pessoa entra com
/// a senha antiga. Oferece enviar o link para ela criar uma nova senha.
Future<void> avisarContaExistente(BuildContext context, String email) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.manage_accounts_outlined),
      title: const Text('Este e-mail já tinha conta'),
      content: Text(
        '$email já tinha uma conta no sistema. O cadastro foi feito, mas a '
        'senha digitada agora não vale: a pessoa entra com a senha que já '
        'usava.\n\nSe ela não lembrar, envie o link para criar uma nova senha.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Agora não'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final nav = Navigator.of(ctx);
            try {
              await UsuarioRepository.enviarLinkNovaSenha(email);
              nav.pop();
              if (context.mounted) {
                avisar(context, 'Link para nova senha enviado para $email.');
              }
            } catch (e) {
              nav.pop();
              if (context.mounted) mostrarErro(context, e);
            }
          },
          icon: const Icon(Icons.forward_to_inbox),
          label: const Text('Enviar link de nova senha'),
        ),
      ],
    ),
  );
}
