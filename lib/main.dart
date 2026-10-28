import 'dart:async'; // NOVO: StreamSubscription (escuta das notificações)
import 'notificacao_service.dart'; // NOVO: serviço de WebSocket
import 'auth_service.dart'; // NOVO: autenticação JWT
import 'login_page.dart'; // NOVO: tela de login
import 'splash_page.dart'; // NOVO: decide Login x Home
import 'dart:convert'; // Necessário para converter texto JSON em estruturas do Dart (Map e List)
import 'dart:io'; // Para capturar exceções de rede específicas (SocketException)
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // Pacote responsável por fazer requisições HTTP (GET, POST, etc.)

void main() {
  runApp(const MyApp());
}

/// Widget raiz da aplicação
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Catálogo de Produtos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SplashPage(),
    );
  }
}

// ==============================================================================
// 1. MODELO DE DADOS (MODEL / DTO)
// ==============================================================================
// Representa o objeto "Produto" exatamente como ele é retornado pelo backend.
// Criar uma classe para os dados nos dá segurança de tipos (Type Safety),
// autocompletar no editor e previne erros comuns de digitação em chaves do JSON.
class Produto {
  final int id;
  final String nome;
  final double preco;
  final String? descricao; // Pode ser nulo (opcional)
  final bool disponivel;

  Produto({
    required this.id,
    required this.nome,
    required this.preco,
    this.descricao,
    required this.disponivel,
  });

  /// Construtor de fábrica (Factory Constructor):
  /// Recebe um `Map<String, dynamic>` vindo do jsonDecode e converte para uma instância da classe Produto.
  factory Produto.fromJson(Map<String, dynamic> json) {
    return Produto(
      id: json['id'] as int,
      nome: json['nome'] as String,
      // O campo preço pode vir como int (ex: 1200) ou double (1199.90) no JSON,
      // por isso usamos toDouble() para garantir a conversão correta.
      preco: (json['preco'] as num).toDouble(),
      descricao: json['descricao'] as String?,
      disponivel: json['disponivel'] as bool? ?? false,
    );
  }
}

// ==============================================================================
// 2. TELA PRINCIPAL (STATEFUL WIDGET)
// ==============================================================================
// Usamos StatefulWidget porque a tela possui estados dinâmicos que mudam com o tempo:
// - Carregando dados
// - Exibição da lista com sucesso
// - Exibição de erro na conexão
class TelaListaProdutos extends StatefulWidget {
  const TelaListaProdutos({super.key});

  @override
  State<TelaListaProdutos> createState() => _TelaListaProdutosState();
}

class _TelaListaProdutosState extends State<TelaListaProdutos> {
  // URL base pública da API no Render (ou use http://10.0.2.2:8000/produtos no emulador local)
  final String _apiUrl = 'https://api-produtos-mobile.onrender.com/produtos';

  // Estados da tela
  List<Produto> _produtos = [];
  bool _carregando = true;
  String? _mensagemErro;

  // NOVO: nome do usuário logado (GET /auth/me)
  String? _nomeUsuario;

  // NOVO: serviço WebSocket e assinatura do stream de notificações
  late final NotificacaoService _notificacaoService;
  StreamSubscription<Notificacao>? _notificacaoSub;

  // initState é o primeiro método executado quando o widget é inserido na árvore.
  // É o lugar ideal para disparar a busca inicial dos dados.
  @override
  void initState() {
    super.initState();
    _buscarProdutos();
    _carregarUsuario(); // NOVO: saudação com o usuário logado

    // NOVO: inicia o listener de notificações em tempo real
    _notificacaoService = NotificacaoService();
    _notificacaoSub = _notificacaoService.notificacoes.listen(_mostrarAviso);
    _notificacaoService.conectar();
  }

  // NOVO: fecha a conexão de forma limpa quando a tela sai da árvore
  @override
  void dispose() {
    _notificacaoSub?.cancel();
    _notificacaoService.desconectar();
    super.dispose();
  }

  // NOVO: GET /auth/me com o Bearer token. Se o token for inválido, desloga.
  Future<void> _carregarUsuario() async {
    try {
      final nome = await AuthService.nomeDoUsuarioLogado();
      if (!mounted) return;
      setState(() => _nomeUsuario = nome);
    } on AuthException catch (e) {
      if (e.statusCode == 401) await _sair();
      // Outros erros (rede etc.): apenas não exibe a saudação.
    }
  }

