import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/permissoes.dart';
import '../core/regra_exception.dart';
import '../core/sessao.dart';
import '../models/loja.dart';
import '../models/usuario.dart';
import 'auditoria_repository.dart';
import 'banco.dart';
import 'offline.dart';

/// Equipe da loja em uso: perfis, permissões e contas de acesso.
///
/// Cada pessoa tem uma conta no Firebase Authentication (uma só, mesmo que
/// trabalhe em várias lojas) e um documento de membro em cada loja:
/// lojas/{lojaId}/membros/{uid}.
class UsuarioRepository {
  static CollectionReference<Map<String, dynamic>> membrosDa(String lojaId) =>
      Banco.lojas.doc(lojaId).collection('membros');

  static CollectionReference<Map<String, dynamic>> get _col =>
      membrosDa(Banco.lojaId);

  Stream<Usuario?> watch(String uid) => _col
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? Usuario.fromDoc(d) : null);

  Stream<List<Usuario>> watchTodos() => _col
      .orderBy('nomeBusca')
      .snapshots()
      .map((s) => s.docs.map(Usuario.fromDoc).toList());

  /// Dados do documento de membro de [usuario] na loja indicada.
  static Map<String, dynamic> dadosMembro(
    Usuario usuario,
    String lojaId,
    String lojaNome,
  ) => {
    ...usuario.toMap(),
    'uid': usuario.id,
    'lojaId': lojaId,
    'lojaNome': lojaNome,
  };

  /// Devolve o uid da conta com este e-mail para vincular à loja [lojaId],
  /// criando a conta se ainda não existir. Precisa de internet.
  ///
  /// Um e-mail só pode estar em uma loja ativa por vez: se a conta já está
  /// vinculada a outra loja que ainda existe, o cadastro é recusado. Contas de
  /// lojas excluídas ficam livres e são reaproveitadas (com a senha antiga:
  /// por isso [nova] = false avisa a tela para oferecer o link de nova senha).
  ///
  /// A conta é criada numa segunda instância do Firebase para não deslogar
  /// quem está cadastrando (criar uma conta pelo SDK faz login nela).
  static Future<({String uid, bool nova})> obterOuCriarConta({
    required String nome,
    required String email,
    required String senha,
    required String lojaId,
    required String lojaNome,
  }) async {
    final chave = email.trim().toLowerCase();
    final ref = Banco.contas.doc(chave);
    final existente = await ref.get(const GetOptions(source: Source.server));
    final dados = existente.data();
    final uidExistente = dados?['uid'] as String?;
    if (uidExistente != null) {
      final outra = dados!['lojaId'] as String?;
      if (outra != null && outra != lojaId && await _lojaExiste(outra)) {
        throw RegraException(
          'Este e-mail já está em uso na loja '
          '${dados['lojaNome'] ?? 'de outro cliente'}. Um e-mail só pode '
          'estar em uma loja ativa por vez: use outro e-mail.',
        );
      }
      if (outra != lojaId) {
        await ref.update({'lojaId': lojaId, 'lojaNome': lojaNome});
      }
      return (uid: uidExistente, nova: false);
    }

    final app = await Firebase.initializeApp(
      name: 'cadastro-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    try {
      final cred = await FirebaseAuth.instanceFor(app: app)
          .createUserWithEmailAndPassword(email: chave, password: senha);
      final uid = cred.user!.uid;
      await ref.set({
        'uid': uid,
        'nome': nome,
        'lojaId': lojaId,
        'lojaNome': lojaNome,
        'criadoEm': FieldValue.serverTimestamp(),
      });
      return (uid: uid, nova: true);
    } finally {
      await app.delete();
    }
  }

  /// A loja ainda existe? Sem permissão para ler (loja de outro cliente),
  /// considera que existe.
  static Future<bool> _lojaExiste(String lojaId) async {
    try {
      final d = await Banco.lojas
          .doc(lojaId)
          .get(const GetOptions(source: Source.server));
      return d.exists;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return true;
      rethrow;
    }
  }

  /// Envia o e-mail (em português) com o link para criar uma nova senha.
  static Future<void> enviarLinkNovaSenha(String email) async {
    await FirebaseAuth.instance.setLanguageCode('pt');
    await FirebaseAuth.instance.sendPasswordResetEmail(
      email: email.trim().toLowerCase(),
    );
  }

  /// Mensagem quando o plano da loja não comporta mais um usuário ativo
  /// (null = cabe). O dono do sistema não conta, porque não é membro.
  static String? motivoLimite(Loja? loja, List<Usuario> equipe) {
    if (loja == null) return null;
    final ativos = equipe.where((u) => u.ativo).length;
    if (loja.cabeUsuario(ativos)) return null;
    return 'O plano ${loja.plano.rotulo} permite ${loja.plano.descricaoLimite} '
        'ativos e a loja já tem $ativos. Bloqueie um funcionário ou fale com '
        'o suporte para mudar para o plano Completo.';
  }

  static void _validarLimite(List<Usuario> equipe) {
    final motivo = motivoLimite(Sessao.instancia.loja, equipe);
    if (motivo != null) throw RegraException(motivo);
  }

  /// Cadastra um funcionário na loja em uso. Se a pessoa já tem conta (em
  /// outra loja), ela é apenas vinculada e continua com a mesma senha.
  /// Retorna true quando a pessoa já tinha conta (a senha informada é
  /// ignorada e ela continua com a senha antiga).
  Future<bool> criar({
    required String nome,
    required String email,
    required String senha,
    required String papel,
    required Set<String> permissoes,
    required String lojaNome,
    required List<Usuario> equipe,
  }) async {
    _validarLimite(equipe);
    final conta = await obterOuCriarConta(
      nome: nome,
      email: email,
      senha: senha,
      lojaId: Banco.lojaId,
      lojaNome: lojaNome,
    );
    final ref = _col.doc(conta.uid);
    final atual = await ref.get(const GetOptions(source: Source.server));
    if (atual.exists) {
      throw const RegraException('Este e-mail já está cadastrado.');
    }
    final usuario = Usuario(
      id: conta.uid,
      nome: nome,
      email: email.trim().toLowerCase(),
      papel: papel,
      permissoes: Permissao.normalizar(permissoes),
    );
    final batch = Banco.db.batch();
    batch.set(ref, {
      ...dadosMembro(usuario, Banco.lojaId, lojaNome),
      'criadoEm': FieldValue.serverTimestamp(),
    });
    AuditoriaRepository.noBatch(
      batch,
      'user.create',
      'Funcionário cadastrado',
      entidade: 'usuario',
      entidadeId: usuario.id,
      depois: {...usuario.toMap(), 'contaExistente': !conta.nova},
    );
    await batch.commit();
    return !conta.nova;
  }

  /// Altera nome, papel, status ou permissões, protegendo o último admin.
  Future<void> salvar(
    Usuario antes,
    Usuario depois, {
    required List<Usuario> equipe,
  }) async {
    if (!antes.ativo && depois.ativo) _validarLimite(equipe);
    final perdeAdmin =
        antes.isAdmin && antes.ativo && (!depois.isAdmin || !depois.ativo);
    if (perdeAdmin &&
        equipe.where((u) => u.isAdmin && u.ativo && u.id != antes.id).isEmpty) {
      throw StateError(
        'Não é possível remover ou bloquear o último administrador ativo.',
      );
    }
    final normalizado = depois.copyWith(
      permissoes: Permissao.normalizar(depois.permissoes),
    );
    final batch = Banco.db.batch();
    batch.update(_col.doc(antes.id), {
      ...normalizado.toMap(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
    AuditoriaRepository.noBatch(
      batch,
      'user.update',
      'Funcionário alterado',
      entidade: 'usuario',
      entidadeId: antes.id,
      antes: antes.toMap(),
      depois: normalizado.toMap(),
    );
    semAguardar(batch.commit(), 'usuário ${antes.nome}');
  }

  /// Envia o e-mail de redefinição de senha do Firebase.
  Future<void> enviarRedefinicaoSenha(Usuario usuario) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: usuario.email);
    AuditoriaRepository.registrar(
      'user.password_reset',
      'E-mail de redefinição de senha enviado',
      entidade: 'usuario',
      entidadeId: usuario.id,
    );
  }

  /// O próprio usuário altera o nome exibido nesta loja.
  void alterarMeuNome(Usuario eu, String nome) {
    semAguardar(
      _col.doc(eu.id).update({
        'nome': nome,
        'nomeBusca': nome.toLowerCase(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      }),
      'perfil',
    );
    AuditoriaRepository.registrar(
      'profile.update',
      'Perfil alterado',
      entidade: 'usuario',
      entidadeId: eu.id,
      antes: {'nome': eu.nome},
      depois: {'nome': nome},
    );
  }

  /// Troca a senha confirmando a senha atual. Precisa de internet.
  Future<void> alterarMinhaSenha(String senhaAtual, String novaSenha) async {
    final conta = FirebaseAuth.instance.currentUser!;
    await conta.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: conta.email!, password: senhaAtual),
    );
    await conta.updatePassword(novaSenha);
    AuditoriaRepository.registrar(
      'profile.password',
      'Senha alterada',
      entidade: 'usuario',
      entidadeId: conta.uid,
    );
  }
}
