import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

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
      title: 'Face Unlock App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthScreen(),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isAuthenticated = false;
  String _authMessage = 'Iniciando autenticação...';
  bool _biometricsAvailable = false;
  bool _checkingBiometrics = true;
  List<BiometricType> _availableBiometrics = [];

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
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
      
      if (_biometricsAvailable) {
        // Iniciar autenticação automaticamente
        _authenticate();
      } else {
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
      }
    } on PlatformException catch (e) {
      setState(() {
        _checkingBiometrics = false;
        _authMessage = 'Erro ao verificar biometria: ${e.message}';
        print('Erro detalhado: ${e.code} - ${e.message} - ${e.details}');
      });
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
        localizedReason: 'Por favor, use sua biometria para desbloquear',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: false, // Pode ajudar em alguns dispositivos
          useErrorDialogs: true, // Exibe diálogos de erro do sistema
        ),
      );
      
      setState(() {
        _isAuthenticated = isAuthenticated;
        _authMessage = isAuthenticated 
            ? 'Autenticação bem-sucedida! Acesso permitido.'
            : 'Autenticação falhou. Tente novamente.';
      });
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Face Unlock App'),
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
              if (_biometricsAvailable && !_isAuthenticated)
                Text(
                  'Biometrias disponíveis: ${_availableBiometrics.map((b) => b.toString().split('.').last).join(', ')}',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 40),
              if (_biometricsAvailable)
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
