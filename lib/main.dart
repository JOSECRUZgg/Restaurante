import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  static const bg = Color(0xFF0A0E14);
  static const bgCard = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const surfaceLight = Color(0xFF1E2530);
  static const mint = Color(0xFF2ECC71);
  static const mintLight = Color(0xFF34D399);
  static const mintDim = Color(0xFF1A7A43);
  static const textPrimary = Color(0xFFF0F6FC);
  static const textSecondary = Color(0xFF8B949E);
  static const textMuted = Color(0xFF484F58);
  static const orange = Color(0xFFFF8C00);
  static const red = Color(0xFFFF4757);
  static const blue = Color(0xFF4C9BE8);
  static const borderMint = Color(0x262ECC71);
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
        primaryColor: AppColors.mint,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.mint,
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
      // Seed de datos iniciales si Firestore está vacío
      await FirebaseService.seedDataIfEmpty();

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) =>
              MesasScreen(meseroNombre: mesero['nombre'] ?? 'Mesero'),
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
                      color: AppColors.mint
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
            color: AppColors.mint.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.mint.withOpacity(0.3), width: 1.5),
          ),
          child:
              const Icon(Icons.sync_rounded, color: AppColors.mint, size: 38),
        ),
        const SizedBox(height: 16),
        const Text(
          'ServeSync',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w900,
            color: AppColors.mint,
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
          border: Border.all(color: AppColors.borderMint, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.mint.withOpacity(0.07),
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
              ? AppColors.mint.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? AppColors.mint.withOpacity(0.5)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? AppColors.mint : AppColors.textSecondary,
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
                  color: AppColors.mint, width: 1.5),
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
            activeColor: AppColors.mint,
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
              color: filled ? AppColors.mint : AppColors.surfaceLight,
              border: Border.all(
                color: filled
                    ? AppColors.mint
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
                  : Border.all(color: AppColors.borderMint),
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
          backgroundColor: AppColors.mint,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.mintDim,
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
              color: AppColors.mint.withOpacity(0.7),
              decoration: TextDecoration.underline,
              decorationColor: AppColors.mint.withOpacity(0.4),
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
  const MesasScreen({super.key, required this.meseroNombre});

  @override
  State<MesasScreen> createState() => _MesasScreenState();
}

class _MesasScreenState extends State<MesasScreen> {
  int _selectedTab = 0;
  int _navIndex = 0;
  final List<String> _salones = ['Salón Principal', 'Terraza', 'Barra'];

  Color _statusColor(MesaStatus s) {
    switch (s) {
      case MesaStatus.libre: return AppColors.mint;
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
          Navigator.pop(context);
          // Actualizar en Firestore
          await FirebaseService.updateMesaStatus(
            mesa.docId,
            newStatus.value,
            comensales: newStatus == MesaStatus.ocupada ? 2 : null,
            ocupadaDesde: newStatus == MesaStatus.ocupada
                ? Timestamp.now()
                : null,
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
        child: Column(
          children: [
            _buildHeader(),
            _buildSalonTabs(),
            _buildLegend(),
            Expanded(child: _buildMesaGrid()),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
      bottomNavigationBar: _buildNavBar(),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.mint.withOpacity(0.15),
              border: Border.all(
                  color: AppColors.mint.withOpacity(0.4)),
            ),
            child: const Icon(Icons.person_outline,
                color: AppColors.mint, size: 22),
          ),
          Expanded(
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sync_rounded,
                        color: AppColors.mint, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'ServeSync',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.mint,
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
          Row(
            children: [
              _IconBtn(icon: Icons.search_rounded, onTap: () {}),
              const SizedBox(width: 8),
              _IconBtn(
                  icon: Icons.settings_outlined, onTap: () {}),
            ],
          ),
        ],
      ),
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
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _salones.asMap().entries.map((e) {
                final selected = e.key == _selectedTab;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _selectedTab = e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.mint
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? AppColors.mint
                            : AppColors.borderMint,
                      ),
                    ),
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.black
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final items = [
      (AppColors.mint, 'Libre'),
      (AppColors.orange, 'Ocupada'),
      (AppColors.red, 'Pago'),
      (AppColors.blue, 'Reservada'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: items
            .map((e) => Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: e.$1,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: e.$1.withOpacity(0.5),
                                blurRadius: 4)
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(e.$2,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildMesaGrid() {
    return StreamBuilder<List<MesaData>>(
      stream: FirebaseService.getMesasStream(),
      builder: (context, snapshot) {
        // Estado de carga
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppColors.mint),
                SizedBox(height: 16),
                Text('Sincronizando mesas...',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14)),
              ],
            ),
          );
        }

        // Error de conexión
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

        final mesas = snapshot.data ?? [];

        if (mesas.isEmpty) {
          return const Center(
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
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: GridView.builder(
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.88,
            ),
            itemCount: mesas.length,
            itemBuilder: (_, i) => _MesaCard(
              mesa: mesas[i],
              statusColor: _statusColor(mesas[i].status),
              statusLabel: _statusLabel(mesas[i].status),
              statusIcon: _statusIcon(mesas[i].status),
              onTap: () => _showMesaDetail(mesas[i]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.mint.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () {},
        backgroundColor: AppColors.mint,
        foregroundColor: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'Nueva Orden',
          style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14),
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
                    ? AppColors.mint.withOpacity(0.15)
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
                            ? AppColors.mint
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
                          ? AppColors.mint
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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withOpacity(0.25), width: 1),
          boxShadow: [
            BoxShadow(
              color: c.withOpacity(0.12),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 5,
              decoration: BoxDecoration(
                color: c,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                      color: c.withOpacity(0.6), blurRadius: 8),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        m.numero.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: -1,
                          height: 1,
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) => Opacity(
                          opacity: m.status == MesaStatus.libre
                              ? 1.0
                              : _pulse.value,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: c.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(widget.statusIcon,
                                color: c, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: c.withOpacity(0.3), width: 0.8),
                    ),
                    child: Text(
                      widget.statusLabel,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (m.status == MesaStatus.ocupada) ...[
                    Row(children: [
                      const Icon(Icons.timer_outlined,
                          size: 12,
                          color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(m.tiempoStr,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.people_outline,
                          size: 12,
                          color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text('${m.comensales ?? 0} personas',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ]),
                  ] else if (m.status == MesaStatus.pago) ...[
                    Text(
                      '\$${(m.totalCobrar ?? 0).toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.red,
                      ),
                    ),
                    Row(children: [
                      const Icon(Icons.timer_outlined,
                          size: 12,
                          color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(m.tiempoStr,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ]),
                  ] else if (m.status == MesaStatus.libre) ...[
                    const Text('Disponible',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                  ] else ...[
                    const Text('Reservada',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.blue)),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chair_outlined,
                            size: 10, color: AppColors.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          '${m.capacidad} pax',
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600),
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
        border: Border.all(color: AppColors.borderMint),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Mesa ${mesa.numero.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: statusColor.withOpacity(0.4)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Capacidad: ${mesa.capacidad} personas',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          if (mesa.status == MesaStatus.ocupada ||
              mesa.status == MesaStatus.pago) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.timer_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('Tiempo en mesa: ${mesa.tiempoStr}',
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary)),
            ]),
          ],
          if (mesa.totalCobrar != null) ...[
            const SizedBox(height: 8),
            Text(
              'Total a cobrar: \$${mesa.totalCobrar!.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.red),
            ),
          ],
          const SizedBox(height: 24),
          const Text('Cambiar estado:',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: MesaStatus.values.map((s) {
              final colors = {
                MesaStatus.libre: AppColors.mint,
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
              final c = colors[s]!;
              return GestureDetector(
                onTap: () => onStatusChange(s),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.withOpacity(0.4)),
                  ),
                  child: Text(
                    labels[s]!,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c),
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
                backgroundColor: AppColors.mint,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.receipt_long_rounded,
                  size: 18),
              label: const Text('Ver Orden Completa',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
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
          color: AppColors.mint.withOpacity(_anim.value),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color:
                  AppColors.mint.withOpacity(0.5 * _anim.value),
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
          border: Border.all(color: AppColors.borderMint),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 18),
      ),
    );
  }
}
