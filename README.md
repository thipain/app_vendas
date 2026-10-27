# App Vendas

App de vendas para **Android** e **Windows** feito em Flutter, com Firebase (Firestore + Authentication).
O mesmo código roda no celular e no PC, com os mesmos dados: a loja usa no computador
do balcão e registra vendas pelo celular quando está longe dele.
Funciona **offline**: vendas, produtos e clientes são gravados no aparelho e sincronizados
automaticamente com o Firebase quando a internet volta.

## Funcionalidades

Sistema completo de PDV para adega/loja, com todas as funções do AdegaPDV (versão web):

**Operação diária**
- **Visão geral**: vendas do dia, comandas abertas, itens em alerta e atalhos
- **Caixa**: abertura, suprimento, sangria, fechamento com conferência da diferença e
  histórico dos últimos fechamentos (só dinheiro movimenta a gaveta)
- **Nova venda**: catálogo com fotos e busca, carrinho limitado ao estoque, desconto em R$
  ou %, Pix/Dinheiro/Débito/Crédito (até 24x)/VR, troco, pagamento dividido em duas formas,
  cliente opcional e comprovante
- **Comandas**: abrir, lançar itens (o estoque sai na hora), alterar/remover itens,
  renomear, cancelar com devolução e fechar com pagamento gerando a venda
- **Retiradas de funcionário**: consumo da equipe com baixa no estoque, resumo mensal
  por pessoa e cancelamento com devolução
- **Ponto**: registro de entrada/saída com localização e endereço; ponto da equipe
- **Clientes**: cadastro de clientes

**Produtos e estoque**
- Produtos com foto, código, categoria, preço de venda e custo, unidade, estoque mínimo,
  ajuste de saldo com motivo obrigatório, desativação e restauração
- **Notificações** de itens zerados e com estoque baixo (sino com contador)
- **Notas de entrada** (controle interno): fornecedor, custo, vários produtos, edição com
  reconciliação automática do estoque e impressão em A4
- **Montagem e desmanche**: regras reutilizáveis (ex.: gelo + dose → copo; pallet →
  caixas → unidades), execução em lotes e custo médio do produto gerado
- **Histórico do estoque**: toda entrada, venda, comanda, ajuste e estorno

**Gestão**
- **Histórico de vendas** com filtros, detalhes, reimpressão, edição do comprovante e
  estorno (devolve ao estoque e estorna o dinheiro no caixa)
- **Relatórios**: faturamento, custo, lucro, margem, descontos, por forma de pagamento e
  lucro por produto
- **Auditoria** de acessos e de todas as operações sensíveis
- **Equipe e acessos**: administrador e funcionários com permissões por módulo, bloqueio,
  redefinição de senha e proteção do último administrador
- **Configurações**: nome da loja, logo, cores, contato e dados do comprovante
- **Calculadora**, **Meu perfil** (nome e senha)

**Geral**
- Funciona **offline** no celular e no PC; sincroniza sozinho quando a internet volta
- Indicador de sincronização (nuvem na barra superior) e relógio laranja nos itens
  ainda não enviados ao servidor
- Comprovante 80 mm e nota A4 impressos ou compartilhados em PDF
- **Atualização automática** pelas Releases do GitHub (APK no Android, instalador no Windows)
- Layout adaptável: menu em gaveta no celular e menu lateral fixo no PC

### Primeiro acesso e equipe

Na primeira vez que alguém entra no sistema, o app pede o nome e transforma essa conta no
**administrador**. Depois disso, novos funcionários são cadastrados pelo administrador em
**Equipe e acessos** (precisa de internet). Contas criadas direto no Console do Firebase não
têm acesso até serem cadastradas na equipe.

## Estrutura

```
lib/
  main.dart                 inicialização do Firebase e cache offline
  app.dart                  tema, idioma, login x home, checagem de atualização
  core/config.dart          usuário/repositório do GitHub usado nas atualizações
  core/update/              consulta de Releases e diálogo de atualização
  core/                     sessão, permissões, dinheiro em centavos, imagens, impressão
  models/                   entidades (Produto, Venda, Caixa, Comanda, NotaEntrada...)
  data/                     repositórios do Firestore com as regras de negócio
  pages/shell/              menu, permissões e primeiro acesso
  pages/                    telas de cada módulo
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
- As regras (estoque suficiente, um caixa aberto por vez etc.) são conferidas com os dados
  que o aparelho tem no momento. Com dois aparelhos **offline ao mesmo tempo**, ambos podem
  vender o último item: o saldo fica negativo e aparece em Notificações e no Histórico do estoque.
- Cadastrar funcionários, trocar a senha e o primeiro acesso do sistema precisam de internet.
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
3. Publique as regras e índices do Firestore ([`firestore.rules`](firestore.rules),
   [`firestore.indexes.json`](firestore.indexes.json)): `firebase deploy --only firestore`.
4. **Authentication** → Método de login → ative **E-mail/senha**.
5. **Authentication → Usuários** → adicione **somente o primeiro usuário** (o dono). Ele vira
   administrador no primeiro acesso e cadastra o resto da equipe pelo app.
6. Na pasta do projeto, conecte o app ao Firebase (gera `lib/firebase_options.dart`
   e `android/app/google-services.json`):

```bash
firebase login
flutterfire configure --platforms=android
```

> Esses arquivos de configuração podem ir para o GitHub: eles identificam o projeto,
> mas não dão acesso aos dados. Quem protege os dados são as **regras do Firestore**
> e o login.

### 3. Rodar no celular/emulador ou no PC

```bash
flutter run
```

Para rodar no Windows (`flutter run -d windows`) é preciso o **Visual Studio 2022** com a
carga de trabalho **"Desenvolvimento para desktop com C++"**. Não é necessário para
publicar: o instalador do Windows é gerado pelo GitHub Actions.

---

## Releases e atualização automática

### Como funciona

1. Você cria uma tag `vX.Y.Z` e envia para o GitHub.
2. O GitHub Actions ([`.github/workflows/release.yml`](.github/workflows/release.yml))
   gera o APK assinado e o instalador do Windows (`app_vendas-setup-X.Y.Z.exe`, feito com
   [Inno Setup](installer/app_vendas.iss)) e cria a Release com os dois anexados.
3. Ao abrir, o app consulta `api.github.com/repos/<usuário>/<repo>/releases/latest`.
   Se a versão for maior que a instalada, mostra o aviso **"Nova versão"**. No Android baixa
   o APK e abre o instalador; no Windows baixa o instalador, roda em modo silencioso e
   reabre o app já atualizado.
4. Para tornar uma atualização **obrigatória** (sem botão "Depois"), crie a tag com uma
   mensagem contendo `[obrigatoria]` (`git tag -a v1.2.3 -m "[obrigatoria] Novidades"`), ou
   edite a Release no GitHub e inclua `[obrigatoria]` no texto.

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
**Releases** com o APK e o instalador do Windows. Sempre aumente o número da versão (`1.0.1` → `1.0.2` → `1.1.0`...).

### Instalação nos aparelhos

Na primeira vez, baixe o APK da página de Releases pelo celular e instale. O Android pedirá
para **permitir instalar apps desta fonte**, tanto para o navegador quanto, na primeira
atualização, para o próprio App Vendas.

No PC, baixe `app_vendas-setup-X.Y.Z.exe` da página de Releases e execute. Não pede senha de
administrador (instala só para o usuário atual). Como o instalador não é assinado
digitalmente, o Windows pode mostrar "O Windows protegeu o computador": clique em
**Mais informações → Executar assim mesmo**.
