import 'dart:io';

import 'package:http/http.dart' as http;

/// Baixa o instalador da nova versão, executa em modo silencioso e fecha o
/// app. O instalador substitui os arquivos e abre o app de novo no final.
Future<void> instalarAtualizacaoWindows(
  String url,
  String versao, {
  required void Function(double progresso) onProgresso,
}) async {
  final cliente = http.Client();
  try {
    final resposta = await cliente.send(http.Request('GET', Uri.parse(url)));
    if (resposta.statusCode != 200) {
      throw HttpException('HTTP ${resposta.statusCode}');
    }
    final total = resposta.contentLength ?? 0;
    final arquivo = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}app_vendas_setup_$versao.exe',
    );
    final saida = arquivo.openWrite();
    var recebido = 0;
    await for (final parte in resposta.stream) {
      saida.add(parte);
      recebido += parte.length;
      if (total > 0) onProgresso(recebido / total);
    }
    await saida.close();

    await Process.start(arquivo.path, [
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
    ], mode: ProcessStartMode.detached);
    exit(0);
  } finally {
    cliente.close();
  }
}
