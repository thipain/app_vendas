import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/mensagens.dart';

/// Telefone no formato do wa.me (55 + DDD + número). Null se não parece um
/// telefone brasileiro.
String? telefoneInternacional(String telefone) {
  final d = telefone.replaceAll(RegExp(r'\D'), '');
  if (d.length == 10 || d.length == 11) return '55$d';
  if ((d.length == 12 || d.length == 13) && d.startsWith('55')) return d;
  return null;
}

Future<void> _abrir(BuildContext context, Uri uri, String erro) async {
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) avisar(context, erro);
  } catch (e) {
    if (context.mounted) mostrarErro(context, e);
  }
}

/// Abre uma conversa no WhatsApp com a mensagem já escrita.
Future<void> abrirWhatsApp(
  BuildContext context,
  String telefone, {
  String mensagem = '',
}) async {
  final fone = telefoneInternacional(telefone);
  if (fone == null) {
    avisar(context, 'Telefone inválido para o WhatsApp (use DDD + número).');
    return;
  }
  final texto = mensagem.isEmpty
      ? ''
      : '?text=${Uri.encodeComponent(mensagem)}';
  await _abrir(
    context,
    Uri.parse('https://wa.me/$fone$texto'),
    'Não foi possível abrir o WhatsApp.',
  );
}

Future<void> ligar(BuildContext context, String telefone) => _abrir(
  context,
  Uri(scheme: 'tel', path: telefone.replaceAll(RegExp(r'[^\d+]'), '')),
  'Não foi possível abrir o discador.',
);

/// Abre o endereço no app de mapas (Google Maps ou o padrão do aparelho).
Future<void> abrirMapa(BuildContext context, String endereco) => _abrir(
  context,
  Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': endereco}),
  'Não foi possível abrir o mapa.',
);
