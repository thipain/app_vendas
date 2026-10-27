import 'package:flutter/material.dart';

import '../../core/sessao.dart';
import '../../data/ponto_repository.dart';
import '../../models/registro_ponto.dart';
import '../../widgets/filtro_periodo.dart';
import '../../widgets/largura_maxima.dart';
import '../inicio/comum.dart';
import 'painel_ponto.dart';

/// Registro de ponto do próprio funcionário e os registros dele hoje.
class MeuPontoPage extends StatefulWidget {
  const MeuPontoPage({super.key});

  @override
  State<MeuPontoPage> createState() => _MeuPontoPageState();
}

class _MeuPontoPageState extends State<MeuPontoPage> {
  late Stream<List<RegistroPonto>> _hoje;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    final p = Periodo.hoje();
    _hoje = PontoRepository().watchPeriodo(p.inicio, p.fim);
  }

  @override
  Widget build(BuildContext context) {
    final uid = Sessao.instancia.atual.id;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LarguraMaxima(
            largura: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PainelPonto(onNovoDia: () => setState(_carregar)),
                const TituloSecao('Meus registros de hoje'),
                StreamBuilder<List<RegistroPonto>>(
                  stream: _hoje,
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
                    final meus = s.data!
                        .where((r) => r.usuarioId == uid)
                        .toList();
                    if (meus.isEmpty) {
                      return const EstadoVazio(
                        icone: Icons.fingerprint,
                        titulo: 'Nenhum registro hoje',
                      );
                    }
                    return Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final r in meus) ItemPonto(registro: r),
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
