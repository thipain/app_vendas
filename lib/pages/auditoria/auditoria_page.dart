import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/auditoria_repository.dart';
import '../../models/registro_auditoria.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/seletor.dart';

/// Registro de acessos e operações sensíveis, somente leitura.
class AuditoriaPage extends StatefulWidget {
  const AuditoriaPage({super.key});

  @override
  State<AuditoriaPage> createState() => _AuditoriaPageState();
}

class _AuditoriaPageState extends State<AuditoriaPage> {
  late Periodo _periodo;
  late Stream<List<RegistroAuditoria>> _stream;
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _definir(Periodo.hoje());
  }

  void _definir(Periodo p) {
    _periodo = p;
    _stream = AuditoriaRepository().watchPeriodo(p.inicio, p.fim);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          LarguraMaxima(
            largura: 1000,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FiltroPeriodo(
                    periodo: _periodo,
                    onChanged: (p) => setState(() => _definir(p)),
                  ),
                  SizedBox(
                    width: 360,
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar por ação, descrição ou usuário',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          setState(() => _busca = normalizarBusca(v.trim())),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<RegistroAuditoria>>(
              stream: _stream,
              builder: (context, s) {
                if (s.hasError) {
                  return EstadoVazio(
                    icone: Icons.error_outline,
                    titulo: 'Não foi possível carregar a auditoria',
                    mensagem: '${s.error}',
                  );
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final lista = s.data!
                    .where(
                      (r) => normalizarBusca(
                        '${r.acao} ${r.descricao} ${r.usuarioNome}',
                      ).contains(_busca),
                    )
                    .toList();
                if (lista.isEmpty) {
                  return const EstadoVazio(
                    icone: Icons.policy_outlined,
                    titulo: 'Nenhum registro encontrado',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: lista.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return LarguraMaxima(
                        largura: 1000,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${lista.length} registro(s)'
                            '${s.data!.length >= 1000 ? ' (exibindo os 1000 mais recentes do período)' : ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      );
                    }
                    return LarguraMaxima(
                      largura: 1000,
                      child: _ItemAuditoria(lista[i - 1]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemAuditoria extends StatelessWidget {
  final RegistroAuditoria r;
  const _ItemAuditoria(this.r);

  static Object? _json(Object? v) => switch (v) {
    Timestamp t => DateFormat('dd/MM/yyyy HH:mm:ss').format(t.toDate()),
    DateTime d => DateFormat('dd/MM/yyyy HH:mm:ss').format(d),
    GeoPoint g => '${g.latitude}, ${g.longitude}',
    DocumentReference d => d.path,
    _ => v.toString(),
  };

  static String _formatar(Object? dados) {
    try {
      return const JsonEncoder.withIndent('  ', _json).convert(dados);
    } catch (_) {
      return '$dados';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final temDetalhes = r.antes != null || r.depois != null;
    final plataforma = r.plataforma.isEmpty ? '' : ' · ${r.plataforma}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        title: Text(r.descricao.isEmpty ? r.acao : r.descricao),
        subtitle: Text(
          '${DateFormat('dd/MM/yyyy HH:mm:ss').format(r.data)} · '
          '${r.usuarioNome.isEmpty ? 'Anônimo' : r.usuarioNome}$plataforma',
        ),
        trailing: Chip(
          label: Text(r.acao, style: t.textTheme.labelSmall),
          visualDensity: VisualDensity.compact,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ação: ${r.acao}'),
          if (r.entidade != null)
            Text(
              'Registro: ${r.entidade}'
              '${r.entidadeId == null ? '' : ' #${r.entidadeId}'}',
            ),
          if (r.plataforma.isNotEmpty) Text('Plataforma: ${r.plataforma}'),
          if (!temDetalhes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Sem dados adicionais.',
                style: TextStyle(color: t.colorScheme.outline),
              ),
            ),
          if (r.antes != null) _bloco(context, 'Antes', r.antes),
          if (r.depois != null) _bloco(context, 'Depois', r.depois),
        ],
      ),
    );
  }

  Widget _bloco(BuildContext context, String titulo, Object? dados) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: t.textTheme.titleSmall),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _formatar(dados),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
