import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:uni_links/uni_links.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  // Garante que a inicialização do Flutter está completa
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face ID Auth Bridge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WebAuthPage(),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isAuthenticated = false;
  String _authMessage = 'Iniciando autenticação...';
  bool _biometricsAvailable = false;
  bool _checkingBiometrics = true;
  List<BiometricType> _availableBiometrics = [];
  StreamSubscription? _deepLinkSubscription;
  bool _processingDeepLink = false;
  
  // URL base para redirecionamento após autenticação
  final String _redirectBaseUrl = 'https://faceid-login-flow.lovable.app/';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinkListener();
    _checkBiometrics();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  // Inicializa o listener para deep links
  Future<void> _initDeepLinkListener() async {
    // Verifica se o app foi aberto por um deep link
    try {
      final initialLink = await getInitialUri();
      if (initialLink != null) {
        _handleDeepLink(initialLink);
      }
    } on PlatformException {
      // Erro ao obter o deep link inicial
      print('Erro ao obter o deep link inicial');
    }

    // Configura o listener para deep links futuros
    _deepLinkSubscription = uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    }, onError: (err) {
      print('Erro no stream de deep links: $err');
    });
  }

  // Processa o deep link recebido
  void _handleDeepLink(Uri uri) {
    print('Deep link recebido: $uri');
    // Verifica se é o deep link esperado (flutterfaceid://auth)
    if (uri.scheme == 'flutterfaceid' && uri.host == 'auth') {
      setState(() {
        _processingDeepLink = true;
      });
      
      // Se a biometria já foi verificada, inicia a autenticação
      if (!_checkingBiometrics && _biometricsAvailable) {
        _authenticate();
      }
    }
  }
  
  // Redireciona de volta para o front-end após a autenticação
  Future<void> _redirectToFrontend(bool success) async {
    String redirectUrl = '$_redirectBaseUrl?auth=${success ? 'success' : 'fail'}';
    
    try {
      final Uri url = Uri.parse(redirectUrl);
      await launchUrl(url, mode: LaunchMode.externalApplication);
      
      // Opcional: fecha o app após o redirecionamento
      Future.delayed(const Duration(seconds: 1), () {
        SystemNavigator.pop();
      });
    } catch (e) {
      print('Erro ao redirecionar: $e');
      setState(() {
        _authMessage = 'Erro ao redirecionar: $e';
      });
    }
  }

  Future<void> _checkBiometrics() async {
    bool canCheckBiometrics = false;
    bool isDeviceSupported = false;
    List<BiometricType> availableBiometrics = [];

    try {
      isDeviceSupported = await _localAuth.isDeviceSupported();
      canCheckBiometrics = await _localAuth.canCheckBiometrics;
      
      if (canCheckBiometrics && isDeviceSupported) {
        try {
          availableBiometrics = await _localAuth.getAvailableBiometrics();
          
          setState(() {
            _availableBiometrics = availableBiometrics;
            _biometricsAvailable = availableBiometrics.isNotEmpty;
          });
          
          print('Biometrias disponíveis: $_availableBiometrics');
        } on PlatformException catch (e) {
          print('Erro ao obter biometrias: ${e.message}');
        }
      }
      
      setState(() {
        _biometricsAvailable = canCheckBiometrics && isDeviceSupported && availableBiometrics.isNotEmpty;
        _checkingBiometrics = false;
      });
      
      // Se estiver processando um deep link e a biometria estiver disponível, autenticar
      if (_processingDeepLink && _biometricsAvailable) {
        _authenticate();
      } else if (!_biometricsAvailable) {
        setState(() {
          _authMessage = 'Biometria não disponível neste dispositivo';
          if (!isDeviceSupported) {
            _authMessage = 'Este dispositivo não suporta autenticação biométrica';
          } else if (!canCheckBiometrics) {
            _authMessage = 'Não é possível verificar biometria neste dispositivo';
          } else if (availableBiometrics.isEmpty) {
            _authMessage = 'Nenhuma biometria cadastrada no dispositivo';
          }
        });
        
        // Redireciona com falha se não houver biometria disponível
        if (_processingDeepLink) {
          _redirectToFrontend(false);
        }
      }
    } on PlatformException catch (e) {
      setState(() {
        _checkingBiometrics = false;
        _authMessage = 'Erro ao verificar biometria: ${e.message}';
        print('Erro detalhado: ${e.code} - ${e.message} - ${e.details}');
      });
      
      // Redireciona com falha em caso de erro
      if (_processingDeepLink) {
        _redirectToFrontend(false);
      }
    }
  }

  Future<void> _authenticate() async {
    try {
      setState(() {
        _authMessage = 'Aguardando autenticação biométrica...';
        if (_availableBiometrics.contains(BiometricType.face)) {
          _authMessage = 'Aguardando autenticação facial...';
        } else if (_availableBiometrics.contains(BiometricType.fingerprint)) {
          _authMessage = 'Aguardando impressão digital...';
        }
      });
      
      // Tenta autenticação com opções específicas
      bool isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Por favor, use sua biometria para autenticar',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: false,
          useErrorDialogs: true,
        ),
      );
      
      setState(() {
        _isAuthenticated = isAuthenticated;
        _authMessage = isAuthenticated 
            ? 'Autenticação bem-sucedida! Redirecionando...'
            : 'Autenticação falhou. Tente novamente.';
      });
      
      // Se veio de um deep link, redireciona com o resultado
      if (_processingDeepLink) {
        _redirectToFrontend(isAuthenticated);
      }
    } on PlatformException catch (e) {
      String message = 'Erro de autenticação desconhecido';
      
      switch (e.code) {
        case auth_error.notAvailable:
          message = 'Autenticação biométrica não disponível';
          break;
        case auth_error.notEnrolled:
          message = 'Nenhuma biometria cadastrada no dispositivo';
          break;
        case auth_error.passcodeNotSet:
          message = 'Configure um PIN ou padrão no dispositivo primeiro';
          break;
        case auth_error.lockedOut:
          message = 'Autenticação bloqueada temporariamente. Tente mais tarde';
          break;
        case auth_error.permanentlyLockedOut:
          message = 'Autenticação bloqueada permanentemente. Reinicie o dispositivo';
          break;
        default:
          message = 'Erro de autenticação: ${e.message}';
      }
      
      setState(() {
        _authMessage = message;
      });
      
      print('Código do erro: ${e.code}');
      print('Mensagem do erro: ${e.message}');
      print('Detalhes do erro: ${e.details}');
      
      // Se veio de um deep link, redireciona com falha
      if (_processingDeepLink) {
        _redirectToFrontend(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Face ID Auth Bridge'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (_checkingBiometrics)
                const CircularProgressIndicator()
              else
                Icon(
                  _isAuthenticated ? Icons.check_circle : 
                  _availableBiometrics.contains(BiometricType.face) ? Icons.face : 
                  _availableBiometrics.contains(BiometricType.fingerprint) ? Icons.fingerprint : 
                  Icons.security,
                  size: 100,
                  color: _isAuthenticated ? Colors.green : Colors.blue,
                ),
              const SizedBox(height: 30),
              Text(
                _authMessage,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _isAuthenticated ? Colors.green : 
                         (_authMessage.contains('Erro') ? Colors.red : Colors.black),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_biometricsAvailable && !_isAuthenticated && !_processingDeepLink)
                Text(
                  'Biometrias disponíveis: ${_availableBiometrics.map((b) => b.toString().split('.').last).join(', ')}',
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 40),
              if (_biometricsAvailable && !_processingDeepLink)
                ElevatedButton.icon(
                  onPressed: _authenticate,
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    'Tentar Novamente',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class WebAuthPage extends StatefulWidget {
  const WebAuthPage({super.key});
  @override
  State<WebAuthPage> createState() => _WebAuthPageState();
}

class _WebAuthPageState extends State<WebAuthPage> {
  late final WebViewController _controller;
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final url = req.url;
            if (url.startsWith('flutterfaceid://auth')) {
              _handleBiometric();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://faceid-login-flow.lovable.app/'),
      );
  }

  Future<void> _handleBiometric() async {
    final canAuth = await _auth.canCheckBiometrics;
    final didAuth = canAuth && await _auth.authenticate(
      localizedReason: 'Use Face ID para continuar',
      options: const AuthenticationOptions(biometricOnly: true),
    );
    final callback = didAuth
        ? 'https://faceid-login-flow.lovable.app/?auth=success'
        : 'https://faceid-login-flow.lovable.app/?auth=fail';
    _controller.loadRequest(Uri.parse(callback));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Autenticação')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
