import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/sistema_repository.dart';
import '../../models/loja.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';

/// Ações do dono do sistema (cadastro de lojas, pagamentos, avisos...).
class AuditoriaSistemaPage extends StatefulWidget {
  const AuditoriaSistemaPage({super.key});

  @override
  State<AuditoriaSistemaPage> createState() => _AuditoriaSistemaPageState();
}

class _AuditoriaSistemaPageState extends State<AuditoriaSistemaPage> {
  final _repo = SistemaRepository();
  late final Stream<List<Loja>> _lojas = _repo.watchLojas();
  Periodo _periodo = Periodo(
    DateTime.now().subtract(const Duration(days: 29)),
    DateTime.now(),
  );
  late Stream<List<RegistroSistema>> _registros = _consultar();

  Stream<List<RegistroSistema>> _consultar() =>
      _repo.watchAuditoria(_periodo.inicio, _periodo.fim);

  static final _json = JsonEncoder.withIndent(
    '  ',
    (o) => o is Timestamp ? o.toDate().toIso8601String() : '$o',
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: LarguraMaxima(
        largura: 900,
        child: StreamBuilder<List<Loja>>(
          stream: _lojas,
          builder: (context, lojasSnap) {
            final nomes = {
              for (final l in lojasSnap.data ?? const <Loja>[]) l.id: l.nome,
            };
            return StreamBuilder<List<RegistroSistema>>(
              stream: _registros,
              builder: (context, snap) {
                final registros = snap.data ?? const <RegistroSistema>[];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Row(
                      children: [
                        FiltroPeriodo(
                          periodo: _periodo,
                          onChanged: (p) => setState(() {
                            _periodo = p;
                            _registros = _consultar();
                          }),
                        ),
                        const SizedBox(width: 12),
                        if (snap.hasData)
                          Expanded(
                            child: Text(
                              '${registros.length} registro(s)',
                              style: t.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (snap.hasError)
                      Text('Erro: ${snap.error}')
                    else if (!snap.hasData)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (registros.isEmpty)
                      const EstadoVazio(
                        icone: Icons.manage_search,
                        titulo: 'Nenhum registro no período',
                      ),
                    for (final r in registros)
                      Card(
                        child: ExpansionTile(
                          shape: const Border(),
                          leading: const Icon(Icons.history),
                          title: Text(
                            r.descricao.isEmpty ? r.acao : r.descricao,
                          ),
                          subtitle: Text(
                            [
                              formatarDataHora(r.data),
                              if (r.email.isNotEmpty) r.email,
                              if (r.lojaId != null)
                                nomes[r.lojaId] ?? 'Loja ${r.lojaId}',
                            ].join(' · '),
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ação: ${r.acao}',
                              style: t.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            if (r.dados == null)
                              const Text('Sem dados adicionais.')
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: t.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  _json.convert(r.dados),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
