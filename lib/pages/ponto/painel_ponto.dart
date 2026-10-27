import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/regra_exception.dart';
import '../../core/sessao.dart';
import '../../data/ponto_repository.dart';
import '../../models/registro_ponto.dart';
import '../../widgets/mensagens.dart';
import '../../widgets/pendente_icon.dart';
import '../inicio/comum.dart';

/// Relógio ao vivo, situação da localização e botão de registrar o ponto do
/// usuário logado. Usado em "Meu ponto" e em "Ponto da equipe".
class PainelPonto extends StatefulWidget {
  /// Chamado quando o dia muda (para as telas atualizarem "hoje").
  final VoidCallback? onNovoDia;

  const PainelPonto({super.key, this.onNovoDia});

  @override
  State<PainelPonto> createState() => _PainelPontoState();
}

class _PainelPontoState extends State<PainelPonto> {
  final _repo = PontoRepository();
  late final Stream<RegistroPonto?> _ultimo;
  late final Timer _timer;
  DateTime _agora = DateTime.now();
  bool _registrando = false;
  String _situacao = 'Aguardando localização';
  String _detalhe = 'Autorize a localização ao registrar.';

  @override
  void initState() {
    super.initState();
    _ultimo = _repo.watchUltimo(Sessao.instancia.atual.id);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final antes = _agora;
      setState(() => _agora = DateTime.now());
      if (antes.day != _agora.day) widget.onNovoDia?.call();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _registrar(RegistroPonto? ultimo) async {
    if (ultimo != null &&
        DateTime.now().difference(ultimo.data) < const Duration(seconds: 60)) {
      mostrarErro(
        context,
        const RegraException('Aguarde um minuto antes de registrar novamente.'),
      );
      return;
    }
    setState(() {
      _registrando = true;
      _situacao = 'Obtendo localização...';
      _detalhe = 'Isso pode levar alguns segundos.';
    });
    final local = await _repo.obterLocalizacao();
    if (!mounted) return;
    setState(() {
      _registrando = false;
      _situacao = local.latitude != null
          ? 'Localização identificada'
          : 'Localização não obtida';
      _detalhe = local.endereco;
    });
    String? tipo;
    final ok = executar(context, () => tipo = _repo.registrar(ultimo, local));
    if (ok && tipo != null) {
      avisar(
        context,
        'Ponto registrado: ${tipo == RegistroPonto.entrada ? 'entrada' : 'saída'}.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              DateFormat('HH:mm').format(_agora),
              style: t.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(dataPorExtenso(_agora), style: t.textTheme.titleSmall),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _registrando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.location_on_outlined,
                          color: t.colorScheme.primary,
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _situacao,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(_detalhe, style: t.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<RegistroPonto?>(
              stream: _ultimo,
              builder: (context, s) {
                final ultimo = s.data;
                final tipo = PontoRepository.proximoTipo(ultimo);
                final carregando =
                    s.connectionState == ConnectionState.waiting && !s.hasData;
                return Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        icon: Icon(
                          tipo == RegistroPonto.entrada
                              ? Icons.login
                              : Icons.logout,
                        ),
                        label: Text(
                          tipo == RegistroPonto.entrada
                              ? 'Registrar entrada'
                              : 'Registrar saída',
                        ),
                        onPressed: _registrando || carregando
                            ? null
                            : () => _registrar(ultimo),
                      ),
                    ),
                    if (ultimo != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Último registro: ${ultimo.tipoNome} em '
                            '${DateFormat('dd/MM/yyyy HH:mm').format(ultimo.data)}',
                            style: t.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 4),
                          PendenteIcon(pendente: ultimo.pendente),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'A coordenada e o endereço identificado serão armazenados no registro.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Linha de um registro de ponto.
class ItemPonto extends StatelessWidget {
  final RegistroPonto registro;
  final bool mostrarNome;

  const ItemPonto({
    super.key,
    required this.registro,
    this.mostrarNome = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = registro;
    final t = Theme.of(context);
    final entrada = r.tipo == RegistroPonto.entrada;
    final cor = entrada ? Colors.green.shade700 : t.colorScheme.error;
    return ListTile(
      leading: mostrarNome
          ? CircleAvatar(child: Text(iniciais(r.usuarioNome)))
          : CircleAvatar(
              backgroundColor: cor.withValues(alpha: 0.12),
              foregroundColor: cor,
              child: Icon(entrada ? Icons.login : Icons.logout),
            ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              mostrarNome ? r.usuarioNome : r.tipoNome,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (mostrarNome) ...[
            const SizedBox(width: 8),
            Text(
              r.tipoNome,
              style: TextStyle(color: cor, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(width: 4),
          PendenteIcon(pendente: r.pendente),
        ],
      ),
      subtitle: Text('Local: ${r.local}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            DateFormat('HH:mm').format(r.data),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            DateFormat('dd/MM/yyyy').format(r.data),
            style: t.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
