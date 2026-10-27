# App Vendas

App de vendas para Android feito em Flutter, com Firebase (Firestore + Authentication).
Funciona **offline**: vendas, produtos e clientes são gravados no aparelho e sincronizados
automaticamente com o Firebase quando a internet volta.

## Funcionalidades

- Login por e-mail e senha (Firebase Authentication)
- CRUD de **produtos** (nome, código, preço, estoque)
- CRUD de **clientes**
- **Vendas**: carrinho, cliente opcional, forma de pagamento, desconto, baixa automática
  de estoque, cancelamento com devolução ao estoque e total vendido no dia
- Indicador de sincronização (nuvem na barra superior) e relógio laranja nos itens
  ainda não enviados ao servidor
- **Atualização automática**: ao abrir, o app consulta a última Release deste repositório
  no GitHub e oferece baixar e instalar a versão nova

## Estrutura

```
lib/
  main.dart                 inicialização do Firebase e cache offline
  app.dart                  tema, idioma, login x home, checagem de atualização
  core/config.dart          usuário/repositório do GitHub usado nas atualizações
  core/update/              consulta de Releases e diálogo de atualização
  models/                   Produto, Cliente, Venda
  data/                     acesso ao Firestore (repositórios)
  pages/                    telas
  widgets/                  componentes reutilizáveis
```

## Como funciona o offline

- O Firestore guarda no aparelho tudo o que já foi lido e todas as gravações pendentes.
- As gravações **não aguardam o servidor** (`data/offline.dart`). Offline, a tela atualiza
  na hora e o envio acontece sozinho quando a conexão voltar.
- A baixa de estoque usa `WriteBatch` + `FieldValue.increment`. Transactions não funcionam
  offline, e o increment soma certo mesmo com vários vendedores offline ao mesmo tempo.
- Produtos são excluídos de forma lógica (`ativo: false`), para que uma venda feita offline
  nunca falhe ao sincronizar por apontar para um produto apagado.
- O **primeiro login** precisa de internet. Depois disso o usuário continua logado offline.
- Os dados precisam ter sido carregados ao menos uma vez com internet para aparecerem offline.

---

## Configuração inicial (uma vez só)

### 1. Ferramentas

- Flutter (instalado em `C:\src\flutter`). Adicione `C:\src\flutter\bin` ao PATH do Windows.
- [Android Studio](https://developer.android.com/studio): instala o Android SDK e o emulador.
  Depois rode `flutter doctor --android-licenses`.
- Firebase CLI e FlutterFire CLI:

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
```

### 2. Firebase

1. Crie um projeto em <https://console.firebase.google.com>.
2. **Firestore Database** → Criar banco de dados (modo produção, região `southamerica-east1`).
3. **Firestore → Regras**: cole o conteúdo de [`firestore.rules`](firestore.rules) e publique.
4. **Authentication** → Método de login → ative **E-mail/senha**.
5. **Authentication → Usuários** → adicione os vendedores (e-mail e senha).
6. Na pasta do projeto, conecte o app ao Firebase (gera `lib/firebase_options.dart`
   e `android/app/google-services.json`):

```bash
firebase login
flutterfire configure --platforms=android
```

> Esses arquivos de configuração podem ir para o GitHub: eles identificam o projeto,
> mas não dão acesso aos dados. Quem protege os dados são as **regras do Firestore**
> e o login.

### 3. Rodar no celular/emulador

```bash
flutter run
```

---

## Releases e atualização automática

### Como funciona

1. Você cria uma tag `vX.Y.Z` e envia para o GitHub.
2. O GitHub Actions ([`.github/workflows/release.yml`](.github/workflows/release.yml))
   gera o APK assinado com a versão `X.Y.Z` e cria a Release com o APK anexado.
3. Ao abrir, o app consulta `api.github.com/repos/<usuário>/<repo>/releases/latest`.
   Se a versão for maior que a instalada, mostra o aviso **"Nova versão"**, baixa o APK
   e abre o instalador do Android.
4. Para tornar uma atualização **obrigatória** (sem botão "Depois"), edite a Release
   no GitHub e inclua `[obrigatoria]` no texto.

Configure o usuário/repositório em [`lib/core/config.dart`](lib/core/config.dart).

### Chave de assinatura (obrigatório, uma vez só)

O Android só instala uma atualização por cima da versão anterior se **as duas forem
assinadas com a mesma chave**. Gere a chave e **guarde-a em local seguro**. Se perder
a chave, os aparelhos terão de desinstalar o app para instalar novas versões.

```bash
keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Crie `android/key.properties` (já está no `.gitignore`, **nunca envie ao GitHub**):

```properties
storeFile=app/upload-keystore.jks
storePassword=SENHA_DO_KEYSTORE
keyAlias=upload
keyPassword=SENHA_DA_CHAVE
```

No GitHub: **Settings → Secrets and variables → Actions → New repository secret**:

| Secret              | Valor                                                     |
|---------------------|-----------------------------------------------------------|
| `KEYSTORE_BASE64`   | conteúdo do keystore em base64 (comando abaixo)           |
| `KEYSTORE_PASSWORD` | senha do keystore                                         |
| `KEY_ALIAS`         | `upload`                                                  |
| `KEY_PASSWORD`      | senha da chave                                            |

Para gerar o base64 no PowerShell (copia para a área de transferência):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\app\upload-keystore.jks")) | Set-Clipboard
```

### Publicar uma nova versão

```bash
git tag v1.0.1
git push origin v1.0.1
```

Acompanhe na aba **Actions** do GitHub. Ao terminar, a Release aparece na aba
**Releases** com o APK. Sempre aumente o número da versão (`1.0.1` → `1.0.2` → `1.1.0`...).

### Instalação nos aparelhos

Na primeira vez, baixe o APK da página de Releases pelo celular e instale. O Android pedirá
para **permitir instalar apps desta fonte**, tanto para o navegador quanto, na primeira
atualização, para o próprio App Vendas.
