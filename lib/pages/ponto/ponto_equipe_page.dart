import 'package:flutter/material.dart';

import '../../data/config_repository.dart';
import '../../data/dados.dart';
import '../../data/ponto_repository.dart';
import '../../models/registro_ponto.dart';
import '../../models/usuario.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../inicio/comum.dart';
import 'painel_ponto.dart';

/// Ponto da equipe: o gestor registra o próprio ponto e acompanha os
/// registros de todos, com filtro de datas e de funcionário.
class PontoEquipePage extends StatefulWidget {
  const PontoEquipePage({super.key});

  @override
  State<PontoEquipePage> createState() => _PontoEquipePageState();
}

class _PontoEquipePageState extends State<PontoEquipePage> {
  late Periodo _periodo;
  late Stream<List<RegistroPonto>> _stream;
  String? _usuarioId;

  @override
  void initState() {
    super.initState();
    _definir(Periodo.hoje());
  }

  void _definir(Periodo p) {
    _periodo = p;
    _stream = PontoRepository().watchPeriodo(p.inicio, p.fim);
  }

  bool get _ehHoje {
    final h = Periodo.hoje();
    return _periodo.inicio == h.inicio && _periodo.ultimoDia == h.ultimoDia;
  }

  @override
  Widget build(BuildContext context) {
    final loja = ConfigRepository.atual.value.nomeLoja;
    final titulo = _ehHoje
        ? 'Registros de hoje — Equipe da $loja'
        : 'Registros de ${_periodo.descricao} — Equipe da $loja';
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LarguraMaxima(
            largura: 900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PainelPonto(
                  onNovoDia: () {
                    // Ao virar o dia, quem estava vendo "hoje" passa ao novo dia.
                    final ontem = DateTime.now().subtract(
                      const Duration(days: 1),
                    );
                    if (_periodo.contem(ontem) &&
                        _periodo.inicio == _periodo.ultimoDia) {
                      setState(() => _definir(Periodo.hoje()));
                    }
                  },
                ),
                TituloSecao(titulo),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FiltroPeriodo(
                      periodo: _periodo,
                      onChanged: (p) => setState(() => _definir(p)),
                    ),
                    if (!_ehHoje)
                      TextButton(
                        onPressed: () =>
                            setState(() => _definir(Periodo.hoje())),
                        child: const Text('Hoje'),
                      ),
                    ValueListenableBuilder<List<Usuario>>(
                      valueListenable: Dados.equipe,
                      builder: (context, equipe, _) => SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<String?>(
                          initialValue: _usuarioId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Funcionário',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Toda a equipe'),
                            ),
                            for (final u in equipe)
                              DropdownMenuItem(
                                value: u.id,
                                child: Text(
                                  u.ativo ? u.nome : '${u.nome} (bloqueado)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _usuarioId = v),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<RegistroPonto>>(
                  stream: _stream,
                  builder: (context, s) {
                    if (s.hasError) {
                      return EstadoVazio(
                        icone: Icons.error_outline,
                        titulo: 'Não foi possível carregar os registros',
                        mensagem: '${s.error}',
                      );
                    }
                    if (!s.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final lista = _usuarioId == null
                        ? s.data!
                        : s.data!
                              .where((r) => r.usuarioId == _usuarioId)
                              .toList();
                    if (lista.isEmpty) {
                      return const EstadoVazio(
                        icone: Icons.badge_outlined,
                        titulo: 'Nenhum registro no período',
                      );
                    }
                    return Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${lista.length} registro(s)',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                          for (final r in lista)
                            ItemPonto(registro: r, mostrarNome: true),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
