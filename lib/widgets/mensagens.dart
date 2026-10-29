import 'package:flutter/material.dart';

import '../core/regra_exception.dart';

/// Mensagem curta no rodapé da tela.
void avisar(BuildContext context, String mensagem) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensagem)));
}

/// Mostra o erro de uma operação. Erros de regra (RegraException, StateError)
/// já trazem a mensagem pronta para o usuário.
void mostrarErro(BuildContext context, Object erro) {
  final msg = switch (erro) {
    RegraException(:final mensagem) => mensagem,
    StateError(:final message) => message,
    _ => 'Não foi possível concluir: $erro',
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
}

/// Executa uma operação de repositório e mostra o erro, se houver.
/// Retorna true quando deu certo.
bool executar(
  BuildContext context,
  void Function() operacao, {
  String? sucesso,
}) {
  try {
    operacao();
    if (sucesso != null) avisar(context, sucesso);
    return true;
  } catch (e) {
    mostrarErro(context, e);
    return false;
  }
}

/// Pede um texto (ex.: motivo de cancelamento). Retorna null se cancelado.
Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String rotulo,
  String inicial = '',
  String confirmar = 'Confirmar',
  int minimo = 0,
  int maximo = 255,
  int linhas = 1,
  String? ajuda,
}) {
  final ctrl = TextEditingController(text: inicial);
  final form = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Form(
        key: form,
        child: TextFormField(
          controller: ctrl,
          autofocus: true,
          maxLength: maximo,
          minLines: linhas,
          maxLines: linhas == 1 ? 1 : linhas + 2,
          decoration: InputDecoration(labelText: rotulo, helperText: ajuda),
          validator: (v) => (v ?? '').trim().length < minimo
              ? 'Informe pelo menos $minimo caracteres'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(ctx, ctrl.text.trim());
            }
          },
          child: Text(confirmar),
        ),
      ],
    ),
  );
}
