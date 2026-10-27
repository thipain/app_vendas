import 'package:flutter/foundation.dart';

import '../models/usuario.dart';

/// Usuário logado e suas permissões, disponível para telas e repositórios.
class Sessao extends ChangeNotifier {
  Sessao._();
  static final instancia = Sessao._();

  Usuario? _usuario;
  Usuario? get usuario => _usuario;

  /// Usuário logado. Só use depois do login (dentro da HomePage).
  Usuario get atual => _usuario!;

  void definir(Usuario? usuario) {
    _usuario = usuario;
    notifyListeners();
  }

  bool pode(String permissao) => _usuario?.pode(permissao) ?? false;
  bool get isAdmin => _usuario?.isAdmin ?? false;

  /// Identificação gravada nos documentos para saber quem fez a operação.
  Map<String, dynamic> get autor => {
        'uid': _usuario?.id ?? '',
        'nome': _usuario?.nome ?? '',
      };
}