  // NOVO: logout = apaga o token e volta ao Login
  Future<void> _sair() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  // NOVO: exibe a notificação recebida como SnackBar flutuante
  void _mostrarAviso(Notificacao n) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.teal.shade700,
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            const Icon(Icons.notifications_active, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    n.mensagem,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.amber,
          onPressed: messenger.hideCurrentSnackBar,
        ),
      ),
    );
  }

  // ============================================================================
  // 3. FUNÇÃO ASSÍNCRONA PARA CONSUMIR O MÉTODO GET
  // ============================================================================
  Future<void> _buscarProdutos() async {
    // 1. Atualizamos o estado para exibir o indicador de carregamento (spinner)
    setState(() {
      _carregando = true;
      _mensagemErro = null;
    });

    try {
      // 2. Fazemos a requisição HTTP GET usando 'await' (aguarda a resposta sem travar a interface)
      final uri = Uri.parse(_apiUrl);
      final resposta = await http.get(uri).timeout(
        const Duration(seconds: 45), // Dá tempo para o Render "acordar" no primeiro acesso
      );

      // 3. Verificamos o Código de Status HTTP (200 = Sucesso / OK)
      if (resposta.statusCode == 200) {
        // resposta.body é uma String com o texto JSON.
        // Usamos utf8.decode para garantir acentuação correta (ç, ã, é, etc.)
        final List<dynamic> dadosJson = jsonDecode(utf8.decode(resposta.bodyBytes));

        // Mapeamos cada item do JSON para um objeto da classe Produto
        final List<Produto> listaCarregada = dadosJson
            .map((item) => Produto.fromJson(item as Map<String, dynamic>))
            .toList();

        // 4. Atualizamos o estado da tela com a nova lista de produtos recebida
        setState(() {
          _produtos = listaCarregada;
          _carregando = false;
        });
      } else {
        // Caso o servidor responda um código diferente de 200 (ex: 404, 500)
        setState(() {
          _mensagemErro = 'Erro no servidor: Código HTTP ${resposta.statusCode}';
          _carregando = false;
        });
      }
    } on SocketException {
      // Erro quando o dispositivo está sem internet ou o endereço não existe
      setState(() {
        _mensagemErro = 'Falha de conexão. Verifique sua internet ou a URL da API.';
        _carregando = false;
      });
    } on http.ClientException {
      // Erro no cliente HTTP (ex: problema de handshake SSL ou queda de conexão)
      setState(() {
        _mensagemErro = 'Não foi possível conectar ao servidor da API.';
        _carregando = false;
      });
    } catch (e) {
      // Qualquer outro erro inesperado (ex: timeout do Render acordando)
      setState(() {
        _mensagemErro = 'Ocorreu um erro inesperado: $e';
        _carregando = false;
      });
    }
  }

  // ============================================================================
  // 4. CONSTRUÇÃO DA INTERFACE (UI)
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produtos (API Externa)'),
        centerTitle: true,
        actions: [
          // Botão no topo para recarregar a lista manualmente
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: _carregando ? null : _buscarProdutos,
          ),
          // NOVO: botão de logout
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: _sair,
          ),
        ],
      ),
      // O corpo da tela se adapta conforme o estado atual
      body: Column(
        children: [
          // NOVO: saudação ao usuário logado
          if (_nomeUsuario != null)
            Container(
              width: double.infinity,
              color: Colors.teal.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Olá, $_nomeUsuario! 👋',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal.shade800,
                ),
              ),
            ),
          Expanded(child: _construirCorpo()),
        ],
      ),
    );
  }

  Widget _construirCorpo() {
    // ESTADO 1: Carregando dados do servidor
    if (_carregando) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Buscando produtos na API...\n(Se for a primeira requisição, o Render pode levar ~40s para acordar)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // ESTADO 2: Ocorreu algum erro na requisição
    if (_mensagemErro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _mensagemErro!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _buscarProdutos,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar Novamente'),
              ),
            ],
          ),
        ),
      );
    }

    // ESTADO 3: A lista retornou vazia do backend
    if (_produtos.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum produto cadastrado na API.',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    // ESTADO 4: Sucesso! Exibição da lista usando Cards e ListView.builder
    // RefreshIndicator permite o gesto de "puxar para baixo para atualizar" (Pull-to-refresh)
    return RefreshIndicator(
      onRefresh: _buscarProdutos,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _produtos.length,
        itemBuilder: (context, index) {
          final produto = _produtos[index];

          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ícone / Avatar à esquerda com o ID do produto
                  CircleAvatar(
                    backgroundColor: produto.disponivel
                        ? Colors.teal.shade50
                        : Colors.grey.shade200,
                    foregroundColor: produto.disponivel
                        ? Colors.teal
                        : Colors.grey.shade600,
                    child: Text('#${produto.id}'),
                  ),
                  const SizedBox(width: 14),

                  // Informações do produto (Nome, Descrição e Preço)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          produto.nome,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (produto.descricao != null &&
                            produto.descricao!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            produto.descricao!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'R\$ ${produto.preco.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Badge de Disponibilidade à direita
                  Chip(
                    label: Text(
                      produto.disponivel ? 'Disponível' : 'Esgotado',
                      style: TextStyle(
                        fontSize: 11,
                        color: produto.disponivel
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: produto.disponivel
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}