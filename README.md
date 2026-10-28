# Catálogo de Produtos – Flutter

Aplicativo Flutter que consome a API de produtos e evoluiu ao longo da disciplina de **Desenvolvimento Mobile(IFMS)**. Esta versão implementa:

- **Autenticação com JWT** (login, cadastro, sessão persistente e logout)
- **Notificações em tempo real via WebSocket** (`dart:io`)
- **Listagem de produtos** consumida da API REST

**API utilizada:** <https://api-produtos-mobile.onrender.com>

> A API está hospedada no plano gratuito do Render: na primeira requisição após um período de inatividade o servidor pode levar cerca de **40 segundos** para "acordar".

## Funcionalidades

### 1. Login (`POST /auth/login`)
- Formulário com **Usuário** e **Senha**, com validação de campos vazios.
- Envia as credenciais em JSON e recebe o `access_token`.
- O token é salvo no aparelho com `shared_preferences`.
- Indicador de carregamento no botão e mensagem amigável de erro:
  - **401** → "Usuário ou senha incorretos."
  - Sem internet / timeout → mensagens específicas.

### 2. Cadastro (`POST /auth/cadastrar`)
- Formulário com **Nome Completo**, **Nome de Usuário** e **Senha**.
- **400** → "Este nome de usuário já está em uso."
- Em caso de sucesso, volta para o Login com o usuário já preenchido.

### 3. Sessão e Logout
- **Manter conectado:** ao abrir o app, a `SplashPage` verifica se existe token salvo e vai direto para a tela principal (ou para o Login, se não houver).
- **Identificação do usuário:** a tela principal faz `GET /auth/me` com o cabeçalho `Authorization: Bearer <token>` e exibe a saudação **"Olá, <nome>!"**.
- **Token inválido/expirado:** se `/auth/me` responder 401, o app encerra a sessão automaticamente e volta ao Login.
- **Sair:** o botão de logout na AppBar remove o token do dispositivo e retorna ao Login.

### 4. Notificações em tempo real (WebSocket)
- Conexão com `wss://api-produtos-mobile.onrender.com/ws/notificacoes` usando o `WebSocket` nativo de `dart:io`.
- Cada mensagem recebida (JSON com `titulo` e `mensagem`) é exibida em um `SnackBar` flutuante.
- Reconexão automática após 5 segundos se a conexão cair.
- Ciclo de vida: o listener inicia no `initState()` e a conexão é fechada no `dispose()`.

### 5. Catálogo de produtos
- `GET /produtos` com estados de carregando, erro, lista vazia e lista de produtos.
- *Pull-to-refresh* e botão de atualizar na AppBar.

## Estrutura do projeto

```
lib/
├── main.dart                 # App, tela principal (produtos, saudação, logout, WebSocket)
├── splash_page.dart          # Decide: Login ou tela principal (token salvo?)
├── login_page.dart           # Tela de login
├── cadastro_page.dart        # Tela de cadastro
├── auth_service.dart         # Chamadas /auth/* + armazenamento do token
└── notificacao_service.dart  # Conexão WebSocket e stream de notificações
```

### Decisões de arquitetura
- **`AuthService`** concentra toda a comunicação com `/auth/*` e o acesso ao `SharedPreferences`; as telas não fazem requisições HTTP de autenticação diretamente.
- Erros viram uma `AuthException` com mensagem pronta para o usuário, mantendo as telas simples.
- **`NotificacaoService`** expõe um `Stream<Notificacao>`, separando a rede da interface.
- Uso de `mounted` após operações assíncronas para evitar `setState` em widgets descartados.

## Endpoints consumidos

| Método | Rota                | Autenticação | Descrição                         |
|--------|---------------------|--------------|-----------------------------------|
| POST   | `/auth/login`       | Não          | Retorna `access_token`            |
| POST   | `/auth/cadastrar`   | Não          | Cria uma nova conta               |
| GET    | `/auth/me`          | Bearer JWT   | Dados do usuário logado           |
| GET    | `/produtos`         | Não          | Lista de produtos                 |
| WS     | `/ws/notificacoes`  | Não          | Notificações em tempo real        |

## Como executar

### Pré-requisitos
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (testado com Flutter 3.16.x / Dart 3.2.x)
- Um dispositivo, emulador ou navegador configurado (`flutter devices` lista os disponíveis)

### Passos

```bash
# 1. Clone o repositório
git clone <URL-DO-SEU-REPOSITORIO>
cd <PASTA-DO-PROJETO>

# 2. Instale as dependências
flutter pub get

# 3. Execute
flutter run -d windows     # ou: chrome, edge, ou o id de um emulador
```

> **WebSocket na web:** o `dart:io` não funciona no navegador. Em Chrome/Edge o login, o cadastro e a sessão funcionam normalmente, mas as notificações em tempo real não. Para testá-las, use Windows, Android ou iOS.

### Alternando entre servidor na nuvem e local
No `lib/notificacao_service.dart`, a flag `usarNuvem` escolhe o servidor do WebSocket:

| Ambiente                     | URL                                              |
|------------------------------|--------------------------------------------------|
| Nuvem (padrão)               | `wss://api-produtos-mobile.onrender.com/ws/notificacoes` |
| Emulador Android local       | `ws://10.0.2.2:8000/ws/notificacoes`             |
| Simulador iOS / Web local    | `ws://localhost:8000/ws/notificacoes`            |

## Como testar

Usuários pré-cadastrados na API:

| Perfil        | Usuário | Senha      |
|---------------|---------|------------|
| Aluno padrão  | `aluno` | `123456`   |
| Administrador | `admin` | `admin123` |

Roteiro de validação:

1. Inicie o app e entre com `aluno` / `123456`.
2. Confira a transição para a tela de produtos e a saudação **"Olá, …!"** (prova de que o Bearer token foi aceito em `/auth/me`).
3. Feche totalmente o app e abra novamente: ele deve entrar direto na lista (persistência com `shared_preferences`).
4. Toque no ícone de **logout**: a sessão é encerrada e o Login reaparece.
5. Toque em **Cadastre-se**, crie um usuário e faça login com ele.
6. Teste os erros: senha incorreta (401) e cadastro com usuário já existente (400).

## Dependências

| Pacote               | Uso                                  |
|----------------------|--------------------------------------|
| `http`               | Requisições REST                     |
| `shared_preferences` | Persistência local do token JWT      |

O WebSocket utiliza apenas a biblioteca nativa `dart:io`, sem pacotes adicionais.

## Capturas de tela

<!-- Adicione aqui as imagens do app, por exemplo:
![Login](docs/login.png)
![Cadastro](docs/cadastro.png)
![Produtos](docs/produtos.png)
-->

## Autor

Wilson dos Santos Catelan – Tecnologia em Sistemas para Internet, IFMS
Disciplina: Programação para Dispositivos Móveis II
