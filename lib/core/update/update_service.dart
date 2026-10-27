import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';

class ReleaseInfo {
  final String versao;

  /// APK no Android, instalador .exe no Windows.
  final String arquivoUrl;
  final String notas;
  final bool obrigatoria;

  const ReleaseInfo({
    required this.versao,
    required this.arquivoUrl,
    required this.notas,
    required this.obrigatoria,
  });
}

/// Consulta a última Release publicada no GitHub e compara com a versão
/// instalada. Retorna null quando não há versão nova (ou sem internet).
class UpdateService {
  static Future<ReleaseInfo?> buscarNovaVersao() async {
    try {
      final resposta = await http
          .get(
            Uri.https(
              'api.github.com',
              '/repos/${AppConfig.githubOwner}/${AppConfig.githubRepo}/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 8));
      if (resposta.statusCode != 200) return null;

      final json = jsonDecode(resposta.body) as Map<String, dynamic>;
      final versao = (json['tag_name'] as String? ?? '').replaceFirst(
        RegExp(r'^v'),
        '',
      );
      // Cada Release traz o APK (Android) e o instalador (Windows).
      final extensao = Platform.isWindows ? '.exe' : '.apk';
      final arquivo = (json['assets'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((a) => (a['name'] as String? ?? '').endsWith(extensao))
          .firstOrNull;
      if (arquivo == null) return null;

      final instalada = await PackageInfo.fromPlatform();
      if (compararVersoes(versao, instalada.version) <= 0) return null;

      final notas = json['body'] as String? ?? '';
      return ReleaseInfo(
        versao: versao,
        arquivoUrl: arquivo['browser_download_url'] as String,
        notas: notas
            .replaceAll(AppConfig.marcadorAtualizacaoObrigatoria, '')
            .trim(),
        obrigatoria: notas.contains(AppConfig.marcadorAtualizacaoObrigatoria),
      );
    } catch (e) {
      debugPrint('Não foi possível verificar atualização: $e');
      return null;
    }
  }
}

/// Compara versões no formato 1.2.3. Retorna >0 se [a] for mais nova que [b].
int compararVersoes(String a, String b) {
  List<int> partes(String v) => v
      .split(RegExp(r'[+-]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final pa = partes(a), pb = partes(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}
