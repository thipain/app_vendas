import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/regra_exception.dart';
import '../models/loja.dart';
import '../models/usuario.dart';
import 'banco.dart';
import 'usuario_repository.dart';

/// Administração do sistema multiloja: lojas, donos e migração.
class SistemaRepository {
  final _db = Banco.db;

  CollectionReference<Map<String, dynamic>> get _auditoria =>
      _db.collection('auditoriaSistema');

  /// Coleções de cada loja (usadas na migração da versão anterior).
  static const colecoesDaLoja = [
    'produtos',
    'clientes',
    'vendas',
    'caixas',
    'movimentosCaixa',
    'comandas',
    'movimentosEstoque',
    'notasEntrada',
    'receitas',
    'operacoesEstoque',
    'retiradas',
    'ponto',
    'auditoria',
  ];

  Stream<Sistema> watchSistema() => Banco.sistema
      .snapshots(includeMetadataChanges: true)
      .where((s) => s.exists || !s.metadata.isFromCache)
      .map(Sistema.fromDoc);

  /// Lojas em que o usuário é membro (consulta em todas as lojas).
  Stream<List<Vinculo>> watchVinculos(String uid) => _db
      .collectionGroup('membros')
      .where('uid', isEqualTo: uid)
      .snapshots(includeMetadataChanges: true)
      .where((s) => s.docs.isNotEmpty || !s.metadata.isFromCache)
      .map(
        (s) =>
            s.docs.map(Vinculo.fromDoc).toList()
              ..sort((a, b) => a.lojaNome.compareTo(b.lojaNome)),
      );

