import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service.dart';

/// Procura uma versão nova no GitHub e, se houver, pede para o usuário atualizar.
Future<void> verificarAtualizacao(
  BuildContext context, {
  bool avisarSemNovidade = false,
}) async {
  final release = await UpdateService.buscarNovaVersao();
  if (!context.mounted) return;
  if (release == null) {
    if (avisarSemNovidade) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Você já está na versão mais recente '
            '(ou não foi possível consultar sem internet).'),
      ));
    }
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: !release.obrigatoria,
    builder: (_) => _UpdateDialog(release: release),
  );
}

class _UpdateDialog extends StatefulWidget {
  final ReleaseInfo release;
  const _UpdateDialog({required this.release});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _baixando = false;
  double? _progresso;
  String? _erro;

  void _atualizar() {
    setState(() {
      _baixando = true;
      _erro = null;
      _progresso = null;
    });
    OtaUpdate()
        .execute(
          widget.release.apkUrl,
          destinationFilename: 'app_vendas_${widget.release.versao}.apk',
        )
        .listen(
          _onEvento,
          onError: (Object e) => _falhou('$e'),
        );
  }

  void _onEvento(OtaEvent evento) {
    if (!mounted) return;
    switch (evento.status) {
      case OtaStatus.DOWNLOADING:
        setState(() => _progresso = (double.tryParse(evento.value ?? '') ?? 0) / 100);
      case OtaStatus.INSTALLING:
      case OtaStatus.INSTALLATION_DONE:
        // O instalador do Android assume daqui em diante.
        setState(() => _baixando = false);
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _falhou('Permita a instalação de apps desta fonte nas configurações '
            'do Android e tente novamente.');
      case OtaStatus.CANCELED:
        setState(() => _baixando = false);
      default:
        _falhou('Falha ao baixar a atualização (${evento.status.name}).');
    }
  }

  void _falhou(String mensagem) {
    if (!mounted) return;
    setState(() {
      _baixando = false;
      _erro = mensagem;
    });
  }

  Future<void> _abrirNoNavegador() => launchUrl(
        Uri.parse(widget.release.apkUrl),
        mode: LaunchMode.externalApplication,
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    return PopScope(
      canPop: !r.obrigatoria && !_baixando,
      child: AlertDialog(
        title: Text('Nova versão ${r.versao}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.obrigatoria
                  ? 'Esta atualização é obrigatória para o app continuar '
                      'funcionando corretamente.'
                  : 'Há uma nova versão disponível. Recomendamos atualizar '
                      'para o melhor funcionamento do app.'),
              if (r.notas.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Novidades:',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(r.notas),
              ],
              if (_baixando) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progresso),
                const SizedBox(height: 4),
                Text(_progresso == null
                    ? 'Iniciando download...'
                    : 'Baixando ${(_progresso! * 100).toStringAsFixed(0)}%'),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                TextButton(
                  onPressed: _abrirNoNavegador,
                  child: const Text('Baixar pelo navegador'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!r.obrigatoria)
            TextButton(
              onPressed: _baixando ? null : () => Navigator.pop(context),
              child: const Text('Depois'),
            ),
          FilledButton(
            onPressed: _baixando ? null : _atualizar,
            child: const Text('Atualizar agora'),
          ),
        ],
      ),
    );
  }
}
