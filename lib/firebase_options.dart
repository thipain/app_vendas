// ARQUIVO PROVISÓRIO.
// Será substituído automaticamente ao rodar `flutterfire configure`
// (veja o README). Até lá o app não consegue conectar ao Firebase.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw UnsupportedError(
        'Firebase ainda não configurado. Rode `flutterfire configure` '
        'na pasta do projeto.',
      );
}