  /// Todas as lojas (somente o dono do sistema consegue ler).
  Stream<List<Loja>> watchLojas() => Banco.lojas.snapshots().map(
    (s) => s.docs.map(Loja.fromDoc).toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase())),
  );

  Stream<Loja?> watchLoja(String id) => Banco.lojas
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Loja.fromDoc(d) : null);

  void _registrar(
    WriteBatch batch,
    String acao,
    String descricao, {
    String? lojaId,
    Object? dados,
  }) {
    final eu = FirebaseAuth.instance.currentUser;
    batch.set(_auditoria.doc(), {
      'acao': acao,
      'descricao': descricao,
      'lojaId': lojaId,
      'dados': dados,
      'usuario': {'uid': eu?.uid, 'email': eu?.email},
      'data': Timestamp.now(),
    });
  }

  static String _validarNomeLoja(String nome) {
    final n = nome.trim();
    if (n.isEmpty || n.length > 120) {
      throw const RegraException(
        'Informe o nome da loja (até 120 caracteres).',
      );
    }
    return n;
  }

  /// Primeiro acesso de uma instalação nova: cria o sistema, a primeira loja
  /// e torna a conta logada dona do sistema e administradora da loja.
  Future<String> configurarSistema({
    required String nomeLoja,
    required String nome,
  }) async {
    final conta = FirebaseAuth.instance.currentUser!;
    final n = _validarNomeLoja(nomeLoja);
    final loja = Banco.lojas.doc();
    final batch = _db.batch();
    batch.set(Banco.sistema, {
      'adminInicial': conta.uid,
      'superAdmins': [conta.uid],
      'configuradoEm': FieldValue.serverTimestamp(),
    });
    batch.set(loja, {
      'nome': n,
      'ativa': true,
      'criadaEm': FieldValue.serverTimestamp(),
    });
    final usuario = Usuario(
      id: conta.uid,
      nome: nome.trim(),
      email: (conta.email ?? '').toLowerCase(),
      papel: Usuario.papelAdmin,
    );
    batch.set(UsuarioRepository.membrosDa(loja.id).doc(conta.uid), {
      ...UsuarioRepository.dadosMembro(usuario, loja.id, n),
      'criadoEm': FieldValue.serverTimestamp(),
    });
    batch.set(Banco.contas.doc(usuario.email), {
      'uid': conta.uid,
      'nome': usuario.nome,
    });
    await batch.commit();
    return loja.id;
  }

  /// Cadastra uma loja e o administrador dela (conta nova ou já existente).
  /// Precisa de internet.
  Future<String> criarLoja({
    required String nomeLoja,
    required String nomeAdmin,
    required String emailAdmin,
    required String senhaAdmin,
    Loja? cadastro,
    int diasTeste = 0,
  }) async {
    final n = _validarNomeLoja(nomeLoja);
    final conta = await UsuarioRepository.obterOuCriarConta(
      nome: nomeAdmin,
      email: emailAdmin,
      senha: senhaAdmin,
    );
    final loja = Banco.lojas.doc();
    final admin = Usuario(
      id: conta.uid,
      nome: nomeAdmin.trim(),
      email: emailAdmin.trim().toLowerCase(),
      papel: Usuario.papelAdmin,
    );
    final hoje = DateTime.now();
    final dados = (cadastro ?? Loja(id: loja.id, nome: n)).copyWith(
      nome: n,
      emTeste: diasTeste > 0,
      pagoAte: diasTeste > 0
          ? DateTime(hoje.year, hoje.month, hoje.day + diasTeste)
          : null,
    );
    final batch = _db.batch();
    batch.set(loja, {
      ...dados.dadosCadastro(),
      'ativa': true,
      'criadaEm': FieldValue.serverTimestamp(),
    });
    batch.set(UsuarioRepository.membrosDa(loja.id).doc(conta.uid), {
      ...UsuarioRepository.dadosMembro(admin, loja.id, n),
      'criadoEm': FieldValue.serverTimestamp(),
    });
    _registrar(
      batch,
      'store.create',
      'Loja cadastrada',
      lojaId: loja.id,
      dados: {'nome': n, 'admin': admin.email, 'contaExistente': !conta.nova},
    );
    await batch.commit();
    return loja.id;
  }

  /// Adiciona outro administrador a uma loja (ex.: o dono de duas lojas).
  Future<void> adicionarAdministrador(
    Loja loja, {
    required String nome,
    required String email,
    required String senha,
  }) async {
    final conta = await UsuarioRepository.obterOuCriarConta(
      nome: nome,
      email: email,
      senha: senha,
    );
    final ref = UsuarioRepository.membrosDa(loja.id).doc(conta.uid);
    final atual = await ref.get(const GetOptions(source: Source.server));
    final admin = Usuario(
      id: conta.uid,
      nome: nome.trim(),
      email: email.trim().toLowerCase(),
      papel: Usuario.papelAdmin,
    );
    final batch = _db.batch();
    if (atual.exists) {
      batch.update(ref, {'papel': Usuario.papelAdmin, 'ativo': true});
    } else {
      batch.set(ref, {
        ...UsuarioRepository.dadosMembro(admin, loja.id, loja.nome),
        'criadoEm': FieldValue.serverTimestamp(),
      });
    }
    _registrar(
      batch,
      'store.admin_add',
      'Administrador adicionado à loja',
      lojaId: loja.id,
      dados: {'email': admin.email},
    );
    await batch.commit();
  }

  Future<void> renomearLoja(Loja loja, String nome) async {
    final n = _validarNomeLoja(nome);
    final batch = _db.batch();
    batch.update(Banco.lojas.doc(loja.id), {'nome': n});
    _registrar(
      batch,
      'store.rename',
      'Loja renomeada',
      lojaId: loja.id,
      dados: {'antes': loja.nome, 'depois': n},
    );
    await batch.commit();
  }

  /// Bloqueia ou libera o acesso de toda a equipe da loja.
  Future<void> definirAtiva(Loja loja, bool ativa) async {
    final batch = _db.batch();
    batch.update(Banco.lojas.doc(loja.id), {
      'ativa': ativa,
      'travadaEm': ativa ? null : FieldValue.serverTimestamp(),
    });
    _registrar(
      batch,
      ativa ? 'store.unblock' : 'store.block',
      ativa ? 'Loja liberada' : 'Loja travada',
      lojaId: loja.id,
    );
    await batch.commit();
  }

  CollectionReference<Map<String, dynamic>> get _pagamentos =>
      _db.collection('pagamentosLojas');
  CollectionReference<Map<String, dynamic>> get _avisos =>
      _db.collection('avisos');

  /// Altera os dados cadastrais e de cobrança da loja.
  Future<void> salvarCadastro(Loja antes, Loja depois) async {
    _validarNomeLoja(depois.nome);
    if (depois.valorMensal < 0 || depois.carenciaDias < 0) {
      throw const RegraException('Informe valores válidos.');
    }
    final batch = _db.batch();
    batch.update(Banco.lojas.doc(antes.id), depois.dadosCadastro());
    _registrar(
      batch,
      'store.update',
      'Cadastro da loja alterado',
      lojaId: antes.id,
      dados: {'antes': _resumo(antes), 'depois': _resumo(depois)},
    );
    await batch.commit();
  }

  static Map<String, dynamic> _resumo(Loja l) => {
    'nome': l.nome,
    'valorMensal': l.valorMensal,
    'pagoAte': l.pagoAte?.toIso8601String(),
    'carenciaDias': l.carenciaDias,
    'emTeste': l.emTeste,
  };

  /// Registra o pagamento de [meses] mensalidades e avança o vencimento.
  /// O primeiro pagamento encerra o período de teste.
  Future<DateTime> registrarPagamento(
    Loja loja, {
    required double valor,
    required int meses,
    required DateTime data,
    required String forma,
    String observacao = '',
  }) async {
    if (valor < 0) throw const RegraException('Informe um valor válido.');
    if (meses < 1 || meses > 24) {
      throw const RegraException('Informe de 1 a 24 meses.');
    }
    final novo = proximoVencimento(loja.emTeste ? null : loja.pagoAte, meses);
    final batch = _db.batch();
    batch.set(_pagamentos.doc(), {
      'lojaId': loja.id,
      'lojaNome': loja.nome,
      'valor': valor,
      'meses': meses,
      'data': Timestamp.fromDate(data),
      'forma': forma,
      'observacao': observacao.trim(),
      'vencimentoAnterior': loja.pagoAte == null
          ? null
          : Timestamp.fromDate(loja.pagoAte!),
      'novoVencimento': Timestamp.fromDate(novo),
      'registradoEm': FieldValue.serverTimestamp(),
    });
    batch.update(Banco.lojas.doc(loja.id), {
      'pagoAte': Timestamp.fromDate(novo),
      'emTeste': false,
    });
    _registrar(
      batch,
      'store.payment',
      'Pagamento registrado',
      lojaId: loja.id,
      dados: {
        'valor': valor,
        'meses': meses,
        'novoVencimento': novo.toIso8601String(),
      },
    );
    await batch.commit();
    return novo;
  }

  Stream<List<PagamentoLoja>> watchPagamentos(DateTime inicio, DateTime fim) =>
      _pagamentos
          .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
          .where('data', isLessThan: Timestamp.fromDate(fim))
          .orderBy('data', descending: true)
          .snapshots()
          .map((s) => s.docs.map(PagamentoLoja.fromDoc).toList());

  Stream<List<PagamentoLoja>> watchPagamentosDaLoja(String lojaId) =>
      _pagamentos
          .where('lojaId', isEqualTo: lojaId)
          .snapshots()
          .map(
            (s) =>
                s.docs.map(PagamentoLoja.fromDoc).toList()
                  ..sort((a, b) => b.data.compareTo(a.data)),
          );

  /// Avisos ativos (para as lojas) ou todos (para o painel).
  Stream<List<Aviso>> watchAvisos({bool somenteAtivos = false}) {
    Query<Map<String, dynamic>> q = _avisos;
    if (somenteAtivos) q = q.where('ativo', isEqualTo: true);
    return q.snapshots().map(
      (s) =>
          s.docs.map(Aviso.fromDoc).toList()
            ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm)),
    );
  }

  Future<void> publicarAviso({
    required String titulo,
    required String mensagem,
    Loja? loja,
  }) async {
    if (titulo.trim().isEmpty || mensagem.trim().isEmpty) {
      throw const RegraException('Informe o título e a mensagem do aviso.');
    }
    final batch = _db.batch();
    final ref = _avisos.doc();
    batch.set(ref, {
      'titulo': titulo.trim(),
      'mensagem': mensagem.trim(),
      'lojaId': loja?.id,
      'lojaNome': loja?.nome,
      'ativo': true,
      'criadoEm': Timestamp.now(),
    });
    _registrar(
      batch,
      'notice.create',
      'Aviso publicado',
      lojaId: loja?.id,
      dados: {'titulo': titulo.trim()},
    );
    await batch.commit();
  }

  Future<void> definirAvisoAtivo(Aviso aviso, bool ativo) async {
    final batch = _db.batch();
    batch.update(_avisos.doc(aviso.id), {'ativo': ativo});
    _registrar(
      batch,
      ativo ? 'notice.enable' : 'notice.disable',
      ativo ? 'Aviso reativado' : 'Aviso encerrado',
      lojaId: aviso.lojaId,
      dados: {'titulo': aviso.titulo},
    );
    await batch.commit();
  }

  Stream<List<RegistroSistema>> watchAuditoria(DateTime inicio, DateTime fim) =>
      _auditoria
          .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
          .where('data', isLessThan: Timestamp.fromDate(fim))
          .orderBy('data', descending: true)
          .limit(1000)
          .snapshots()
          .map((s) => s.docs.map(RegistroSistema.fromDoc).toList());

  /// true quando ainda há dados da versão anterior (sem lojas) para migrar.
  Future<bool> temDadosAntigos(Sistema sistema) async {
    if (sistema.migradoPara != null) return false;
    for (final c in ['produtos', 'vendas', 'usuarios']) {
      final s = await _db
          .collection(c)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (s.docs.isNotEmpty) return true;
    }
    return false;
  }

  /// Cria a loja [nomeLoja] e copia para ela os dados da versão anterior
  /// (coleções na raiz do banco). Os originais ficam intactos como cópia de
  /// segurança. A conta logada (dono do sistema) vira administradora da loja.
  Future<String> migrarDadosAntigos(
    String nomeLoja, {
    void Function(String etapa)? progresso,
  }) async {
    final n = _validarNomeLoja(nomeLoja);
    final conta = FirebaseAuth.instance.currentUser!;
    final lojaRef = Banco.lojas.doc();
    final destino = Loja(id: lojaRef.id, nome: n);
    progresso?.call('Criando a loja...');
    await lojaRef.set({
      'nome': n,
      'ativa': true,
      'criadaEm': FieldValue.serverTimestamp(),
    });
    var batch = _db.batch();
    var operacoes = 0;
    Future<void> gravar(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> d,
    ) async {
      batch.set(ref, d);
      if (++operacoes >= 400) {
        await batch.commit();
        batch = _db.batch();
        operacoes = 0;
      }
    }

    for (final c in colecoesDaLoja) {
      progresso?.call('Copiando $c...');
      final docs = await _db
          .collection(c)
          .get(const GetOptions(source: Source.server));
      for (final d in docs.docs) {
        await gravar(lojaRef.collection(c).doc(d.id), d.data());
      }
    }

    progresso?.call('Copiando configurações da loja...');
    final config = await _db
        .collection('config')
        .doc('loja')
        .get(const GetOptions(source: Source.server));
    if (config.exists) {
      await gravar(lojaRef.collection('config').doc('loja'), config.data()!);
    }

    progresso?.call('Copiando equipe...');
    final usuarios = await _db
        .collection('usuarios')
        .get(const GetOptions(source: Source.server));
    if (!usuarios.docs.any((d) => d.id == conta.uid)) {
      final eu = Usuario(
        id: conta.uid,
        nome: conta.email ?? 'Administrador',
        email: (conta.email ?? '').toLowerCase(),
        papel: Usuario.papelAdmin,
      );
      await gravar(
        UsuarioRepository.membrosDa(destino.id).doc(conta.uid),
        UsuarioRepository.dadosMembro(eu, destino.id, destino.nome),
      );
      await gravar(Banco.contas.doc(eu.email), {'uid': eu.id, 'nome': eu.nome});
    }
    for (final d in usuarios.docs) {
      final u = Usuario.fromDoc(d);
      await gravar(UsuarioRepository.membrosDa(destino.id).doc(u.id), {
        ...d.data(),
        ...UsuarioRepository.dadosMembro(u, destino.id, destino.nome),
      });
      if (u.email.isNotEmpty) {
        await gravar(Banco.contas.doc(u.email.toLowerCase()), {
          'uid': u.id,
          'nome': u.nome,
        });
      }
    }

    batch.update(Banco.sistema, {'migradoPara': destino.id});
    _registrar(
      batch,
      'store.migrate',
      'Dados da versão anterior migrados',
      lojaId: destino.id,
    );
    await batch.commit();
    return destino.id;
  }

  /// Nome da loja na versão anterior (para sugerir na migração).
  Future<String> nomeLojaAntiga() async {
    try {
      final d = await _db
          .collection('config')
          .doc('loja')
          .get(const GetOptions(source: Source.server));
      return d.data()?['nomeLoja'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }
}
