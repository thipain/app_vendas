import 'package:flutter/material.dart';

import '../../core/imagem.dart';
import '../../core/regra_exception.dart';
import '../../data/config_repository.dart';
import '../../models/config_loja.dart';
import '../../widgets/foto_produto.dart';
import '../../widgets/largura_maxima.dart';
import '../../widgets/mensagens.dart';
import '../inicio/comum.dart';

/// Configurações da loja (somente administrador): identidade, dados do
/// comprovante, status exibido no topo, cores do tema e logo.
class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final _c = ConfigRepository.atual.value;
  late final _nomeLoja = TextEditingController(text: _c.nomeLoja);
  late final _nomeSistema = TextEditingController(text: _c.nomeSistema);
  late final _telefone = TextEditingController(text: _c.telefone);
  late final _documento = TextEditingController(text: _c.documento);
  late final _endereco = TextEditingController(text: _c.endereco);
  late final _mensagem = TextEditingController(text: _c.mensagemComprovante);
  late final _status = TextEditingController(text: _c.statusLoja);
  late final _corPrimaria = TextEditingController(
    text: ConfigLoja.corParaHex(_c.corPrimaria),
  );
  late final _corDestaque = TextEditingController(
    text: ConfigLoja.corParaHex(_c.corDestaque),
  );
  late String _logo = _c.logo;
  bool _carregandoLogo = false;

  @override
  void dispose() {
    for (final c in [
      _nomeLoja,
      _nomeSistema,
      _telefone,
      _documento,
      _endereco,
      _mensagem,
      _status,
      _corPrimaria,
      _corDestaque,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static Color? _lerCor(String texto) {
    final t = texto.trim();
    if (!_hex.hasMatch(t)) return null;
    return Color(0xFF000000 | int.parse(t.substring(1), radix: 16));
  }

  Future<void> _escolherLogo() async {
    setState(() => _carregandoLogo = true);
    try {
      final b64 = await escolherImagem(png: true, lado: 256);
      if (b64 != null && mounted) setState(() => _logo = b64);
    } on FormatException catch (e) {
      if (mounted) mostrarErro(context, RegraException(e.message));
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _carregandoLogo = false);
    }
  }

  void _salvar() {
    final nomeLoja = _nomeLoja.text.trim();
    final nomeSistema = _nomeSistema.text.trim();
    final mensagem = _mensagem.text.trim();
    final status = _status.text.trim();
    if (nomeLoja.isEmpty ||
        nomeSistema.isEmpty ||
        mensagem.isEmpty ||
        status.isEmpty) {
      mostrarErro(
        context,
        const RegraException('Preencha todos os campos obrigatórios.'),
      );
      return;
    }
    if (nomeLoja.length > 120 ||
        nomeSistema.length > 80 ||
        mensagem.length > 300 ||
        status.length > 60 ||
        _telefone.text.trim().length > 40 ||
        _documento.text.trim().length > 30 ||
        _endereco.text.trim().length > 255) {
      mostrarErro(
        context,
        const RegraException(
          'Um dos nomes informados ultrapassa o tamanho permitido.',
        ),
      );
      return;
    }
    final primaria = _lerCor(_corPrimaria.text);
    final destaque = _lerCor(_corDestaque.text);
    if (primaria == null || destaque == null) {
      mostrarErro(context, const RegraException('Selecione cores válidas.'));
      return;
    }
    final nova = ConfigLoja(
      nomeLoja: nomeLoja,
      nomeSistema: nomeSistema,
      telefone: _telefone.text.trim(),
      documento: _documento.text.trim(),
      endereco: _endereco.text.trim(),
      mensagemComprovante: mensagem,
      statusLoja: status,
      corPrimaria: primaria,
      corDestaque: destaque,
      logo: _logo,
    );
    executar(
      context,
      () => ConfigRepository.salvar(nova),
      sucesso: 'Configurações salvas e aplicadas em todo o sistema.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LarguraMaxima(
            largura: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TituloSecao('Identidade'),
                _cartao([
                  _campo(_nomeLoja, 'Nome da adega *', 120),
                  _campo(_nomeSistema, 'Nome do sistema *', 80),
                  _campo(
                    _status,
                    'Status exibido no topo *',
                    60,
                    ajuda: 'Texto livre, ex.: "Loja aberta".',
                  ),
                ]),
                const TituloSecao('Comprovante e notas'),
                _cartao([
                  _campo(
                    _telefone,
                    'Telefone / WhatsApp',
                    40,
                    teclado: TextInputType.phone,
                  ),
                  _campo(_documento, 'CPF / CNPJ', 30),
                  _campo(_endereco, 'Endereço', 255),
                  _campo(_mensagem, 'Mensagem no rodapé *', 300, linhas: 3),
                ]),
                const TituloSecao('Cores'),
                _cartao([
                  _CampoCor(rotulo: 'Cor principal', controller: _corPrimaria),
                  const SizedBox(height: 16),
                  _CampoCor(
                    rotulo: 'Cor de destaque',
                    controller: _corDestaque,
                  ),
                ]),
                const TituloSecao('Logo'),
                _cartao([
                  Row(
                    children: [
                      ListenableBuilder(
                        listenable: _nomeLoja,
                        builder: (_, _) => FotoProduto(
                          foto: _logo,
                          nome: _nomeLoja.text.isEmpty ? 'A' : _nomeLoja.text,
                          tamanho: 72,
                          raio: 14,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              icon: _carregandoLogo
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.image_outlined),
                              label: Text(
                                _logo.isEmpty ? 'Escolher logo' : 'Trocar logo',
                              ),
                              onPressed: _carregandoLogo ? null : _escolherLogo,
                            ),
                            if (_logo.isNotEmpty)
                              TextButton.icon(
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Remover a logo'),
                                onPressed: () => setState(() => _logo = ''),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aparece no menu, no login, nos comprovantes e nas notas. '
                    'Sem logo, é exibida a inicial do nome da adega.',
                    style: t.textTheme.bodySmall,
                  ),
                ]),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar configurações'),
                  onPressed: _salvar,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartao(List<Widget> filhos) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: filhos,
      ),
    ),
  );

  Widget _campo(
    TextEditingController c,
    String rotulo,
    int maximo, {
    int linhas = 1,
    String? ajuda,
    TextInputType? teclado,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: TextField(
      controller: c,
      maxLength: maximo,
      minLines: linhas,
      maxLines: linhas == 1 ? 1 : linhas + 3,
      keyboardType: linhas > 1 ? TextInputType.multiline : teclado,
      decoration: InputDecoration(labelText: rotulo, helperText: ajuda),
    ),
  );
}

/// Paleta de cores prontas + campo hexadecimal (#rrggbb).
class _CampoCor extends StatelessWidget {
  final String rotulo;
  final TextEditingController controller;

  const _CampoCor({required this.rotulo, required this.controller});

  static const _paleta = [
    '#173f2d',
    '#d8ed87',
    '#1b5e20',
    '#2e7d32',
    '#00695c',
    '#0277bd',
    '#1565c0',
    '#283593',
    '#4527a0',
    '#6a1b9a',
    '#ad1457',
    '#c62828',
    '#d84315',
    '#ef6c00',
    '#f9a825',
    '#fdd835',
    '#9e9d24',
    '#4e342e',
    '#37474f',
    '#212121',
    '#ffffff',
    '#ffe0b2',
    '#b3e5fc',
    '#f8bbd0',
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final atual = _ConfiguracoesPageState._lerCor(controller.text);
        final selecionada = controller.text.trim().toLowerCase();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rotulo, style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in _paleta)
                  Tooltip(
                    message: hex,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => controller.text = hex,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _ConfiguracoesPageState._lerCor(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selecionada == hex
                                ? t.colorScheme.onSurface
                                : t.colorScheme.outlineVariant,
                            width: selecionada == hex ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: atual ?? Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.colorScheme.outlineVariant),
                  ),
                  child: atual == null
                      ? Icon(Icons.close, color: t.colorScheme.error)
                      : null,
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: controller,
                    maxLength: 7,
                    decoration: InputDecoration(
                      labelText: 'Hexadecimal',
                      hintText: '#rrggbb',
                      counterText: '',
                      errorText: atual == null ? 'Use o formato #rrggbb' : null,
                    ),
                    onChanged: (v) {
                      final minusculo = v.toLowerCase();
                      if (minusculo != v) {
                        controller.value = controller.value.copyWith(
                          text: minusculo,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
