import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/sistema_repository.dart';
import '../../models/loja.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../inicio/comum.dart';
import 'admin_comum.dart';

/// Avisos do dono do sistema exibidos no app das lojas.
class AvisosPage extends StatefulWidget {
  const AvisosPage({super.key});

  @override
  State<AvisosPage> createState() => _AvisosPageState();
}

class _AvisosPageState extends State<AvisosPage> {
  final _repo = SistemaRepository();
  late final Stream<List<Aviso>> _avisos = _repo.watchAvisos();
  late final StreamSubscription<List<Loja>> _sub;
  List<Loja> _lojas = const [];

  @override
  void initState() {
    super.initState();
    _sub = _repo.watchLojas().listen((l) => _lojas = l, onError: (Object _) {});
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _novo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogAviso(lojas: _lojas),
    );
    if (ok == true && mounted) avisar(context, 'Aviso publicado.');
  }

  Future<void> _alternar(Aviso a) => executarComProgresso(
    context,
    () => _repo.definirAvisoAtivo(a, !a.ativo),
    sucesso: a.ativo ? 'Aviso encerrado.' : 'Aviso reativado.',
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novo,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Novo aviso'),
      ),
      body: LarguraMaxima(
        largura: 900,
        child: StreamBuilder<List<Aviso>>(
          stream: _avisos,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Erro: ${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final avisos = snap.data!;
            if (avisos.isEmpty) {
              return const EstadoVazio(
                icone: Icons.campaign_outlined,
                titulo: 'Nenhum aviso publicado',
                mensagem:
                    'Avisos aparecem no app das lojas (todas ou uma '
                    'específica).',
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                for (final a in avisos)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  a.titulo,
                                  style: t.textTheme.titleMedium,
                                ),
                              ),
                              Selo(
                                a.ativo ? 'Ativo' : 'Encerrado',
                                positivo: a.ativo,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(a.mensagem),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                a.lojaId == null
                                    ? Icons.public
                                    : Icons.storefront_outlined,
                                size: 16,
                                color: t.colorScheme.outline,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${a.lojaId == null ? 'Todas as lojas' : (a.lojaNome ?? 'Loja')}'
                                  ' · ${formatarDataHora(a.criadoEm)}',
                                  style: t.textTheme.bodySmall,
                                ),
                              ),
                              TextButton(
                                onPressed: () => _alternar(a),
                                child: Text(a.ativo ? 'Encerrar' : 'Reativar'),
                              ),
                            ],
                          ),
                        ],
                      ),
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

class _DialogAviso extends StatefulWidget {
  final List<Loja> lojas;

  const _DialogAviso({required this.lojas});

  @override
  State<_DialogAviso> createState() => _DialogAvisoState();
}

class _DialogAvisoState extends State<_DialogAviso> {
  final _form = GlobalKey<FormState>();
  final _titulo = TextEditingController();
  final _mensagem = TextEditingController();

  /// null = todas as lojas.
  String? _lojaId;
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _titulo.dispose();
    _mensagem.dispose();
    super.dispose();
  }

  Future<void> _publicar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await SistemaRepository().publicarAviso(
        titulo: _titulo.text,
        mensagem: _mensagem.text,
        loja: widget.lojas.where((l) => l.id == _lojaId).firstOrNull,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = textoErro(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo aviso'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titulo,
                  autofocus: true,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Título'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Informe o título' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _mensagem,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Mensagem',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Informe a mensagem' : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _lojaId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Destino'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todas as lojas'),
                    ),
                    for (final l in widget.lojas)
                      DropdownMenuItem<String?>(
                        value: l.id,
                        child: Text(l.nome, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _lojaId = v),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _erro!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvando ? null : _publicar,
          child: Text(_salvando ? 'Publicando...' : 'Publicar'),
        ),
      ],
    );
  }
}
