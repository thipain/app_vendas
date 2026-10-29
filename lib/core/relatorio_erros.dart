import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/banco.dart';
import 'sessao.dart';

/// Envia os erros do app para o Firebase (coleção errosApp), onde o dono do
/// sistema os acompanha no painel administrativo ("Erros do app").
///
/// Funciona no Android e no Windows. Offline, o registro fica na fila e é
/// enviado quando a internet volta. Para não gerar custo, cada erro igual é
/// enviado uma vez por sessão, com no máximo [_limitePorSessao] registros.
class RelatorioErros {
  static const _limitePorSessao = 20;
  static final _enviados = <String>{};
  static String _versao = '';

  static Future<void> iniciar() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _versao = '${info.version}+${info.buildNumber}';
    } catch (_) {}

    final anterior = FlutterError.onError;
    FlutterError.onError = (detalhes) {
      if (anterior != null) {
        anterior(detalhes);
      } else {
        FlutterError.presentError(detalhes);
      }
      registrar(detalhes.exception, detalhes.stack, origem: 'tela');
    };
    PlatformDispatcher.instance.onError = (erro, stack) {
      registrar(erro, stack, origem: 'app');
      return true;
    };
  }

  static String _cortar(String texto, int max) =>
      texto.length > max ? texto.substring(0, max) : texto;

  /// Registra um erro. Só envia com alguém logado (as regras exigem login).
  static void registrar(
    Object erro,
    StackTrace? stack, {
    String origem = 'app',
    String? contexto,
  }) {
    debugPrint('Erro ($origem${contexto == null ? '' : ': $contexto'}): $erro');
    final conta = FirebaseAuth.instance.currentUser;
    if (conta == null) return;
    final mensagem = _cortar('$erro', 1000);
    if (_enviados.length >= _limitePorSessao ||
        !_enviados.add('$origem|$mensagem')) {
      return;
    }
    final sessao = Sessao.instancia;
    FirebaseFirestore.instance
        .collection('errosApp')
        .add({
          'mensagem': mensagem,
          'tipo': erro.runtimeType.toString(),
          'stack': _cortar('${stack ?? ''}', 4000),
          'origem': origem,
          'contexto': contexto,
          'versao': _versao,
          'plataforma': Platform.operatingSystem,
          'lojaId': Banco.temLoja ? Banco.lojaId : null,
          'lojaNome': sessao.lojaNome.isEmpty ? null : sessao.lojaNome,
          'uid': conta.uid,
          'email': conta.email,
          'usuarioNome': sessao.usuario?.nome,
          'data': Timestamp.now(),
        })
        .catchError((Object e) {
          debugPrint('Não foi possível registrar o erro: $e');
          return FirebaseFirestore.instance.collection('errosApp').doc();
        });
  }
}
