import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../data/sistema_repository.dart';
import '../../models/loja.dart';
import '../../widgets/confirmar.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';

/// Erros enviados pelos aparelhos das lojas, agrupados pela mensagem, para o
/// dono do sistema descobrir problemas antes de o cliente reclamar.
class ErrosAppPage extends StatefulWidget {
  const ErrosAppPage({super.key});

  @override
  State<ErrosAppPage> createState() => _ErrosAppPageState();
}

/// Ocorrências do mesmo erro.
class _Grupo {
  final List<ErroApp> erros;
  _Grupo(this.erros);

  ErroApp get ultimo => erros.first;
  Set<String> get lojas => {
    for (final e in erros) e.lojaNome ?? 'Sem loja (login/painel)',
  };
  Set<String> get versoes => {for (final e in erros) e.versao};
  Set<String> get plataformas => {for (final e in erros) e.plataforma};
}

class _ErrosAppPageState extends State<ErrosAppPage> {
  final _repo = SistemaRepository();
  Periodo _periodo = Periodo(
    DateTime.now().subtract(const Duration(days: 6)),
    DateTime.now(),
  );
  late Stream<List<ErroApp>> _erros = _consultar();

  Stream<List<ErroApp>> _consultar() =>
      _repo.watchErros(_periodo.inicio, _periodo.fim);

  static String _origem(String o) => switch (o) {
    'tela' => 'Erro de tela',
    'sincronizacao' => 'Falha ao sincronizar',
    _ => 'Erro do app',
  };

  Future<void> _resolver(_Grupo g) async {
    final ok = await confirmar(
      context,
      titulo: 'Marcar como resolvido',
      mensagem:
          'Apagar as ${g.erros.length} ocorrência(s) deste erro no período? '
          'Se ele acontecer de novo, volta a aparecer aqui.',
      confirmarTexto: 'Apagar',
    );
    if (!ok) return;
    try {
      await _repo.excluirErros(g.erros.map((e) => e.id));
      if (mounted) avisar(context, 'Ocorrências apagadas.');
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: LarguraMaxima(
        largura: 900,
        child: StreamBuilder<List<ErroApp>>(
          stream: _erros,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Erro: ${snap.error}'));
            }
            final erros = snap.data ?? const <ErroApp>[];
            final porMensagem = <String, List<ErroApp>>{};
            for (final e in erros) {
              porMensagem
                  .putIfAbsent('${e.origem}|${e.mensagem}', () => [])
                  .add(e);
            }
            final grupos = porMensagem.values.map(_Grupo.new).toList()
              ..sort((a, b) => b.erros.length.compareTo(a.erros.length));
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FiltroPeriodo(
                      periodo: _periodo,
                      onChanged: (p) => setState(() {
                        _periodo = p;
                        _erros = _consultar();
                      }),
                    ),
                    Text(
                      '${erros.length} ocorrência(s) · ${grupos.length} '
                      'erro(s) diferente(s)',
                      style: t.textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Cada aparelho envia o mesmo erro uma vez por sessão. '
                  '"Falha ao sincronizar" é uma gravação recusada pelo '
                  'servidor (ex.: loja travada ou sem permissão).',
                  style: t.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (!snap.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (grupos.isEmpty)
                  const EstadoVazio(
                    icone: Icons.check_circle_outline,
                    titulo: 'Nenhum erro no período',
                    mensagem: 'Os aparelhos das lojas não relataram problemas.',
                  ),
                for (final g in grupos)
                  Card(
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: t.colorScheme.errorContainer,
                        child: Text(
                          '${g.erros.length}',
                          style: TextStyle(
                            color: t.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        g.ultimo.mensagem,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_origem(g.ultimo.origem)} · último em '
                        '${formatarDataHora(g.ultimo.data)} · '
                        '${g.lojas.join(', ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (g.ultimo.contexto != null)
                          Text('Operação: ${g.ultimo.contexto}'),
                        Text(
                          'Versões: ${g.versoes.join(', ')} · '
                          'Plataformas: ${g.plataformas.join(', ')}',
                        ),
                        Text(
                          'Usuários: '
                          '${{for (final e in g.erros) e.email ?? '?'}.join(', ')}',
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          '${g.ultimo.tipo}: ${g.ultimo.mensagem}\n\n'
                          '${g.ultimo.stack}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text:
                                        '${g.ultimo.tipo}: ${g.ultimo.mensagem}\n'
                                        'Versão ${g.ultimo.versao} · '
                                        '${g.ultimo.plataforma}\n\n'
                                        '${g.ultimo.stack}',
                                  ),
                                );
                                if (context.mounted) {
                                  avisar(context, 'Erro copiado.');
                                }
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copiar detalhes'),
                            ),
                            TextButton.icon(
                              onPressed: () => _resolver(g),
                              icon: const Icon(Icons.done_all),
                              label: const Text('Marcar como resolvido'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
