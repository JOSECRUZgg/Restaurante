import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Autenticación anónima para proteger Firestore
  try {
    await FirebaseAuth.instance.signInAnonymously();
  } catch (e) {
    // Si falla, la app no puede continuar
    runApp(const _AuthErrorApp());
    return;
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ServeSyncApp());
}

class _AuthErrorApp extends StatelessWidget {
  const _AuthErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0E14),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, color: Color(0xFFFF4757), size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Error de conexión',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFF0F6FC),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'No se pudo autenticar con Firebase. Verifica tu conexión a internet y la configuración del proyecto.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF8B949E)),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => main(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2ECC71),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  ),
                  child: const Text('Reintentar', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── PALETA DE COLORES ────────────────────────────────────────────────────────
class AppColors {
  static const bg = Color(0xFF0D0B0A);
  static const bgCard = Color(0xFF151210);
  static const surface = Color(0xFF1D1916);
  static const surfaceLight = Color(0xFF26211C);
  static const primary = Color(0xFFE8843C);
  static const primaryLight = Color(0xFFF5A623);
  static const primaryDim = Color(0xFFA85D1A);
  static const textPrimary = Color(0xFFF0EDEB);
  static const textSecondary = Color(0xFF9E948E);
  static const textMuted = Color(0xFF544C47);
  static const orange = Color(0xFFFF8C00);
  static const red = Color(0xFFFF4757);
  static const blue = Color(0xFF4C9BE8);
  static const green = Color(0xFF22C55E);
  static const borderPrimary = Color(0x26E8843C);
}

// ─── MODELO PARA ÚLTIMA ACCIÓN (UNDO) ─────────────────────────────────────────

class _UltimoCambio {
  final String docId;
  final MesaStatus oldStatus;
  final double? oldTotalCobrar;
  final DateTime? oldOcupadaDesde;
  final MesaStatus newStatus;
  final int mesaNumero;
  final String descripcion;
  final DateTime timestamp;

  _UltimoCambio({
    required this.docId,
    required this.oldStatus,
    this.oldTotalCobrar,
    this.oldOcupadaDesde,
    required this.newStatus,
    required this.mesaNumero,
    required this.descripcion,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// ─── APP ROOT ─────────────────────────────────────────────────────────────────
class ServeSyncApp extends StatelessWidget {
  const ServeSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ServeSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        primaryColor: AppColors.primary,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          surface: AppColors.surface,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PANTALLA 1: LOGIN
// ═════════════════════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _idController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;
  String? _errorMessage;
  bool _usePinMode = false;
  String _pinValue = '';

  late AnimationController _shakeController;
  late AnimationController _glowController;
  late Animation<double> _shakeAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _shakeController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('session_id');
    final pin = prefs.getString('session_pin');
    final raw = prefs.getString('session_timestamp');
    if (id == null || pin == null || raw == null) return;
    final ts = DateTime.tryParse(raw);
    if (ts == null) return;
    if (DateTime.now().difference(ts).inHours >= 1) {
      await prefs.clear();
      return;
    }
    // Sesión válida — auto-login
    final mesero = await FirebaseService.loginMesero(id, pin);
    if (mesero == null || !mounted) {
      if (mesero == null) await prefs.clear();
      return;
    }
    await FirebaseService.seedDataIfEmpty();
    final esAdmin = mesero['rol'] == 'admin';
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MesasScreen(
          meseroNombre: mesero['nombre'] ?? 'Mesero',
          meseroDocId: mesero['docId'] ?? '',
          esAdmin: esAdmin,
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    final id = _idController.text.trim().toUpperCase();
    final pin = _usePinMode ? _pinValue : '';

    if (id.isEmpty && !_usePinMode) {
      setState(() => _errorMessage = 'Ingresa tu ID de mesero');
      _shakeController.forward(from: 0);
      return;
    }
    if (_usePinMode && _pinValue.length < 4) {
      setState(() => _errorMessage = 'Ingresa tu ID y PIN completo');
      _shakeController.forward(from: 0);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Validar contra Firestore
    final mesero = await FirebaseService.loginMesero(id, pin);

    if (!mounted) return;

    if (mesero != null) {
      // Guardar sesión persistente
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session_id', id);
      await prefs.setString('session_pin', pin);
      await prefs.setString(
          'session_timestamp', DateTime.now().toIso8601String());

      // Seed de datos iniciales si Firestore está vacío
      await FirebaseService.seedDataIfEmpty();

      final esAdmin = mesero['rol'] == 'admin';
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => MesasScreen(
            meseroNombre: mesero['nombre'] ?? 'Mesero',
            meseroDocId: mesero['docId'] ?? '',
            esAdmin: esAdmin,
          ),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.05),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                )),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'ID o PIN incorrecto. Contacta al administrador.';
      });
      _shakeController.forward(from: 0);
    }
  }

  void _onPinTap(String digit) {
    if (_pinValue.length < 4) {
      setState(() {
        _pinValue += digit;
        _errorMessage = null;
      });
      // Auto-login cuando PIN llega a 4 dígitos (si el ID ya está)
      if (_pinValue.length == 4 && _idController.text.trim().isNotEmpty) {
        _handleLogin();
      }
    }
  }

  void _onPinDelete() {
    if (_pinValue.isNotEmpty) {
      setState(() => _pinValue = _pinValue.substring(0, _pinValue.length - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (_, __) => Positioned(
              top: -100,
              left: -50,
              right: -50,
              child: Container(
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary
                          .withOpacity(0.06 * _glowAnimation.value),
                      blurRadius: 200,
                      spreadRadius: 100,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  _buildBranding(),
                  const SizedBox(height: 40),
                  _buildCard(),
                  const SizedBox(height: 24),
                  _buildBottomInfo(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranding() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.primary.withOpacity(0.3), width: 1.5),
          ),
          child:
              const Icon(Icons.sync_rounded, color: AppColors.primary, size: 38),
        ),
        const SizedBox(height: 16),
        const Text(
          'ServeSync',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Sistema de gestión para restaurantes',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildCard() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (_, child) {
        final offset =
            sin(_shakeAnimation.value * pi * 6) * 10.0;
        return Transform.translate(
          offset: Offset(offset * (1 - _shakeAnimation.value), 0),
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderPrimary, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.07),
              blurRadius: 40,
              spreadRadius: 5,
            ),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildModeTab('ID de Mesero', !_usePinMode, () {
                  setState(() {
                    _usePinMode = false;
                    _errorMessage = null;
                  });
                }),
                const SizedBox(width: 8),
                _buildModeTab('ID + PIN', _usePinMode, () {
                  setState(() {
                    _usePinMode = true;
                    _errorMessage = null;
                    _pinValue = '';
                  });
                }),
              ],
            ),
            const SizedBox(height: 24),
            _buildIdField(),
            if (_usePinMode) ...[
              const SizedBox(height: 20),
              _buildPinLabel(),
              const SizedBox(height: 12),
              _buildPinDisplay(),
              const SizedBox(height: 16),
              _buildPinKeypad(),
            ] else ...[
              const SizedBox(height: 12),
              _buildRememberMe(),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _buildError(),
            ],
            const SizedBox(height: 24),
            _buildLoginButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? AppColors.primary.withOpacity(0.5)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildIdField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ID DE MESERO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _idController,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Ej: M001, M002, ADMIN...',
            hintStyle:
                const TextStyle(color: AppColors.textMuted),
            prefixIcon: const Icon(Icons.badge_outlined,
                color: AppColors.textSecondary, size: 20),
            filled: true,
            fillColor: AppColors.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: AppColors.textMuted.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: AppColors.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 16),
          ),
          onSubmitted: (_) => _usePinMode ? null : _handleLogin(),
        ),
      ],
    );
  }

  Widget _buildPinLabel() {
    return const Text(
      'PIN NUMÉRICO',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildRememberMe() {
    return Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: _rememberMe,
            onChanged: (v) =>
                setState(() => _rememberMe = v ?? false),
            activeColor: AppColors.primary,
            side: const BorderSide(
                color: AppColors.textMuted, width: 1.5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(width: 8),
        const Text('Recordar ID',
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildPinDisplay() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final filled = i < _pinValue.length;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? AppColors.primary : AppColors.surfaceLight,
              border: Border.all(
                color: filled
                    ? AppColors.primary
                    : AppColors.textMuted,
                width: 1.5,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPinKeypad() {
    final keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '', '0', '⌫'
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: 12,
      itemBuilder: (_, i) {
        final key = keys[i];
        if (key.isEmpty) return const SizedBox();
        return GestureDetector(
          onTap: () =>
              key == '⌫' ? _onPinDelete() : _onPinTap(key),
          child: Container(
            decoration: BoxDecoration(
              color: key == '⌫'
                  ? Colors.transparent
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: key == '⌫'
                  ? null
                  : Border.all(color: AppColors.borderPrimary),
            ),
            alignment: Alignment.center,
            child: Text(
              key,
              style: TextStyle(
                fontSize: key == '⌫' ? 22 : 18,
                fontWeight: FontWeight.w600,
                color: key == '⌫'
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildError() {
    return Row(
      children: [
        const Icon(Icons.error_outline, color: AppColors.red, size: 15),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _errorMessage!,
            style:
                const TextStyle(color: AppColors.red, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.primaryDim,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.black54,
                  strokeWidth: 2.5,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login_rounded, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Ingresar a Turno',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBottomInfo() {
    return Column(
      children: [
        GestureDetector(
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Contacta al administrador del sistema'),
              backgroundColor: AppColors.surface,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          child: Text(
            '¿Olvidaste tu ID? Contacta al administrador',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.primary.withOpacity(0.7),
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary.withOpacity(0.4),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Sucursal Centro · v1.2.0',
          style:
              TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PANTALLA 2: MAPA DE MESAS (con Firestore en tiempo real)
// ═════════════════════════════════════════════════════════════════════════════
class MesasScreen extends StatefulWidget {
  final String meseroNombre;
  final String meseroDocId;
  final bool esAdmin;
  const MesasScreen({
    super.key,
    required this.meseroNombre,
    required this.meseroDocId,
    this.esAdmin = false,
  });

  @override
  State<MesasScreen> createState() => _MesasScreenState();
}

class _MesasScreenState extends State<MesasScreen>
    with WidgetsBindingObserver {
  int _selectedTab = 0;
  int _navIndex = 0;
  bool _isSearching = false;
  final _searchController = TextEditingController();
  List<String> _salones = ['Salón Principal', 'Terraza', 'Barra'];
  String _nombreRestaurante = 'Sucursal Centro';
  int _capacidadDefault = 4;
  String? _fotoBase64;
  StreamSubscription<Map<String, dynamic>?>? _fotoSub;
  _UltimoCambio? _ultimoCambio;
  Timer? _sessionTimer;
  DateTime? _sessionStart;
  int? _historialMesaSeleccionada;
  String? _lastKnownRol;
  bool _esAdmin = false;
  List<String> _menuSecciones = ['Platillos', 'Postres', 'Bebidas'];
  final _menuSearchCtrl = TextEditingController();
  String? _menuSeccionFilter;
  bool _mostrandoHistorial = false;
  Map<String, dynamic>? _meseroData;
  int _ordenesHoy = 0;
  double _totalFacturadoHoy = 0;
  List<Map<String, dynamic>> _mesasData = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _esAdmin = widget.esAdmin;
    _initSession();
    FirebaseService.getConfigStream().listen((config) {
      if (config != null && mounted) {
        setState(() {
          _salones = List<String>.from(config['salones'] ?? _salones);
          _nombreRestaurante = config['nombreRestaurante'] ?? _nombreRestaurante;
          _capacidadDefault = config['capacidadDefault'] ?? _capacidadDefault;
          _menuSecciones = List<String>.from(
              config['menuSecciones'] ?? _menuSecciones);
          if (_menuSeccionFilter != null &&
              !_menuSecciones.contains(_menuSeccionFilter)) {
            _menuSeccionFilter = null;
          }
        });
      }
    });
    _fotoSub = FirebaseService.getMeseroStream(widget.meseroDocId).listen((data) {
      if (data != null && mounted) {
        setState(() {
          _meseroData = data;
          _fotoBase64 = data['foto'];
        });
        final nuevoRol = data['rol'] as String?;
        final rolInitial = _esAdmin ? 'admin' : 'mesero';
        _lastKnownRol ??= rolInitial;
        if (nuevoRol != null && nuevoRol != _lastKnownRol) {
          _lastKnownRol = nuevoRol;
          setState(() => _esAdmin = nuevoRol == 'admin');
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              backgroundColor: AppColors.surface,
              title: const Text('Rol actualizado',
                  style: TextStyle(color: AppColors.textPrimary)),
              content: Text(
                nuevoRol == 'admin'
                    ? 'Ahora tienes permisos de administrador.'
                    : 'Tu rol ha cambiado a mesero.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendido',
                      style: TextStyle(color: AppColors.primary)),
                ),
              ],
            ),
          );
        }
      }
    });
    _loadTodayStats();
    FirebaseService.getMesasStream().listen((mesas) {
      if (mounted) {
        setState(() => _mesasData = mesas.map((m) {
          final map = <String, dynamic>{
            'docId': m.docId,
            'numero': m.numero,
            'status': m.status.name,
            'totalOrden': m.totalOrden,
            'salon': m.salon,
          };
          return map;
        }).toList());
      }
    });
  }

  Future<void> _loadTodayStats() async {
    final eventos = await FirebaseService.getHistorialHoyByUsuario(widget.meseroNombre);
    if (!mounted) return;
    int ordenes = 0;
    double total = 0;
    for (final e in eventos) {
      if (e.tipo == 'cambio_estado') {
        final status = e.datos['status'] as String?;
        if (status == 'ocupada') ordenes++;
        if (status == 'pago') {
          final t = e.datos['totalOrden'];
          if (t is num) total += t.toDouble();
        }
      }
    }
    setState(() {
      _ordenesHoy = ordenes;
      _totalFacturadoHoy = total;
    });
  }

  Future<void> _initSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('session_timestamp');
    if (raw != null) {
      _sessionStart = DateTime.tryParse(raw);
      if (_sessionStart != null) {
        _startSessionTimer();
      }
    }
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkSessionExpiry();
    });
  }

  Future<void> _checkSessionExpiry() async {
    if (_sessionStart == null) return;
    final elapsed = DateTime.now().difference(_sessionStart!);
    if (elapsed.inHours >= 1 && mounted) {
      _sessionTimer?.cancel();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.borderPrimary),
          ),
          title: const Text('Sesión expirada',
              style: TextStyle(color: AppColors.textPrimary)),
          content: const Text('Han pasado 1 hora desde tu ingreso.',
              style: TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              },
              child: const Text('Cerrar sesión',
                  style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSessionExpiry();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _searchController.dispose();
    _menuSearchCtrl.dispose();
    _fotoSub?.cancel();
    super.dispose();
  }

  Color _statusColor(MesaStatus s) {
    switch (s) {
      case MesaStatus.libre: return AppColors.green;
      case MesaStatus.ocupada: return AppColors.orange;
      case MesaStatus.pago: return AppColors.red;
      case MesaStatus.reservada: return AppColors.blue;
    }
  }

  String _statusLabel(MesaStatus s) {
    switch (s) {
      case MesaStatus.libre: return 'Libre';
      case MesaStatus.ocupada: return 'Ocupada';
      case MesaStatus.pago: return 'Pago';
      case MesaStatus.reservada: return 'Reservada';
    }
  }

  IconData _statusIcon(MesaStatus s) {
    switch (s) {
      case MesaStatus.libre: return Icons.check_circle_outline;
      case MesaStatus.ocupada: return Icons.restaurant;
      case MesaStatus.pago: return Icons.attach_money;
      case MesaStatus.reservada: return Icons.bookmark_outlined;
    }
  }

  void _showStatusNotification(MesaStatus status, int numero,
      {VoidCallback? onUndo}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _StatusNotification(
        status: status,
        numero: numero,
        statusColor: _statusColor(status),
        statusLabel: _statusLabel(status),
        statusIcon: _statusIcon(status),
        onDismiss: () => entry.remove(),
        onUndo: onUndo,
      ),
    );
    overlay.insert(entry);
  }

  void _showMesaDetail(MesaData mesa) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MesaDetailSheet(
        mesa: mesa,
        statusColor: _statusColor(mesa.status),
        statusLabel: _statusLabel(mesa.status),
        onStatusChange: (newStatus) async {
          final oldStatus = mesa.status;
          final oldTotal = mesa.totalCobrar;
          final oldOcupada = mesa.ocupadaDesde;
          Navigator.pop(context);
          await FirebaseService.updateMesaStatus(
            mesa.docId,
            newStatus.value,
            ocupadaDesde: newStatus == MesaStatus.ocupada
                ? Timestamp.now()
                : null,
            usuario: widget.meseroNombre,
            mesaNumero: mesa.numero,
            oldStatus: oldStatus.value,
            totalOrden: newStatus == MesaStatus.pago ? mesa.totalOrden : null,
          );
          if (mounted) {
            setState(() {
              _ultimoCambio = _UltimoCambio(
                docId: mesa.docId,
                oldStatus: oldStatus,
                oldTotalCobrar: oldTotal,
                oldOcupadaDesde: oldOcupada,
                newStatus: newStatus,
                mesaNumero: mesa.numero,
                descripcion:
                    'Mesa ${mesa.numero}: ${_statusLabel(oldStatus)} → ${_statusLabel(newStatus)}',
              );
            });
            _showStatusNotification(newStatus, mesa.numero, onUndo: () {
              _doUndo();
            });
          }
        },
      ),
    );
  }

  void _doUndo() {
    final c = _ultimoCambio;
    if (c == null) return;
    FirebaseService.updateMesaStatus(
      c.docId,
      c.oldStatus.value,
      totalCobrar: c.oldTotalCobrar,
      ocupadaDesde: c.oldOcupadaDesde != null
          ? Timestamp.fromDate(c.oldOcupadaDesde!)
          : null,
      usuario: widget.meseroNombre,
      mesaNumero: c.mesaNumero,
      oldStatus: c.newStatus.value,
    );
    setState(() => _ultimoCambio = null);
    if (mounted) {
      _showStatusNotification(c.oldStatus, c.mesaNumero);
    }
  }

  // ─── PERFIL / ADMIN ──────────────────────────────────────────────────────────

  void _showFotoSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Foto de perfil',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Cámara',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickFoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Galería',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _pickFoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final base64 = base64Encode(bytes);
    if (mounted) {
      setState(() => _fotoBase64 = base64);
      await FirebaseService.updateMesero(widget.meseroDocId, {'foto': base64});
    }
  }

  void _showChangePinDialog() {
    final actualCtrl = TextEditingController();
    final nuevoCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.borderPrimary),
          ),
          title: const Text('Cambiar PIN',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: actualCtrl,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration('PIN actual', Icons.lock_outline),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nuevoCtrl,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration('Nuevo PIN', Icons.lock),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration('Confirmar PIN', Icons.lock),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: const TextStyle(
                          color: AppColors.red, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () async {
                final actual = actualCtrl.text.trim();
                final nuevo = nuevoCtrl.text.trim();
                final confirm = confirmCtrl.text.trim();

                if (actual != _meseroData?['pin']) {
                  setDState(() => error = 'El PIN actual no coincide');
                  return;
                }
                if (nuevo.length != 4 || int.tryParse(nuevo) == null) {
                  setDState(() => error = 'El nuevo PIN debe ser de 4 dígitos');
                  return;
                }
                if (nuevo != confirm) {
                  setDState(() => error = 'Los PIN nuevos no coinciden');
                  return;
                }

                await FirebaseService.updateMesero(
                    widget.meseroDocId, {'pin': nuevo});
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Guardar',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerfilScreen() {
    if (_mostrandoHistorial) return _buildHistorialScreen();
    if (_esAdmin) return _buildAdminPanel();
    return _buildMeseroProfile();
  }

  Widget _buildMeseroProfile() {
    final pin = (_meseroData?['pin'] as String?) ?? '';
    final turno = (_meseroData?['turno'] as String?) ?? 'No asignado';
    final salonesAsignados = _meseroData?['salones'] is List
        ? List<String>.from(_meseroData!['salones'])
        : List<String>.from(_salones);
    final mesasActivas = _mesasData
        .where((m) =>
            m['status'] == 'ocupada' && m['salon'] == _salones[_selectedTab])
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _showFotoSelector,
            child: Stack(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.15),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.4)),
                  ),
                  child: ClipOval(
                    child: _fotoBase64 != null
                        ? Image.memory(
                            base64Decode(_fotoBase64!),
                            fit: BoxFit.cover,
                            width: 90,
                            height: 90,
                          )
                        : const Icon(Icons.person_outline,
                            color: AppColors.primary, size: 48),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.black, size: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.meseroNombre,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Mesero',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.meseroDocId,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _profileCard(
            icon: Icons.badge_outlined,
            title: 'ID de Empleado',
            child: Text(widget.meseroDocId,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
          const SizedBox(height: 8),
          _profileCard(
            icon: Icons.schedule_outlined,
            title: 'Turno / Horario',
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(turno,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _profileCard(
            icon: Icons.table_restaurant_outlined,
            title: 'Mesas Activas',
            child: Text('$mesasActivas mesas',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ),
          const SizedBox(height: 8),
          _profileCard(
            icon: Icons.bar_chart_rounded,
            title: 'Estadísticas del Día',
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Órdenes tomadas',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                    Text('$_ordenesHoy',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Total facturado',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                    Text('\$${_totalFacturadoHoy.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _profileCard(
            icon: Icons.room_outlined,
            title: 'Salones',
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: salonesAsignados
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.borderPrimary),
                        ),
                        child: Text(s,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          _profileCard(
            icon: Icons.lock_outline,
            title: 'PIN de Acceso',
            trailing: TextButton.icon(
              onPressed: _showChangePinDialog,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Cambiar',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
            child: Row(
              children: [
                Text(pin.isNotEmpty ? pin : 'No configurado',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: pin.isNotEmpty
                            ? AppColors.textPrimary
                            : AppColors.textMuted)),
                if (pin.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.visibility_outlined,
                      size: 16, color: AppColors.textMuted),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildUltimaAccion(),
          const SizedBox(height: 12),
          _buildHistorialNavCardMesero(),
          const SizedBox(height: 12),
          _buildCerrarSesion(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _profileCard({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5)),
                if (trailing != null) const Spacer(),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildUltimaAccion() {
    final c = _ultimoCambio;
    if (c == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: ListTile(
        leading: const Icon(Icons.history, color: AppColors.primary, size: 22),
        title: Text(c.descripcion,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        subtitle: Text(
          'Hace ${DateTime.now().difference(c.timestamp).inSeconds}s',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        trailing: TextButton(
          onPressed: _doUndo,
          child: const Text('Deshacer',
              style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
    );
  }

  Widget _buildCerrarSesion() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: const Text('Cerrar sesión',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.red.withOpacity(0.15),
          foregroundColor: AppColors.red,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    _sessionTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  // ─── ADMIN PANEL (secciones expandibles) ─────────────────────────────────────

  Widget _buildAdminPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _showFotoSelector,
                child: Stack(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withOpacity(0.15),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.4)),
                      ),
                      child: ClipOval(
                        child: _fotoBase64 != null
                            ? Image.memory(
                                base64Decode(_fotoBase64!),
                                fit: BoxFit.cover,
                                width: 44,
                                height: 44,
                              )
                            : const Icon(Icons.admin_panel_settings,
                                color: AppColors.primary, size: 24),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.black, size: 10),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Administración',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    _nombreRestaurante,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                widget.meseroNombre,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                _buildSectionMesas(),
                _buildSectionMeseros(),
                _buildSectionSalones(),
                _buildSectionMenu(),
                _buildSectionConfig(),
                _buildHistorialNavCard(),
                const SizedBox(height: 8),
                _buildUltimaAccion(),
                const SizedBox(height: 8),
                _buildCerrarSesion(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── SECCIÓN: MESAS ──────────────────────────────────────────────────────────

  Widget _buildSectionMesas() {
    return _adminSection(
      icon: Icons.table_restaurant_outlined,
      title: 'Gestión de Mesas',
      initiallyExpanded: true,
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _showAddMesaSheet,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Agregar Mesa',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                elevation: 0,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildAdminMesaList(),
        ],
      ),
    );
  }

  Widget _buildAdminMesaList() {
    return SizedBox(
      height: 200,
      child: StreamBuilder<List<MesaData>>(
        stream: FirebaseService.getMesasStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text('No hay mesas', style: TextStyle(color: AppColors.textMuted)),
            );
          }
          final mesas = snapshot.data!;
          return ListView.builder(
            itemCount: mesas.length,
            itemBuilder: (_, i) {
              final m = mesas[i];
              final c = _statusColor(m.status);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderPrimary),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(m.numero.toString().padLeft(2, '0'),
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900, color: c)),
                    ),
                  ),
                  title: Text('Mesa ${m.numero.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  subtitle: Text('${m.salon} · ${m.capacidad} pax · ${_statusLabel(m.status)}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _miniBtn(Icons.edit_outlined, () => _showEditMesaSheet(m)),
                      const SizedBox(width: 4),
                      _miniBtn(Icons.delete_outline, () => _confirmDeleteMesa(m)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 16),
      ),
    );
  }

  // ─── SECCIÓN: MESEROS ────────────────────────────────────────────────────────

  Widget _buildSectionMeseros() {
    return _adminSection(
      icon: Icons.people_outlined,
      title: 'Gestión de Personal',
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _showAddMeseroSheet,
              icon: const Icon(Icons.person_add_rounded, size: 20),
              label: const Text('Agregar Personal',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                elevation: 0,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: FirebaseService.getMeserosStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text('No hay meseros',
                        style: TextStyle(color: AppColors.textMuted)),
                  );
                }
                final meseros = snapshot.data!;
                return ListView.builder(
                  itemCount: meseros.length,
                  itemBuilder: (_, i) {
                    final m = meseros[i];
                    final activo = m['activo'] == true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderPrimary),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 0),
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: activo
                                ? AppColors.green.withOpacity(0.15)
                                : AppColors.textMuted.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: m['foto'] != null &&
                                    (m['foto'] as String).isNotEmpty
                                ? Image.memory(
                                    base64Decode(m['foto']),
                                    fit: BoxFit.cover,
                                    width: 36,
                                    height: 36,
                                  )
                                : Icon(Icons.person_outline,
                                    color: activo
                                        ? AppColors.green
                                        : AppColors.textMuted,
                                    size: 18),
                          ),
                        ),
                        title: Text(m['nombre'] ?? '',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        subtitle: Row(
                          children: [
                            Text(m['id'] ?? '',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textSecondary)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: (m['rol'] == 'admin'
                                        ? AppColors.primary
                                        : AppColors.blue)
                                    .withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                m['rol'] == 'admin' ? 'Admin' : 'Mesero',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: m['rol'] == 'admin'
                                      ? AppColors.primary
                                      : AppColors.blue,
                                ),
                              ),
                            ),
                            if (m['turno'] != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  m['turno'],
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                            if (!activo) ...[
                              const SizedBox(width: 6),
                              const Text('Inactivo',
                                  style: TextStyle(
                                      fontSize: 10, color: AppColors.red)),
                            ],
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _miniBtn(
                                Icons.edit_outlined, () => _showEditMeseroSheet(m)),
                            if (m['id'] != 'ADMIN')
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: _miniBtn(Icons.delete_outline,
                                    () => _confirmDeleteMesero(m)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMeseroSheet() {
    final idCtrl = TextEditingController();
    final nombreCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String rol = 'mesero';
    String turno = 'Matutino';
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.borderPrimary),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                24, 20, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('NUEVO MESERO',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary, letterSpacing: 1.5)),
                const SizedBox(height: 16),
                TextField(
                    controller: idCtrl,
                    decoration: _inputDecoration('ID (ej: M003)', Icons.badge_outlined)),
                const SizedBox(height: 12),
                TextField(
                    controller: nombreCtrl,
                    decoration: _inputDecoration('Nombre completo', Icons.person_outline)),
                const SizedBox(height: 12),
                TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: _inputDecoration('PIN (4 dígitos)', Icons.lock_outline)),
                const SizedBox(height: 4),
                _buildDropdown(
                  value: rol,
                  items: const ['mesero', 'admin'],
                  icon: Icons.admin_panel_settings_outlined,
                  label: (v) => v == 'admin' ? 'Administrador' : 'Mesero',
                  onChanged: (v) {
                    if (v != null) setSheetState(() => rol = v);
                  },
                ),
                const SizedBox(height: 10),
                _buildDropdown(
                  value: turno,
                  items: const ['Matutino', 'Vespertino', 'Nocturno'],
                  icon: Icons.schedule_outlined,
                  label: (v) => v,
                  onChanged: (v) {
                    if (v != null) setSheetState(() => turno = v);
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            final id = idCtrl.text.trim();
                            final nombre = nombreCtrl.text.trim();
                            if (id.isEmpty || nombre.isEmpty) return;
                            setSheetState(() => isLoading = true);
                            await FirebaseService.createMesero(
                                id, nombre, pinCtrl.text.trim(), rol, turno: turno);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: AppColors.primaryDim,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.black54, strokeWidth: 2.5))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_add_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('Crear Mesero',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditMeseroSheet(Map<String, dynamic> mesero) {
    final nombreCtrl =
        TextEditingController(text: mesero['nombre'] ?? '');
    final pinCtrl = TextEditingController(text: mesero['pin'] ?? '');
    String rol = mesero['rol'] ?? 'mesero';
    String turno = mesero['turno'] ?? 'Matutino';
    bool activo = mesero['activo'] == true;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.borderPrimary),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                24, 20, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('EDITAR ${mesero['id'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary, letterSpacing: 1.5)),
                const SizedBox(height: 16),
                TextField(
                    controller: nombreCtrl,
                    decoration: _inputDecoration(
                        'Nombre completo', Icons.person_outline)),
                const SizedBox(height: 12),
                TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: _inputDecoration(
                        'PIN (dejar vacío para quitar)', Icons.lock_outline)),
                const SizedBox(height: 4),
                _buildDropdown(
                  value: rol,
                  items: const ['mesero', 'admin'],
                  icon: Icons.admin_panel_settings_outlined,
                  label: (v) => v == 'admin' ? 'Administrador' : 'Mesero',
                  onChanged: (v) {
                    if (v != null) setSheetState(() => rol = v);
                  },
                ),
                const SizedBox(height: 10),
                _buildDropdown(
                  value: turno,
                  items: const ['Matutino', 'Vespertino', 'Nocturno'],
                  icon: Icons.schedule_outlined,
                  label: (v) => v,
                  onChanged: (v) {
                    if (v != null) setSheetState(() => turno = v);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.textPrimary)),
                  value: activo,
                  activeColor: AppColors.green,
                  onChanged: (v) => setSheetState(() => activo = v),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            final nombre = nombreCtrl.text.trim();
                            if (nombre.isEmpty) return;
                            setSheetState(() => isLoading = true);
                            final data = <String, dynamic>{
                              'nombre': nombre,
                              'rol': rol,
                              'turno': turno,
                              'activo': activo,
                            };
                            final pin = pinCtrl.text.trim();
                            if (pin.isNotEmpty) {
                              data['pin'] = pin;
                            } else {
                              data['pin'] = FieldValue.delete();
                            }
                            await FirebaseService.updateMesero(
                                mesero['docId'], data);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: AppColors.primaryDim,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.black54, strokeWidth: 2.5))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('Guardar Cambios',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteMesero(Map<String, dynamic> mesero) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderPrimary),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.red, size: 24),
            SizedBox(width: 10),
            Text('Eliminar Mesero',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
        content: Text(
          '¿Eliminar a ${mesero['nombre']} (${mesero['id']})?\n\n'
          'Esta acción no se puede deshacer.',
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseService.deleteMesero(mesero['docId']);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Eliminar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ─── SECCIÓN: SALONES ────────────────────────────────────────────────────────

  Widget _buildSectionSalones() {
    return _adminSection(
      icon: Icons.room_outlined,
      title: 'Gestión de Salones',
      child: StreamBuilder<Map<String, dynamic>?>(
        stream: FirebaseService.getConfigStream(),
        builder: (context, snap) {
          final salones = snap.data?['salones'] is List
              ? List<String>.from(snap.data!['salones'])
              : _salones;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...salones.map((s) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderPrimary),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.room_outlined,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(s,
                              style: const TextStyle(
                                  fontSize: 14, color: AppColors.textPrimary)),
                        ),
                        GestureDetector(
                          onTap: () => _editSalon(s),
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.edit_outlined,
                                color: AppColors.textSecondary, size: 14),
                          ),
                        ),
                        if (salones.length > 1) ...[
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _deleteSalon(s),
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.close,
                                  color: AppColors.red, size: 14),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: _showAddSalonSheet,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Agregar Salón',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddSalonSheet() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderPrimary),
        ),
        title: const Text('Nuevo Salón',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: _inputDecoration('Nombre del salón', Icons.room_outlined),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              final nombre = ctrl.text.trim();
              if (nombre.isEmpty) return;
              final nuevos = List<String>.from(_salones)..add(nombre);
              await FirebaseService.saveConfig({'salones': nuevos});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Agregar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _editSalon(String oldName) {
    final ctrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderPrimary),
        ),
        title: const Text('Renombrar Salón',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: _inputDecoration('Nombre del salón', Icons.room_outlined),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              final nuevo = ctrl.text.trim();
              if (nuevo.isEmpty || nuevo == oldName) {
                if (ctx.mounted) Navigator.pop(ctx);
                return;
              }
              final nuevos = _salones.map((s) => s == oldName ? nuevo : s).toList();
              await FirebaseService.saveConfig({'salones': nuevos});
              await FirebaseService.updateMesasSalon(oldName, nuevo);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Guardar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _deleteSalon(String salon) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderPrimary),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.red, size: 24),
            SizedBox(width: 10),
            Text('Eliminar Salón',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
        content: Text(
          '¿Eliminar "$salon"?\n\n'
          'Las mesas asignadas a este salón conservarán\n'
          'el nombre actual como texto.',
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              final nuevos = _salones.where((s) => s != salon).toList();
              await FirebaseService.saveConfig({'salones': nuevos});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Eliminar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ─── SECCIÓN: MENÚ ────────────────────────────────────────────────────────────

  Widget _buildSectionMenu() {
    final List<String> secciones = List.from(_menuSecciones);
    return _adminSection(
      icon: Icons.menu_book_rounded,
      title: 'Gestión de Menú',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...secciones.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderPrimary),
                ),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_rounded,
                        size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s,
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textPrimary)),
                    ),
                    GestureDetector(
                      onTap: () => _showRenameSeccionDialog(s),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.edit_outlined,
                            color: AppColors.textSecondary, size: 14),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _confirmDeleteSeccion(s),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.close,
                            color: AppColors.red, size: 14),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _showAddSeccionSheet,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Agregar Sección',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddSeccionSheet() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderPrimary),
        ),
        title: const Text('Nueva Sección',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: _inputDecoration('Nombre de la sección', Icons.label_outline),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              final nombre = ctrl.text.trim();
              if (nombre.isEmpty) return;
              final updated = [..._menuSecciones, nombre];
              await FirebaseService.saveConfig({'menuSecciones': updated});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Agregar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showRenameSeccionDialog(String oldName) {
    final ctrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderPrimary),
        ),
        title: const Text('Renombrar Sección',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: _inputDecoration('Nombre de la sección', Icons.label_outline),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty || newName == oldName) {
                if (ctx.mounted) Navigator.pop(ctx);
                return;
              }
              final idx = _menuSecciones.indexOf(oldName);
              if (idx == -1) return;
              await FirebaseService.updatePlatilloSeccion(oldName, newName);
              setState(() {
                _menuSecciones[idx] = newName;
                _menuSeccionFilter = null;
              });
              await FirebaseService.saveConfig({'menuSecciones': _menuSecciones});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Guardar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSeccion(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderPrimary),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.red, size: 24),
            SizedBox(width: 10),
            Text('Eliminar Sección',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
        content: Text(
          '¿Eliminar la sección "$name"?\n\n'
          'Los platillos de esta sección se moverán\na la primera sección disponible.',
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Eliminar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final updated = List<String>.from(_menuSecciones)..remove(name);
      final fallback = updated.isNotEmpty ? updated.first : 'Sin categoría';
      if (fallback != name) {
        await FirebaseService.updatePlatilloSeccion(name, fallback);
      }
      setState(() {
        _menuSecciones = updated;
      });
      await FirebaseService.saveConfig({'menuSecciones': updated});
    }
  }

  // ─── SECCIÓN: CONFIGURACIÓN ───────────────────────────────────────────────────

  Widget _buildSectionConfig() {
    final nombreCtrl = TextEditingController(text: _nombreRestaurante);
    final capCtrl =
        TextEditingController(text: _capacidadDefault.toString());
    bool isLoading = false;

    return _adminSection(
      icon: Icons.settings_outlined,
      title: 'Configuración',
      child: StatefulBuilder(
        builder: (ctx, setLocalState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: _inputDecoration(
                  'Nombre del restaurante', Icons.store_outlined),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: capCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration(
                  'Capacidad default (pax)', Icons.chair_outlined),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final cap = int.tryParse(capCtrl.text);
                        if (cap == null || cap < 1) return;
                        setLocalState(() => isLoading = true);
                        await FirebaseService.saveConfig({
                          'nombreRestaurante': nombreCtrl.text.trim(),
                          'capacidadDefault': cap,
                        });
                        setLocalState(() => isLoading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: const Text('Configuración guardada'),
                              backgroundColor: AppColors.green,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppColors.primaryDim,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.black54, strokeWidth: 2.5))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Guardar Configuración',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SECCIÓN: HISTORIAL ──────────────────────────────────────────────────────

  // ─── HISTORIAL ──────────────────────────────────────────────────────────────────

  Widget _buildHistorialScreen() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() {
              _mostrandoHistorial = false;
              _historialMesaSeleccionada = null;
            }),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back, color: AppColors.primary, size: 22),
                SizedBox(width: 8),
                Text('Historial de Actividad',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<HistorialEvento>>(
              stream: FirebaseService.getHistorialStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                var eventos = snapshot.data!;
                if (!_esAdmin) {
                  eventos = eventos
                      .where((e) => e.usuario == widget.meseroNombre)
                      .toList();
                }
                if (eventos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.history_rounded,
                            size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 12),
                        const Text('Sin actividad registrada',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14)),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => setState(() {
                            _mostrandoHistorial = false;
                            _historialMesaSeleccionada = null;
                          }),
                          icon: const Icon(Icons.arrow_back,
                              size: 18),
                          label: const Text('Regresar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                if (_historialMesaSeleccionada == null) {
                  return SingleChildScrollView(
                      child: _buildMesaHistorialList(eventos));
                }
                return _buildMesaHistorialDetail(eventos);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorialNavCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.history_rounded,
              color: AppColors.primary, size: 22),
        ),
        title: const Text('Historial de Actividad',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontSize: 14)),
        trailing: const Icon(Icons.chevron_right,
            color: AppColors.textMuted, size: 22),
        onTap: () =>
            setState(() => _mostrandoHistorial = true),
      ),
    );
  }

  Widget _buildHistorialNavCardMesero() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.history_rounded,
              color: AppColors.primary, size: 22),
        ),
        title: const Text('Historial',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontSize: 14)),
        subtitle: const Text('Cambios por mesa',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        trailing: const Icon(Icons.chevron_right,
            color: AppColors.textMuted, size: 22),
        onTap: () =>
            setState(() => _mostrandoHistorial = true),
      ),
    );
  }

  Widget _buildMesaHistorialList(List<HistorialEvento> eventos) {
    final mesaMap = <int, List<HistorialEvento>>{};
    for (final e in eventos) {
      final n = e.datos['mesaNumero'] ?? e.datos['numero'];
      if (n is int) {
        mesaMap.putIfAbsent(n, () => []).add(e);
      }
    }
    final mesas = mesaMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(Icons.table_restaurant_outlined,
                  size: 14, color: AppColors.textMuted),
              SizedBox(width: 6),
              Text('Selecciona una mesa',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ),
        ...mesas.map((entry) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderPrimary),
              ),
              child: ListTile(
                dense: true,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${entry.key}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            fontSize: 14)),
                  ),
                ),
                title: Text('Mesa ${entry.key}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontSize: 13)),
                subtitle: Text('${entry.value.length} cambios',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.textMuted, size: 20),
                onTap: () =>
                    setState(() => _historialMesaSeleccionada = entry.key),
              ),
            )),
      ],
    );
  }

  Widget _buildMesaHistorialDetail(List<HistorialEvento> eventos) {
    final mesaEventos = eventos.where((e) {
      final n = e.datos['mesaNumero'] ?? e.datos['numero'];
      return n == _historialMesaSeleccionada;
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _historialMesaSeleccionada = null),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: const Icon(Icons.arrow_back,
                      size: 20, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 8),
              Text('Mesa $_historialMesaSeleccionada',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const Spacer(),
              Text('${mesaEventos.length} cambios',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: mesaEventos.length,
            itemBuilder: (_, i) => _buildHistorialEventCard(mesaEventos[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildHistorialEventCard(HistorialEvento e) {
    final puedeRevertir = e.tipo != 'mesa_eliminada';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_historialIcon(e.tipo), size: 16, color: _historialColor(e.tipo)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(e.descripcion,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${e.usuario} · ${_formatTimestamp(e.timestamp)}',
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textMuted),
              ),
              const Spacer(),
              if (puedeRevertir)
                GestureDetector(
                  onTap: () => _revertirEvento(e),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Revertir',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _revertirEvento(HistorialEvento e) async {
    switch (e.tipo) {
      case 'cambio_estado':
        final docId = e.datos['docId'] as String?;
        final oldStatus = e.datos['oldStatus'] as String?;
        if (docId == null || oldStatus == null || oldStatus.isEmpty) return;
        await FirebaseService.updateMesaStatus(docId, oldStatus,
            usuario: widget.meseroNombre,
            mesaNumero: e.datos['mesaNumero'] ?? 0);
        break;
      case 'mesa_creada':
        final numero = e.datos['numero'] as int?;
        if (numero == null) return;
        final mesas = await FirebaseService.getMesasStream().first;
        final mesa = mesas.where((m) => m.numero == numero).firstOrNull;
        if (mesa == null) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.bgCard,
            title: const Text('Revertir creación',
                style: TextStyle(color: AppColors.textPrimary)),
            content: Text('¿Eliminar la Mesa $numero?',
                style: const TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Eliminar',
                    style: TextStyle(color: AppColors.red)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await FirebaseService.deleteMesa(mesa.docId,
              usuario: widget.meseroNombre, mesaNumero: numero);
        }
        break;
      case 'mesa_modificada':
        final docId = e.datos['docId'] as String?;
        final oldData = e.datos['oldData'] as Map<String, dynamic>?;
        if (docId == null || oldData == null) return;
        final revertData = Map<String, dynamic>.from(oldData);
        revertData.remove('orden');
        revertData.remove('ocupadaDesde');
        revertData.remove('timestamp');
        await FirebaseService.updateMesa(docId, revertData,
            usuario: widget.meseroNombre,
            mesaNumero: e.datos['mesaNumero'] ?? 0);
        break;
    }
  }

  IconData _historialIcon(String tipo) {
    switch (tipo) {
      case 'cambio_estado':
        return Icons.swap_horiz_rounded;
      case 'mesa_creada':
        return Icons.add_circle_outline;
      case 'mesa_eliminada':
        return Icons.remove_circle_outline;
      case 'mesa_modificada':
        return Icons.edit_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _historialColor(String tipo) {
    switch (tipo) {
      case 'cambio_estado':
        return AppColors.blue;
      case 'mesa_creada':
        return AppColors.green;
      case 'mesa_eliminada':
        return AppColors.red;
      case 'mesa_modificada':
        return AppColors.primary;
      default:
        return AppColors.textMuted;
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ─── ADMIN: widget sección expandible ────────────────────────────────────────

  Widget _adminSection({
    required IconData icon,
    required String title,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          unselectedWidgetColor: AppColors.textSecondary,
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding:
              const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(icon, color: AppColors.primary, size: 22),
          title: Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          children: [child],
        ),
      ),
    );
  }

  // ─── ADMIN: métodos compartidos de formularios ───────────────────────────────

  void _showAddMesaSheet() {
    final numeroCtrl = TextEditingController();
    final capacidadCtrl =
        TextEditingController(text: _capacidadDefault.toString());
    String salonSeleccionado = _salones.isNotEmpty ? _salones.first : 'Salón Principal';
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.borderPrimary),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                24, 20, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('NUEVA MESA',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary, letterSpacing: 1.5)),
                const SizedBox(height: 16),
                TextField(
                    controller: numeroCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(
                        'Número de mesa', Icons.table_restaurant_outlined)),
                const SizedBox(height: 12),
                TextField(
                    controller: capacidadCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(
                        'Capacidad (personas)', Icons.chair_outlined)),
                const SizedBox(height: 12),
                _buildDropdown(
                  value: salonSeleccionado,
                  items: _salones,
                  icon: Icons.room_outlined,
                  onChanged: (v) {
                    if (v != null) setSheetState(() => salonSeleccionado = v);
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            final num = int.tryParse(numeroCtrl.text);
                            final cap = int.tryParse(capacidadCtrl.text);
                            if (num == null || cap == null || cap < 1) return;
                            setSheetState(() => isLoading = true);
                            await FirebaseService.createMesa(
                                num, cap, salonSeleccionado,
                                usuario: widget.meseroNombre);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              _showStatusNotification(MesaStatus.libre, num);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: AppColors.primaryDim,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.black54, strokeWidth: 2.5))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('Crear Mesa',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditMesaSheet(MesaData mesa) {
    final numeroCtrl =
        TextEditingController(text: mesa.numero.toString());
    final capacidadCtrl =
        TextEditingController(text: mesa.capacidad.toString());
    String salonSeleccionado = mesa.salon;
    String statusSeleccionado = mesa.status.value;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.borderPrimary),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                24, 20, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                    'EDITAR MESA ${mesa.numero.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary, letterSpacing: 1.5)),
                const SizedBox(height: 16),
                TextField(
                    controller: numeroCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(
                        'Número de mesa', Icons.table_restaurant_outlined)),
                const SizedBox(height: 12),
                TextField(
                    controller: capacidadCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(
                        'Capacidad (personas)', Icons.chair_outlined)),
                const SizedBox(height: 12),
                _buildDropdown(
                  value: salonSeleccionado,
                  items: _salones,
                  icon: Icons.room_outlined,
                  onChanged: (v) {
                    if (v != null) setSheetState(() => salonSeleccionado = v);
                  },
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  value: statusSeleccionado,
                  items: const ['libre', 'ocupada', 'pago', 'reservada'],
                  icon: Icons.circle_outlined,
                  label: (v) {
                    switch (v) {
                      case 'libre': return 'Libre';
                      case 'ocupada': return 'Ocupada';
                      case 'pago': return 'Pago';
                      case 'reservada': return 'Reservada';
                      default: return v;
                    }
                  },
                  onChanged: (v) {
                    if (v != null) setSheetState(() => statusSeleccionado = v);
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            final num = int.tryParse(numeroCtrl.text);
                            final cap = int.tryParse(capacidadCtrl.text);
                            if (num == null || cap == null || cap < 1) return;
                            setSheetState(() => isLoading = true);
                            await FirebaseService.updateMesa(mesa.docId, {
                              'numero': num,
                              'capacidad': cap,
                              'salon': salonSeleccionado,
                              'status': statusSeleccionado,
                            }, usuario: widget.meseroNombre, mesaNumero: mesa.numero);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              _showStatusNotification(
                                  MesaStatusExt.fromString(statusSeleccionado),
                                  num);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: AppColors.primaryDim,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.black54, strokeWidth: 2.5))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('Guardar Cambios',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteMesa(MesaData mesa) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderPrimary),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.red, size: 24),
            SizedBox(width: 10),
            Text('Eliminar Mesa',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
        content: Text(
          '¿Estás seguro de eliminar la Mesa ${mesa.numero.toString().padLeft(2, '0')}?\n\n'
          'Esta acción no se puede deshacer.',
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseService.deleteMesa(mesa.docId,
                  usuario: widget.meseroNombre,
                  mesaNumero: mesa.numero);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                _showStatusNotification(MesaStatus.libre, mesa.numero);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Eliminar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      hintText: label,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required IconData icon,
    required void Function(String?) onChanged,
    String Function(String)? label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
          ),
          items: items.map((s) {
            return DropdownMenuItem(
              value: s,
              child: Row(
                children: [
                  Icon(icon, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(label != null ? label(s) : s),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ─── REPORTES ────────────────────────────────────────────────────────────────

  Widget _buildReportesScreen() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.15),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.4)),
                ),
                child: const Icon(Icons.bar_chart_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 10),
              const Text('Reportes',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 20),
          StreamBuilder<List<MesaData>>(
            stream: FirebaseService.getMesasStream(),
            builder: (context, snapshot) {
              final mesas = snapshot.data ?? [];
              final total = mesas.length;
              final libres =
                  mesas.where((m) => m.status == MesaStatus.libre).length;
              final ocupadas =
                  mesas.where((m) => m.status == MesaStatus.ocupada).length;
              final pagos =
                  mesas.where((m) => m.status == MesaStatus.pago).length;
              final reservadas =
                  mesas.where((m) => m.status == MesaStatus.reservada).length;

              return Expanded(
                child: ListView(
                  children: [
                    _buildReportCard(
                      'Resumen de Mesas',
                      Icons.table_restaurant_outlined,
                      [
                        _statItem(
                            'Libres', libres, total, AppColors.green),
                        _statItem(
                            'Ocupadas', ocupadas, total, AppColors.orange),
                        _statItem('Pago', pagos, total, AppColors.red),
                        _statItem('Reservadas', reservadas,
                            total, AppColors.blue),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildReportCard(
                      'Ocupación por Salón',
                      Icons.room_outlined,
                      _salones.map((s) {
                        const statuses = [
                          MesaStatus.ocupada,
                          MesaStatus.pago
                        ];
                        final count = mesas
                            .where((m) =>
                                m.salon == s && statuses.contains(m.status))
                            .length;
                        final totalSalon =
                            mesas.where((m) => m.salon == s).length;
                        return _statItem(
                            s, count, totalSalon, AppColors.orange);
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _buildMeserosActivosCard(),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(
      String title, IconData icon, List<Widget> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          ...items,
        ],
      ),
    );
  }

  Widget _statItem(String label, int count, int total, Color color) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              Text('$count${total > 0 ? '/$total' : ''}',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeserosActivosCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirebaseService.getMeserosStream(),
        builder: (context, snapshot) {
          final meseros = snapshot.data ?? [];
          final activos = meseros.where((m) => m['activo'] == true).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.people_outlined, color: AppColors.primary, size: 18),
                  SizedBox(width: 8),
                  Text('Personal Activo',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 12),
              if (activos.isEmpty)
                const Text('Sin personal activo',
                    style: TextStyle(color: AppColors.textMuted))
              else
                ...activos.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(m['nombre'] ?? '',
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.textPrimary)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (m['rol'] == 'admin'
                                      ? AppColors.primary
                                      : AppColors.blue)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              m['rol'] == 'admin' ? 'Admin' : 'Mesero',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: m['rol'] == 'admin'
                                    ? AppColors.primary
                                    : AppColors.blue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('(${m['id'] ?? ''})',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _navIndex == 4
            ? _buildPerfilScreen()
            : _navIndex == 3
                ? _buildReportesScreen()
                : _navIndex == 1
                    ? _buildMenuScreen()
                    : _buildMesasContent(),
      ),
      floatingActionButton:
          _navIndex == 0 || _navIndex == 1 ? _buildFAB() : null,
      bottomNavigationBar: _buildNavBar(),
    );
  }

  Widget _buildMesasContent() {
    return Column(
      children: [
        _buildHeader(),
        _buildSalonTabs(),
        Expanded(child: _buildMesaGrid()),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: _isSearching ? _buildSearchField() : _buildNormalHeader(),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar mesa por número...',
          hintStyle: TextStyle(
              color: AppColors.textMuted.withOpacity(0.7),
              fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded,
              color: AppColors.textMuted, size: 20),
          suffixIcon: GestureDetector(
            onTap: () {
              setState(() {
                _isSearching = false;
                _searchController.clear();
              });
            },
            child: const Icon(Icons.close_rounded,
                color: AppColors.textMuted, size: 20),
          ),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildNormalHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => _navIndex = 4),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.15),
              border: Border.all(
                  color: AppColors.primary.withOpacity(0.4)),
            ),
            child: ClipOval(
              child: _fotoBase64 != null
                  ? Image.memory(
                      base64Decode(_fotoBase64!),
                      fit: BoxFit.cover,
                      width: 40,
                      height: 40,
                    )
                  : const Icon(Icons.person_outline,
                      color: AppColors.primary, size: 22),
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sync_rounded,
                      color: AppColors.primary, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'ServeSync',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _OnlineDot(),
                  const SizedBox(width: 5),
                  Text(
                    '${widget.meseroNombre} · En línea',
                    style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
        _IconBtn(
          icon: Icons.search_rounded,
          onTap: () => setState(() => _isSearching = true),
        ),
      ],
    );
  }

  Widget _buildSalonTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mapa de Mesas',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: _salones.asMap().entries.map((e) {
                final selected = e.key == _selectedTab;
                return Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _selectedTab = e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.bgCard
                            : Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(11),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: Colors.black
                                      .withOpacity(0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        e.value,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final items = [
      (AppColors.green, 'Libre'),
      (AppColors.orange, 'Ocupada'),
      (AppColors.red, 'Pago'),
      (AppColors.blue, 'Reservada'),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: items
          .map((e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: e.$1,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(e.$2,
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500)),
                ],
              ))
          .toList(),
    );
  }

  Widget _buildMesaGrid() {
    return StreamBuilder<List<MesaData>>(
      stream: FirebaseService.getMesasStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 16),
                Text('Sincronizando mesas...',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14)),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off,
                    color: AppColors.red, size: 48),
                const SizedBox(height: 12),
                const Text('Sin conexión a Firebase',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  'Verifica tu google-services.json\ny la configuración de Firebase',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13),
                ),
              ],
            ),
          );
        }

        final allMesas = snapshot.data ?? [];
        final query = _searchController.text.trim();
        final filteredMesas = allMesas
            .where((m) => m.salon == _salones[_selectedTab])
            .where((m) => query.isEmpty || m.numero.toString().contains(query))
            .toList();

        return Column(
          children: [
            _buildSummaryBar(allMesas),
            Expanded(
              child: allMesas.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.table_restaurant,
                              color: AppColors.textMuted, size: 56),
                          SizedBox(height: 12),
                          Text('No hay mesas registradas',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 15)),
                        ],
                      ),
                    )
                  : filteredMesas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.filter_none,
                                  color: AppColors.textMuted, size: 56),
                              const SizedBox(height: 12),
                              Text('Sin mesas en ${_salones[_selectedTab]}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 15)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            setState(() {});
                          },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 200,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.88,
                              ),
                              itemCount: filteredMesas.length,
                              itemBuilder: (_, i) => _MesaCard(
                                mesa: filteredMesas[i],
                                statusColor: _statusColor(filteredMesas[i].status),
                                statusLabel: _statusLabel(filteredMesas[i].status),
                                statusIcon: _statusIcon(filteredMesas[i].status),
                                onTap: () => _showMesaDetail(filteredMesas[i]),
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryBar(List<MesaData> mesas) {
    final counts = {
      MesaStatus.libre: mesas.where((m) => m.status == MesaStatus.libre).length,
      MesaStatus.ocupada: mesas.where((m) => m.status == MesaStatus.ocupada).length,
      MesaStatus.pago: mesas.where((m) => m.status == MesaStatus.pago).length,
      MesaStatus.reservada: mesas.where((m) => m.status == MesaStatus.reservada).length,
    };
    final items = [
      (AppColors.green, 'Libre', counts[MesaStatus.libre]!),
      (AppColors.orange, 'Ocupada', counts[MesaStatus.ocupada]!),
      (AppColors.red, 'Pago', counts[MesaStatus.pago]!),
      (AppColors.blue, 'Reservada', counts[MesaStatus.reservada]!),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: items.map((e) {
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: e.$3 > 0
                      ? e.$1.withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      '${e.$3}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: e.$3 > 0 ? e.$1 : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      e.$2,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: e.$3 > 0
                            ? e.$1.withOpacity(0.7)
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    final isMenuTab = _navIndex == 1;
    if (isMenuTab && !_esAdmin) return const SizedBox.shrink();
    final label = isMenuTab ? 'Agregar Platillo' : 'Nueva Orden';
    final onTap = isMenuTab ? _showPlatilloForm : _showNuevaOrdenSheet;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: onTap,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: Text(
          label,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }

  // ─── MENÚ (TAB 1) ─────────────────────────────────────────────────────────────

  Widget _buildMenuScreen() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.15),
                ),
                child: const Icon(Icons.menu_book_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('Menú del Restaurante',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _menuSearchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: _inputDecoration(
                'Buscar platillo...', Icons.search),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildMenuFilterChip('Todas', null),
                ..._menuSecciones.map(
                    (s) => _buildMenuFilterChip(s, s)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<Platillo>>(
              stream: FirebaseService.getPlatillosStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                var platillos = snapshot.data!;
                final query = _menuSearchCtrl.text.toLowerCase();
                if (query.isNotEmpty || _menuSeccionFilter != null) {
                  platillos = platillos.where((p) {
                    if (_menuSeccionFilter != null &&
                        p.seccion != _menuSeccionFilter) {
                      return false;
                    }
                    if (query.isNotEmpty &&
                        !p.nombre.toLowerCase().contains(query)) {
                      return false;
                    }
                    return true;
                  }).toList();
                }
                if (platillos.isEmpty) {
                  if (_menuSeccionFilter != null && snapshot.data!.isNotEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync,
                              size: 48, color: AppColors.textMuted),
                          SizedBox(height: 12),
                          Text('Actualizando sección…',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 14)),
                        ],
                      ),
                    );
                  }
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restaurant_menu,
                            size: 48, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text('No hay platillos en el menú',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 14)),
                      ],
                    ),
                  );
                }
                // Group by seccion
                final grouped = <String, List<Platillo>>{};
                final targetSection = _menuSecciones.isNotEmpty
                    ? _menuSecciones.first
                    : 'Sin categoría';
                for (final p in platillos) {
                  final key =
                      _menuSecciones.contains(p.seccion) ? p.seccion : targetSection;
                  grouped.putIfAbsent(key, () => []).add(p);
                }
                final order = _menuSecciones
                    .where((s) => grouped.containsKey(s))
                    .toList();
                return ListView(
                  padding: const EdgeInsets.only(bottom: 80),
                  children: order.map((seccion) {
                    final items = grouped[seccion]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 3, height: 16,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(seccion,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary)),
                              const Spacer(),
                              Text('${items.length}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: items.length,
                          itemBuilder: (_, i) =>
                              _buildPlatilloCard(items[i]),
                        ),
                      ],
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatilloCard(Platillo p) {
    return GestureDetector(
      onTap: _esAdmin ? () => _showPlatilloForm(p) : () => _showPlatilloDetails(p),
      onLongPress: null,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderPrimary),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: AppColors.surface,
                    child: p.foto != null && p.foto!.isNotEmpty
                        ? Image.memory(
                            base64Decode(p.foto!),
                            fit: BoxFit.cover,
                          )
                        : Center(
                            child: Icon(Icons.restaurant,
                                color: AppColors.textMuted.withOpacity(0.3),
                                size: 40),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(p.descripcion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted)),
                      const SizedBox(height: 6),
                      Text('\$${p.precio.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_esAdmin)
            Positioned(
              top: 4, right: 4,
              child: GestureDetector(
                onTap: () => _confirmDeletePlatillo(p),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.close,
                      size: 16, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuFilterChip(String label, String? value) {
    final selected = _menuSeccionFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary)),
        selected: selected,
        onSelected: (_) =>
            setState(() => _menuSeccionFilter = value),
        selectedColor: AppColors.primary.withOpacity(0.3),
        backgroundColor: AppColors.bgCard,
      ),
    );
  }

  void _showPlatilloForm([Platillo? existing]) {
    if (!_esAdmin) return;
    final nombreCtrl = TextEditingController(text: existing?.nombre ?? '');
    final descCtrl =
        TextEditingController(text: existing?.descripcion ?? '');
    final precioCtrl =
        TextEditingController(text: existing?.precio.toStringAsFixed(0) ?? '');
    String? fotoBase64 = existing?.foto;
    final isEditing = existing != null;
    String seccion =
        existing?.seccion ?? (_menuSecciones.isNotEmpty ? _menuSecciones.first : 'Platillos');

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => SingleChildScrollView(
          child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 24, right: 24, top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(isEditing ? 'Editar Platillo' : 'Nuevo Platillo',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 512, maxHeight: 512, imageQuality: 80,
                  );
                  if (picked != null) {
                    final bytes = await picked.readAsBytes();
                    setLocalState(() => fotoBase64 = base64Encode(bytes));
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: 140,
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderPrimary),
                  ),
                  child: fotoBase64 != null && fotoBase64!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            base64Decode(fotoBase64!),
                            fit: BoxFit.cover, width: double.infinity,
                          ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                color: AppColors.textMuted, size: 36),
                            SizedBox(height: 6),
                            Text('Agregar foto',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 13)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nombreCtrl,
                decoration: _inputDecoration(
                    'Nombre del platillo', Icons.restaurant_outlined),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: _inputDecoration(
                    'Descripción', Icons.description_outlined),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: precioCtrl,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(
                    'Precio (\$)', Icons.attach_money_outlined),
              ),
              const SizedBox(height: 10),
              _buildDropdown(
                value: seccion,
                items: _menuSecciones,
                icon: Icons.category_outlined,
                label: (v) => v,
                onChanged: (v) {
                  if (v != null) setLocalState(() => seccion = v);
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final nombre = nombreCtrl.text.trim();
                    final desc = descCtrl.text.trim();
                    final precio = double.tryParse(precioCtrl.text);
                    if (nombre.isEmpty || precio == null || precio <= 0) return;
                    if (isEditing) {
                      final cambios = <String, dynamic>{
                        'nombre': nombre, 'descripcion': desc,
                        'precio': precio, 'foto': fotoBase64 ?? '',
                        'seccion': seccion,
                      };
                      await FirebaseService.updatePlatillo(
                        existing.docId, cambios,
                      );
                      final cambiosSync = <String, dynamic>{};
                      if (existing.nombre != nombre) cambiosSync['nombre'] = nombre;
                      if (existing.precio != precio) cambiosSync['precio'] = precio;
                      if (cambiosSync.isNotEmpty) {
                        await FirebaseService.updatePlatilloInAllOrdenes(
                          existing.docId, cambiosSync,
                        );
                      }
                    } else {
                      await FirebaseService.createPlatillo(
                        nombre, desc, precio,
                        foto: fotoBase64,
                        seccion: seccion,
                      );
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isEditing ? 'Guardar' : 'Crear Platillo',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _confirmDeletePlatillo(Platillo p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderPrimary),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.red, size: 24),
            SizedBox(width: 10),
            Text('Eliminar Platillo',
                style: TextStyle(color: AppColors.textPrimary)),
          ],
        ),
        content: Text('¿Eliminar "${p.nombre}" del menú?',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseService.deletePlatillo(p.docId);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Eliminar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showPlatilloDetails(Platillo p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24, right: 24, top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.textMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (p.foto != null && p.foto!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  base64Decode(p.foto!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 180,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(p.nombre,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ),
                const SizedBox(width: 12),
                Text('\$${p.precio.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(p.seccion,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
            ),
            if (p.descripcion.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(p.descripcion,
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Cerrar',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ─── NUEVA ORDEN ──────────────────────────────────────────────────────────────

  void _showNuevaOrdenSheet() async {
    final mesasSnapshot =
        await FirebaseService.getMesasStream().first;
    final libres =
        mesasSnapshot.where((m) => m.status == MesaStatus.libre).toList();
    final ocupadas =
        mesasSnapshot.where((m) => m.status == MesaStatus.ocupada).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.textMuted.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text('Seleccionar Mesa',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            if (libres.isNotEmpty) ...[
              const Text('Mesas libres:',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.green, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ...libres.map((m) => ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text('${m.numero}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.green, fontSize: 14)),
                      ),
                    ),
                    title: Text('Mesa ${m.numero}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.textPrimary)),
                    subtitle: Text('${m.capacidad} pax · ${m.salon}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Libre',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.green,
                              fontWeight: FontWeight.w600)),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _startOrden(m);
                    },
                  )),
              if (ocupadas.isNotEmpty) const SizedBox(height: 8),
            ],
            if (ocupadas.isNotEmpty) ...[
              const Text('Mesas ocupadas:',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.orange, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ...ocupadas.map((m) => ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text('${m.numero}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.orange, fontSize: 14)),
                      ),
                    ),
                    title: Text('Mesa ${m.numero}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.textPrimary)),
                    subtitle: Text('${m.orden.length} items · ${m.salon}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Ocupada',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.orange,
                              fontWeight: FontWeight.w600)),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showOrdenScreen(m);
                    },
                  )),
            ],
            if (libres.isEmpty && ocupadas.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No hay mesas disponibles',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
          ],
        ),
      ),
    );
  }

  void _startOrden(MesaData mesa) async {
    if (mesa.status == MesaStatus.libre) {
      final oldStatus = mesa.status;
      final oldTotal = mesa.totalCobrar;
      final oldOcupada = mesa.ocupadaDesde;
      await FirebaseService.updateMesaStatus(
        mesa.docId,
        'ocupada',
        ocupadaDesde: Timestamp.now(),
        usuario: widget.meseroNombre,
        mesaNumero: mesa.numero,
        oldStatus: oldStatus.value,
        atendidoPor: widget.meseroNombre,
      );

      if (!mounted) return;
      setState(() {
        _ultimoCambio = _UltimoCambio(
          docId: mesa.docId,
          oldStatus: oldStatus,
          oldTotalCobrar: oldTotal,
          oldOcupadaDesde: oldOcupada,
          newStatus: MesaStatus.ocupada,
          mesaNumero: mesa.numero,
          descripcion:
              'Mesa ${mesa.numero}: ${_statusLabel(oldStatus)} → Ocupada',
        );
      });
    }

    if (!mounted) return;
    _showOrdenScreen(mesa);
  }

  void _showOrdenScreen(MesaData mesa) {
    List<Map<String, dynamic>> items = [];
    String? seccionSel;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Text('Mesa ${mesa.numero}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: ctx,
                        builder: (d) => AlertDialog(
                          backgroundColor: AppColors.bgCard,
                          title: const Text('Cancelar orden',
                              style: TextStyle(color: AppColors.textPrimary)),
                          content: const Text('¿Liberar la mesa?',
                              style: TextStyle(color: AppColors.textSecondary)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: const Text('No'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: const Text('Sí, cancelar',
                                  style: TextStyle(color: AppColors.red)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && ctx.mounted) {
                        await FirebaseService.updateMesaStatus(
                          mesa.docId, 'libre',
                          usuario: widget.meseroNombre,
                          mesaNumero: mesa.numero,
                          oldStatus: mesa.status.value,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    },
                    child: const Icon(Icons.close, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<List<Platillo>>(
                  stream: FirebaseService.getPlatillosStream(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final platillos = snap.data!;
                    if (seccionSel == null) {
                      // ─── SECTION LIST ────────────────────────────
                      final counts = <String, int>{};
                      for (final p in platillos) {
                        if (_menuSecciones.contains(p.seccion)) {
                          counts[p.seccion] =
                              (counts[p.seccion] ?? 0) + 1;
                        }
                      }
                      final secciones = _menuSecciones
                          .where((s) => (counts[s] ?? 0) > 0)
                          .toList();
                      return GridView.builder(
                        padding: const EdgeInsets.only(top: 4),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.1,
                        ),
                        itemCount: secciones.length,
                        itemBuilder: (_, i) {
                          final s = secciones[i];
                          return GestureDetector(
                            onTap: () =>
                                setLocalState(() => seccionSel = s),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.bgCard,
                                borderRadius:
                                    BorderRadius.circular(16),
                                border: Border.all(
                                    color:
                                        AppColors.borderPrimary),
                              ),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                      Icons.restaurant_menu_rounded,
                                      color: AppColors.primary,
                                      size: 36),
                                  const SizedBox(height: 8),
                                  Text(s,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color:
                                              AppColors.textPrimary)),
                                  const SizedBox(height: 4),
                                  Text('${counts[s]} platillos',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color:
                                              AppColors.textMuted)),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }
                    // ─── PLATILLO LIST FILTERED BY SECTION ─────────
                    final filtered = platillos
                        .where((p) => p.seccion == seccionSel)
                        .toList();
                    return Column(
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => setLocalState(
                                    () => seccionSel = null),
                                child: const Icon(Icons.arrow_back,
                                    color: AppColors.primary,
                                    size: 20),
                              ),
                              const SizedBox(width: 8),
                              const Text('Secciones',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted)),
                              const Spacer(),
                              Text(seccionSel!,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final p = filtered[i];
                              return Container(
                                margin: const EdgeInsets.only(
                                    bottom: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.bgCard,
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          AppColors.borderPrimary),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: p.foto != null &&
                                            p.foto!.isNotEmpty
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(
                                                    10),
                                            child: Image.memory(
                                              base64Decode(p.foto!),
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.restaurant,
                                            color:
                                                AppColors.textMuted,
                                            size: 22),
                                  ),
                                  title: Text(p.nombre,
                                      style: const TextStyle(
                                          fontWeight:
                                              FontWeight.w600,
                                          color:
                                              AppColors.textPrimary,
                                          fontSize: 14)),
                                  subtitle: Text(
                                      '\$${p.precio.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight:
                                              FontWeight.w700,
                                          fontSize: 13)),
                                  trailing: IconButton(
                                    icon: const Icon(
                                        Icons.add_circle_outline,
                                        color: AppColors.primary),
                                    onPressed: () =>
                                        _showAddItemDialog(
                                      ctx,
                                      setLocalState,
                                      p,
                                      items,
                                      mesa.docId,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (items.isNotEmpty) ...[
                const Divider(color: AppColors.borderPrimary),
                SizedBox(
                  height: items.length * 44.0 + 60,
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final item = items[i];
                      return ListTile(
                        dense: true,
                        leading: Container(
                          width: 28, height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${item['cantidad']}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary, fontSize: 13)),
                        ),
                        title: Text('${item['nombre']}',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textPrimary)),
                        subtitle: item['notas'] != null &&
                                (item['notas'] as String).isNotEmpty
                            ? Text(item['notas'],
                                style: const TextStyle(
                                    fontSize: 10, color: AppColors.textMuted))
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                '\$${((item['precio'] as num) * (item['cantidad'] as num)).toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                    fontSize: 13)),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                setLocalState(() => items.removeAt(i));
                              },
                              child: const Icon(Icons.remove_circle_outline,
                                  color: AppColors.red, size: 20),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Divider(color: AppColors.borderPrimary),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Text('Total:',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      const Spacer(),
                      Text(
                        '\$${items.fold(0.0, (double sum, it) => sum + ((it['precio'] as num) * (it['cantidad'] as num)).toDouble()).toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800,
                            color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      await FirebaseService.setOrden(mesa.docId, items);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        _showStatusNotification(MesaStatus.ocupada, mesa.numero);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Confirmar Orden',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddItemDialog(
    BuildContext ctx,
    void Function(void Function()) setLocalState,
    Platillo platillo,
    List<Map<String, dynamic>> items,
    String mesaDocId,
  ) {
    int cantidad = 1;
    final notasCtrl = TextEditingController();

    showDialog(
      context: ctx,
      builder: (d) => StatefulBuilder(
        builder: (d, setDState) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.borderPrimary),
          ),
          title: Text(platillo.nombre,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: AppColors.primary),
                    onPressed: cantidad > 1
                        ? () => setDState(() => cantidad--)
                        : null,
                  ),
                  Container(
                    width: 44, height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$cantidad',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: AppColors.primary),
                    onPressed: () => setDState(() => cantidad++),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notasCtrl,
                maxLines: 2,
                decoration: _inputDecoration(
                    'Notas (ej: sin cebolla, extra queso)', Icons.edit_note_outlined),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                setLocalState(() {
                  items.add({
                    'platilloId': platillo.docId,
                    'nombre': platillo.nombre,
                    'precio': platillo.precio,
                    'cantidad': cantidad,
                    'notas': notasCtrl.text.trim(),
                  });
                });
                Navigator.pop(d);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Agregar',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBar() {
    final items = [
      (Icons.grid_view_rounded, Icons.grid_view_outlined, 'Mesas'),
      (Icons.menu_book_rounded, Icons.menu_book_outlined, 'Menú'),
      (Icons.notifications_rounded, Icons.notifications_outlined,
          'Alertas'),
      (Icons.bar_chart_rounded, Icons.bar_chart_outlined, 'Reportes'),
      (Icons.person_rounded, Icons.person_outlined, 'Perfil'),
    ];
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.asMap().entries.map((e) {
          final selected = e.key == _navIndex;
          return GestureDetector(
            onTap: () => setState(() => _navIndex = e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        selected ? e.value.$1 : e.value.$2,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textMuted,
                        size: 22,
                      ),
                      if (e.key == 2)
                        Positioned(
                          right: -6,
                          top: -4,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              color: AppColors.red,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Text('3',
                                style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.value.$3,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── MESA CARD ────────────────────────────────────────────────────────────────
class _MesaCard extends StatefulWidget {
  final MesaData mesa;
  final Color statusColor;
  final String statusLabel;
  final IconData statusIcon;
  final VoidCallback onTap;

  const _MesaCard({
    required this.mesa,
    required this.statusColor,
    required this.statusLabel,
    required this.statusIcon,
    required this.onTap,
  });

  @override
  State<_MesaCard> createState() => _MesaCardState();
}

class _MesaCardState extends State<_MesaCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulse = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    if (widget.mesa.status != MesaStatus.libre) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_MesaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mesa.status != MesaStatus.libre) {
      _pulseCtrl.repeat(reverse: true);
    } else {
      _pulseCtrl.stop();
      _pulseCtrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.statusColor;
    final m = widget.mesa;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: c.withOpacity(0.15),
              blurRadius: 12,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    c.withOpacity(0.2),
                    c.withOpacity(0.05),
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.numero.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: c,
                      letterSpacing: -1.5,
                      height: 1.1,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, __) => Icon(
                            widget.statusIcon,
                            size: 12,
                            color: c.withOpacity(
                              m.status == MesaStatus.libre
                                  ? 1.0
                                  : _pulse.value,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.statusLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: c,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (m.status == MesaStatus.ocupada) ...[
                    _infoRow(Icons.timer_outlined, m.tiempoStr),
                  ] else if (m.status == MesaStatus.pago) ...[
                    Text(
                      '\$${(m.totalCobrar ?? 0).toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.red,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _infoRow(Icons.timer_outlined, m.tiempoStr),
                  ] else if (m.status == MesaStatus.libre) ...[
                    const Text(
                      'Disponible',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Reservada',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chair_outlined,
                            size: 11, color: AppColors.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          '${m.capacidad} pax',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 12, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─── MODAL DETALLE MESA ───────────────────────────────────────────────────────
class _MesaDetailSheet extends StatelessWidget {
  final MesaData mesa;
  final Color statusColor;
  final String statusLabel;
  final ValueChanged<MesaStatus> onStatusChange;

  const _MesaDetailSheet({
    required this.mesa,
    required this.statusColor,
    required this.statusLabel,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  statusColor.withOpacity(0.2),
                  statusColor.withOpacity(0.05),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MESA',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          mesa.numero.toString().padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: statusColor,
                            letterSpacing: -2,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: statusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _infoChip(
                      Icons.chair_outlined,
                      '${mesa.capacidad} personas',
                    ),
                    if (mesa.status == MesaStatus.ocupada ||
                        mesa.status == MesaStatus.pago) ...[
                      const SizedBox(width: 12),
                      _infoChip(
                        Icons.timer_outlined,
                        mesa.tiempoStr,
                      ),
                    ],
                  ],
                ),
                if (mesa.orden.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('ORDEN',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  ...mesa.orden.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 24, height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text('${item['cantidad']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary, fontSize: 11)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('${item['nombre']}',
                                  style: const TextStyle(
                                      fontSize: 13, color: AppColors.textPrimary)),
                            ),
                            Text(
                                '\$${((item['precio'] as num) * (item['cantidad'] as num)).toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13, color: AppColors.textPrimary)),
                          ],
                        ),
                      )),
                  if (mesa.orden.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Spacer(),
                          Text('Total: \$${mesa.totalOrden.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15, color: AppColors.primary)),
                        ],
                      ),
                    ),
                ],
                if (mesa.totalCobrar != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.red.withOpacity(0.15)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.receipt_outlined,
                            color: AppColors.red, size: 20),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total a cobrar',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '\$${(mesa.totalCobrar!).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.red,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Divider(
                  color: AppColors.borderPrimary,
                  height: 1,
                ),
                const SizedBox(height: 16),
                const Text(
                  'CAMBIAR ESTADO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: MesaStatus.values.map((s) {
                    final colors = {
                      MesaStatus.libre: AppColors.green,
                      MesaStatus.ocupada: AppColors.orange,
                      MesaStatus.pago: AppColors.red,
                      MesaStatus.reservada: AppColors.blue,
                    };
                    final labels = {
                      MesaStatus.libre: 'Libre',
                      MesaStatus.ocupada: 'Ocupada',
                      MesaStatus.pago: 'Pago',
                      MesaStatus.reservada: 'Reservada',
                    };
                    final icons = {
                      MesaStatus.libre: Icons.check_circle_outline,
                      MesaStatus.ocupada: Icons.people_alt_outlined,
                      MesaStatus.pago: Icons.payments_outlined,
                      MesaStatus.reservada:
                          Icons.event_available_outlined,
                    };
                    final c = colors[s]!;
                    final active = s == mesa.status;
                    return Expanded(
                      child: GestureDetector(
                        onTap: active
                            ? null
                            : () => onStatusChange(s),
                        child: Container(
                          margin:
                              const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              vertical: 10),
                          decoration: BoxDecoration(
                            color: active
                                ? c.withOpacity(0.15)
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(12),
                            border: Border.all(
                              color: active
                                  ? c.withOpacity(0.4)
                                  : AppColors.borderPrimary,
                              width: active ? 1.2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                icons[s]!,
                                size: 18,
                                color: active
                                    ? c
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                labels[s]!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: active
                                      ? c
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                    ),
                    icon: const Icon(Icons.receipt_long_rounded,
                        size: 18),
                    label: const Text('Ver Orden Completa',
                        style: TextStyle(
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── NOTIFICACIÓN OVERLAY ─────────────────────────────────────────────────────
class _StatusNotification extends StatefulWidget {
  final MesaStatus status;
  final int numero;
  final Color statusColor;
  final String statusLabel;
  final IconData statusIcon;
  final VoidCallback onDismiss;
  final VoidCallback? onUndo;

  const _StatusNotification({
    required this.status,
    required this.numero,
    required this.statusColor,
    required this.statusLabel,
    required this.statusIcon,
    required this.onDismiss,
    this.onUndo,
  });

  @override
  State<_StatusNotification> createState() => _StatusNotificationState();
}

class _StatusNotificationState extends State<_StatusNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;
  bool _dismissed = false;

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _ctrl.dispose();
    widget.onDismiss();
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    );

    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.12, curve: Curves.easeOut),
        reverseCurve: const Interval(0.82, 1.0, curve: Curves.easeIn),
      ),
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.12, curve: Curves.easeOut),
        reverseCurve: const Interval(0.82, 1.0, curve: Curves.easeIn),
      ),
    );

    _ctrl.forward();
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _dismiss();
    });
  }

  @override
  void dispose() {
    if (!_dismissed) {
      _ctrl.dispose();
      _dismissed = true;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final offset = _slide.value * 120;
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Opacity(
            opacity: _opacity.value,
            child: Transform.translate(
              offset: Offset(offset.dx, offset.dy),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.statusColor.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: widget.statusColor.withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ListTile(
                        leading: Icon(
                          widget.statusIcon,
                          color: Colors.white,
                          size: 28,
                        ),
                        title: Text(
                          'Mesa ${widget.numero.toString().padLeft(2, '0')}: ${widget.statusLabel}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.onUndo != null)
                              GestureDetector(
                                onTap: () {
                                  widget.onUndo!();
                                  _dismiss();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.undo_rounded,
                                          color: Colors.white, size: 16),
                                      SizedBox(width: 4),
                                      Text('Deshacer',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                                size: 20,
                              ),
                              onPressed: _dismiss,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        contentPadding:
                            const EdgeInsets.only(left: 16, right: 4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── WIDGETS AUXILIARES ───────────────────────────────────────────────────────
class _OnlineDot extends StatefulWidget {
  const _OnlineDot();

  @override
  State<_OnlineDot> createState() => _OnlineDotState();
}

class _OnlineDotState extends State<_OnlineDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(_anim.value),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color:
                  AppColors.primary.withOpacity(0.5 * _anim.value),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderPrimary),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 18),
      ),
    );
  }
}
