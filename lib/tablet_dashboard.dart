import 'dart:async';
import 'package:flutter/material.dart';
import 'services/firebase_service.dart';
import 'main.dart'; // To reuse AppColors and other styles if needed

class TabletDashboard extends StatefulWidget {
  final String meseroNombre;
  final String meseroDocId;
  final bool esAdmin;

  const TabletDashboard({
    super.key,
    required this.meseroNombre,
    required this.meseroDocId,
    this.esAdmin = false,
  });

  @override
  State<TabletDashboard> createState() => _TabletDashboardState();
}

class _TabletDashboardState extends State<TabletDashboard> with SingleTickerProviderStateMixin {
  MesaData? _selectedMesa;
  String _filter = 'pendientes'; // 'todas', 'pendientes', 'ocupadas', 'libres'
  double _tipPercentage = 0.10; // Default 10% tip
  double _customTipAmount = 0.0;
  bool _isCustomTip = false;
  String _paymentMethod = 'tarjeta'; // 'efectivo', 'tarjeta', 'transferencia'
  
  // Stats
  double _totalCajaHoy = 0.0;
  int _cuentasCobradasHoy = 0;
  int _alertasPendientes = 0;
  StreamSubscription? _mesasSubscription;
  StreamSubscription? _historialSubscription;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    // Listen to statistics for cashier today
    _subscribeToStats();
  }

  void _subscribeToStats() {
    _mesasSubscription = FirebaseService.getMesasStream().listen((mesas) {
      if (!mounted) return;
      int alerts = 0;
      for (final m in mesas) {
        if (m.solicitudPago != null) {
          alerts++;
        }
        // Update selected mesa with fresh data in real-time
        if (_selectedMesa != null && m.docId == _selectedMesa!.docId) {
          setState(() {
            _selectedMesa = m;
          });
        }
      }
      setState(() {
        _alertasPendientes = alerts;
      });
    });

    _historialSubscription = FirebaseService.getHistorialHoyStream().listen((eventos) {
      if (!mounted) return;
      double total = 0;
      int cobradas = 0;
      for (final e in eventos) {
        if (e.tipo == 'pago_confirmado') {
          cobradas++;
          final t = e.datos['total'];
          if (t is num) total += t.toDouble();
        }
      }
      setState(() {
        _totalCajaHoy = total;
        _cuentasCobradasHoy = cobradas;
      });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mesasSubscription?.cancel();
    _historialSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Pane (Tables List)
                  Expanded(
                    flex: 4,
                    child: _buildLeftPane(),
                  ),
                  // Vertical Divider
                  Container(
                    width: 1,
                    color: AppColors.borderPrimary,
                  ),
                  // Right Pane (Checkout details)
                  Expanded(
                    flex: 6,
                    child: _buildRightPane(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TOP BAR ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: const Border(bottom: BorderSide(color: AppColors.borderPrimary, width: 1)),
      ),
      child: Row(
        children: [
          // Branding
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: const Icon(Icons.sync_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SERVESYNC CAJA',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                'Terminal de Cobro Principal',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const Spacer(),
          // Stats Counters
          _buildStatCard('CAJA HOY', '\$${_totalCajaHoy.toStringAsFixed(2)}', Icons.payments_outlined, AppColors.green),
          const SizedBox(width: 16),
          _buildStatCard('COBROS', '$_cuentasCobradasHoy', Icons.check_circle_outline, AppColors.blue),
          const SizedBox(width: 16),
          _buildStatCard(
            'ALERTAS', 
            '$_alertasPendientes', 
            Icons.notifications_active_outlined, 
            _alertasPendientes > 0 ? AppColors.red : AppColors.textMuted,
            pulse: _alertasPendientes > 0,
          ),
          const SizedBox(width: 16),
          _buildCerrarCajaBtn(),
          const SizedBox(width: 24),
          // User profile / exit
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    widget.meseroNombre,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                  ),
                  const Text(
                    'Cajero Principal',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: AppColors.red),
                onPressed: () => _showLogoutDialog(),
                tooltip: 'Cerrar Sesión',
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, {bool pulse = false}) {
    Widget card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pulse ? color.withOpacity(0.5) : AppColors.borderPrimary,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
              ),
              Text(
                value,
                style: TextStyle(fontSize: 15, color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );

    if (pulse) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + (_pulseController.value * 0.04),
            child: card,
          );
        },
      );
    }
    return card;
  }

  // ─── CIERRE DE CAJA ──────────────────────────────────────────────────────────
  Widget _buildCerrarCajaBtn() {
    return GestureDetector(
      onTap: _showCierreCajaDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 16),
            const SizedBox(width: 6),
            Text(
              'Cerrar Caja',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCierreCajaDialog() {
    final ticketPromedio = _cuentasCobradasHoy > 0
        ? _totalCajaHoy / _cuentasCobradasHoy
        : 0.0;
    final now = DateTime.now();
    final fechaStr = "${now.day}/${now.month}/${now.year}";
    final horaStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderPrimary),
        ),
        title: Row(
          children: [
            Icon(Icons.lock_rounded, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            const Text('Cierre de Caja', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Container(
          width: 420,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderPrimary),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cierreRow('Cajero:', widget.meseroNombre),
              const SizedBox(height: 6),
              _cierreRow('Fecha:', fechaStr),
              const SizedBox(height: 6),
              _cierreRow('Hora:', horaStr),
              const Divider(color: AppColors.borderPrimary, height: 24),
              _cierreRow('Total en Caja:', '\$${_totalCajaHoy.toStringAsFixed(2)}', isTotal: true),
              const SizedBox(height: 6),
              _cierreRow('Cuentas Cobradas:', '$_cuentasCobradasHoy'),
              const SizedBox(height: 6),
              _cierreRow('Ticket Promedio:', '\$${ticketPromedio.toStringAsFixed(2)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseService.cerrarCaja(
                widget.meseroNombre,
                totalGeneral: _totalCajaHoy,
                numTransacciones: _cuentasCobradasHoy,
              );
              setState(() {
                _totalCajaHoy = 0;
                _cuentasCobradasHoy = 0;
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Cierre de caja realizado — Total: \$${_totalCajaHoy.toStringAsFixed(2)}, Cuentas: $_cuentasCobradasHoy'),
                    backgroundColor: AppColors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text('Cerrar Caja', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cierreRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
          fontSize: isTotal ? 14 : 13,
          color: AppColors.textSecondary,
          fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
        )),
        Text(value, style: TextStyle(
          fontSize: isTotal ? 16 : 13,
          color: isTotal ? AppColors.green : AppColors.textPrimary,
          fontWeight: FontWeight.bold,
        )),
      ],
    );
  }

  // ─── LEFT PANE (TABLES GRID) ────────────────────────────────────────────────
  Widget _buildLeftPane() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Tabs
          Row(
            children: [
              _buildFilterBtn('Pendientes', 'pendientes', Icons.priority_high_rounded),
              const SizedBox(width: 8),
              _buildFilterBtn('Todas', 'todas', Icons.grid_view_rounded),
              const SizedBox(width: 8),
              _buildFilterBtn('Ocupadas', 'ocupadas', Icons.restaurant_rounded),
            ],
          ),
          const SizedBox(height: 16),
          // Tables Grid
          Expanded(
            child: StreamBuilder<List<MesaData>>(
              stream: FirebaseService.getMesasStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No hay mesas configuradas', style: TextStyle(color: AppColors.textMuted)));
                }

                var mesas = snapshot.data!;
                // Filter logic
                if (_filter == 'pendientes') {
                  mesas = mesas.where((m) => m.solicitudPago != null || m.status == MesaStatus.pago).toList();
                } else if (_filter == 'ocupadas') {
                  mesas = mesas.where((m) => m.status == MesaStatus.ocupada || m.status == MesaStatus.pago).toList();
                }

                if (mesas.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _filter == 'pendientes' ? Icons.check_circle_outline_rounded : Icons.table_restaurant_outlined, 
                          size: 48, 
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _filter == 'pendientes' ? '¡Excelente! Sin cuentas pendientes' : 'No hay mesas en este estado',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.25,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: mesas.length,
                  itemBuilder: (context, index) {
                    final mesa = mesas[index];
                    final isSelected = _selectedMesa?.docId == mesa.docId;
                    final hasPendingPayment = mesa.solicitudPago != null;

                    return _buildMesaCard(mesa, isSelected, hasPendingPayment);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBtn(String label, String code, IconData icon) {
    final active = _filter == code;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _filter = code;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withOpacity(0.15) : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.borderPrimary,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: active ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMesaCard(MesaData mesa, bool isSelected, bool hasPendingPayment) {
    Color statusColor = AppColors.green;
    if (hasPendingPayment) {
      statusColor = AppColors.red;
    } else if (mesa.status == MesaStatus.ocupada) {
      statusColor = AppColors.orange;
    } else if (mesa.status == MesaStatus.reservada) {
      statusColor = AppColors.blue;
    }

    Widget card = Container(
      decoration: BoxDecoration(
        color: isSelected ? AppColors.surfaceLight : AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasPendingPayment 
              ? AppColors.red.withOpacity(_pulseController.value) 
              : (isSelected ? AppColors.primary : AppColors.borderPrimary),
          width: isSelected || hasPendingPayment ? 2 : 1,
        ),
        boxShadow: hasPendingPayment ? [
          BoxShadow(
            color: AppColors.red.withOpacity(0.15 * _pulseController.value),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ] : null,
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedMesa = mesa;
            _isCustomTip = false;
            _tipPercentage = 0.10;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      'MESA ${mesa.numero}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: statusColor,
                      ),
                    ),
                  ),
                  if (hasPendingPayment)
                    const Icon(Icons.receipt_long_rounded, color: AppColors.red, size: 20)
                  else
                    Icon(
                      mesa.status == MesaStatus.libre ? Icons.check_circle_outline : Icons.restaurant, 
                      color: statusColor.withOpacity(0.6), 
                      size: 16
                    ),
                ],
              ),
              const Spacer(),
              Text(
                mesa.salon,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    mesa.status == MesaStatus.libre 
                        ? 'Libre' 
                        : (hasPendingPayment ? 'Cobro Solicitado' : 'Consumiendo'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hasPendingPayment ? AppColors.red : AppColors.textSecondary,
                    ),
                  ),
                  if (mesa.status != MesaStatus.libre)
                    Text(
                      '\$${mesa.totalOrden.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (hasPendingPayment) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) => card,
      );
    }
    return card;
  }

  // ─── RIGHT PANE (CHECKOUT / BILLING) ───────────────────────────────────────
  Widget _buildRightPane() {
    if (_selectedMesa == null) {
      return Container(
        color: AppColors.bgCard,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.payments_rounded, size: 80, color: AppColors.primary.withOpacity(0.15)),
              const SizedBox(height: 16),
              const Text(
                'Selecciona una Mesa para Cobrar',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Las mesas en rojo tienen una solicitud de cuenta activa',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final mesa = _selectedMesa!;
    final subtotal = mesa.totalOrden;
    final propina = _isCustomTip ? _customTipAmount : (subtotal * _tipPercentage);
    final total = subtotal + propina;

    return Container(
      color: AppColors.bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Selected Table Header (siempre visible)
          _buildCheckoutHeader(mesa),
          // Scrollable content (items + billing, todo junto)
          Expanded(
            child: mesa.orden.isEmpty
                ? _buildEmptyOrderState()
                : SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      children: [
                        _buildOrderItemsList(mesa),
                        _buildBillingControls(subtotal, propina, total),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutHeader(MesaData mesa) {
    final mesero = mesa.solicitudPago != null 
        ? (mesa.solicitudPago!['solicitadoPor'] ?? mesa.atendidoPor ?? 'Mesero')
        : (mesa.atendidoPor ?? 'Sin asignar');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderPrimary)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'MESA ${mesa.numero}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      mesa.salon,
                      style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Atendido por: $mesero',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
          const Spacer(),
          if (mesa.solicitudPago != null) ...[
            OutlinedButton.icon(
              onPressed: () => _rejectPaymentRequest(mesa),
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('Rechazar Cuenta', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: const BorderSide(color: AppColors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildEmptyOrderState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_basket_outlined, size: 48, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text(
            'Esta mesa no tiene platillos cargados',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItemsList(MesaData mesa) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      itemCount: mesa.orden.length,
      itemBuilder: (context, i) {
        final item = mesa.orden[i];
        final cant = item['cantidad'] ?? 1;
        final precio = (item['precio'] as num?)?.toDouble() ?? 0.0;
        final itemTotal = precio * cant;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderPrimary),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${cant}x',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['nombre'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                    ),
                    Text(
                      '\$${precio.toStringAsFixed(2)} c/u',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(
                '\$${itemTotal.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBillingControls(double subtotal, double propina, double total) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderPrimary)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Propina Selector
          const Text(
            'AÑADIR PROPINA',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.0),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildTipBtn('0%', 0.0),
              const SizedBox(width: 8),
              _buildTipBtn('10%', 0.10),
              const SizedBox(width: 8),
              _buildTipBtn('15%', 0.15),
              const SizedBox(width: 8),
              _buildTipBtn('20%', 0.20),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _showCustomTipDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _isCustomTip ? AppColors.primary.withOpacity(0.15) : AppColors.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _isCustomTip ? AppColors.primary : AppColors.borderPrimary),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _isCustomTip ? '\$${_customTipAmount.toStringAsFixed(0)}' : 'Otro',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _isCustomTip ? AppColors.primary : AppColors.textPrimary
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Payment Method Selector
          const Text(
            'MÉTODO DE PAGO',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1.0),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildPaymentMethodBtn('Efectivo', 'efectivo', Icons.money_rounded),
              const SizedBox(width: 10),
              _buildPaymentMethodBtn('Tarjeta', 'tarjeta', Icons.credit_card_rounded),
              const SizedBox(width: 10),
              _buildPaymentMethodBtn('Transferencia', 'transferencia', Icons.account_balance_rounded),
            ],
          ),
          const SizedBox(height: 20),

          // Total Calculation Area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderPrimary),
            ),
            child: Column(
              children: [
                _buildTotalRow('Subtotal', '\$${subtotal.toStringAsFixed(2)}'),
                const SizedBox(height: 6),
                _buildTotalRow('Propina', '\$${propina.toStringAsFixed(2)}'),
                const Divider(color: AppColors.borderPrimary, height: 20),
                _buildTotalRow(
                  'TOTAL A COBRAR', 
                  '\$${total.toStringAsFixed(2)}', 
                  isHighlighted: true
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: () => _simulatePrint(false),
                    icon: const Icon(Icons.print_rounded, size: 20),
                    label: const Text(
                      'Pre-Ticket',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: () => _showSplitBillDialog(),
                    icon: const Icon(Icons.call_split_rounded, size: 20),
                    label: const Text(
                      'Dividir',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.blue,
                      side: const BorderSide(color: AppColors.blue, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () => _processPayment(total),
                    icon: const Icon(Icons.check_circle_rounded, size: 20),
                    label: const Text(
                      'Cobrar & Cerrar',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTipBtn(String label, double percentage) {
    final active = !_isCustomTip && _tipPercentage == percentage;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isCustomTip = false;
            _tipPercentage = percentage;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withOpacity(0.15) : AppColors.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? AppColors.primary : AppColors.borderPrimary),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: active ? AppColors.primary : AppColors.textPrimary
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodBtn(String label, String code, IconData icon) {
    final active = _paymentMethod == code;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _paymentMethod = code;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withOpacity(0.12) : AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.borderPrimary,
              width: active ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: active ? AppColors.primary : AppColors.textSecondary, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: active ? AppColors.primary : AppColors.textPrimary
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, {bool isHighlighted = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isHighlighted ? 15 : 13,
            fontWeight: isHighlighted ? FontWeight.w900 : FontWeight.normal,
            color: isHighlighted ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isHighlighted ? 20 : 14,
            fontWeight: FontWeight.w900,
            color: isHighlighted ? AppColors.green : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // ─── ACTIONS & LOGIC ───────────────────────────────────────────────────────
  void _showCustomTipDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderPrimary),
        ),
        title: const Text('Propina Personalizada', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Monto en pesos',
            prefixText: '\$ ',
            hintStyle: TextStyle(color: AppColors.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(ctrl.text);
              if (amount != null && amount >= 0) {
                setState(() {
                  _isCustomTip = true;
                  _customTipAmount = amount;
                });
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
            ),
            child: const Text('Aplicar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _rejectPaymentRequest(MesaData mesa) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Rechazar Cobro', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('¿Rechazar solicitud de cobro para la Mesa ${mesa.numero}?\nEsto le permitirá al mesero seguir editando la orden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Rechazar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseService.rechazarSolicitudPago(mesa.docId);
      setState(() {
        _selectedMesa = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud de cobro rechazada correctamente'),
            backgroundColor: AppColors.orange,
          ),
        );
      }
    }
  }

  Future<void> _processPayment(double total) async {
    final mesa = _selectedMesa!;
    
    // Simulate print first
    await _simulatePrint(true);
    
    // Confirm payment on Firebase and liberate table
    await FirebaseService.confirmarPago(
      mesa.docId,
      usuario: widget.meseroNombre,
      mesaNumero: mesa.numero,
      totalOrden: total,
      atendidoPor: mesa.solicitudPago?['solicitadoPor'] ?? mesa.atendidoPor,
    );

    // Save statistics locally if needed or let Firebase log handles it

    setState(() {
      _selectedMesa = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mesa ${mesa.numero} cobrada exitosamente (\$${total.toStringAsFixed(2)})'),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─── DIVIDIR CUENTA ─────────────────────────────────────────────────────────
  void _showSplitBillDialog() {
    final mesa = _selectedMesa!;
    if (mesa.orden.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La mesa no tiene platillos para dividir'), backgroundColor: AppColors.orange, behavior: SnackBarBehavior.floating),
      );
      return;
    }

    // Estado mutable del diálogo
    final personas = <_SplitPerson>[];
    personas.add(_SplitPerson('Persona 1'));
    // Bitmask de items asignados
    final asignados = List.filled(mesa.orden.length, -1);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Items disponibles (no asignados a nadie)
          final itemsDisponibles = <int>[];
          for (int i = 0; i < mesa.orden.length; i++) {
            if (asignados[i] == -1) itemsDisponibles.add(i);
          }
          final totalOrdenCheck = mesa.totalOrden;
          double totalAsignado = 0;
          for (final p in personas) {
            for (final idx in p.itemIndices) {
              final item = mesa.orden[idx];
              final cant = item['cantidad'] ?? 1;
              final precio = (item['precio'] as num?)?.toDouble() ?? 0;
              totalAsignado += precio * cant;
            }
          }
          final resto = totalOrdenCheck - totalAsignado;
          final puedeCobrar = itemsDisponibles.isEmpty && (resto).abs() < 0.01;

          return AlertDialog(
            backgroundColor: AppColors.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.borderPrimary),
            ),
            title: Row(
              children: [
                const Icon(Icons.call_split_rounded, color: AppColors.blue, size: 24),
                const SizedBox(width: 12),
                Text('Dividir Cuenta — Mesa ${mesa.numero}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Lista de personas
                    ...personas.asMap().entries.map((entry) {
                      final i = entry.key;
                      final p = entry.value;
                      double pTotal = 0;
                      for (final idx in p.itemIndices) {
                        final item = mesa.orden[idx];
                        final cant = item['cantidad'] ?? 1;
                        final precio = (item['precio'] as num?)?.toDouble() ?? 0;
                        pTotal += precio * cant;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderPrimary),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.person_outline, color: AppColors.blue, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: TextEditingController(text: p.nombre)..selection = TextSelection.collapsed(offset: p.nombre.length),
                                    onChanged: (v) => p.nombre = v,
                                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                if (personas.length > 1)
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: AppColors.red, size: 18),
                                    onPressed: () {
                                      for (final idx in p.itemIndices) {
                                        asignados[idx] = -1;
                                      }
                                      personas.removeAt(i);
                                      setDialogState(() {});
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (p.itemIndices.isEmpty)
                              const Text('Sin items asignados', style: TextStyle(color: AppColors.textMuted, fontSize: 12))
                            else
                              ...p.itemIndices.map((idx) {
                                final item = mesa.orden[idx];
                                return Text(
                                  ' • ${item['nombre']} x${item['cantidad'] ?? 1} — \$${((item['precio'] as num?)?.toDouble() ?? 0) * ((item['cantidad'] as num?)?.toInt() ?? 1)}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                );
                              }),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text('Subtotal: \$${pTotal.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => _showItemSelector(mesa, p, asignados, personas.indexOf(p), setDialogState),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.blue.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.blue.withOpacity(0.3)),
                                    ),
                                    child: const Text('Seleccionar items', style: TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    // Botón agregar persona
                    if (itemsDisponibles.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          personas.add(_SplitPerson('Persona ${personas.length + 1}'));
                          setDialogState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.blue.withOpacity(0.3), style: BorderStyle.solid),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle_outline, color: AppColors.blue, size: 18),
                              SizedBox(width: 8),
                              Text('Agregar Persona', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    const Divider(color: AppColors.borderPrimary, height: 24),
                    // Resumen
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total orden:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        Text('\$${totalOrdenCheck.toStringAsFixed(2)}', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Asignado:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        Text('\$${totalAsignado.toStringAsFixed(2)}', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    if (!puedeCobrar) ...[
                      const SizedBox(height: 8),
                      Text('Faltan \$${resto.toStringAsFixed(2)} por asignar', style: const TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton.icon(
                onPressed: puedeCobrar
                    ? () {
                        Navigator.pop(ctx);
                        _processSplitPayments(mesa, personas);
                      }
                    : null,
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text('Cobrar Todo', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: puedeCobrar ? AppColors.green : AppColors.textMuted,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.textMuted,
                  disabledForegroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showItemSelector(MesaData mesa, _SplitPerson person, List<int> asignados, int personIdx, void Function(void Function()) setDialogState) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) {
          return AlertDialog(
            backgroundColor: AppColors.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.borderPrimary),
            ),
            title: Text('Items para ${person.nombre}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: mesa.orden.asMap().entries.map((entry) {
                    final i = entry.key;
                    final item = entry.value;
                    final cant = item['cantidad'] ?? 1;
                    final precio = (item['precio'] as num?)?.toDouble() ?? 0;
                    final itemTotal = precio * cant;
                    final esDePersona = asignados[i] == personIdx;
                    final disponible = asignados[i] == -1;
                    final seleccionable = esDePersona || disponible;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: esDePersona ? AppColors.blue.withOpacity(0.08) : AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: esDePersona ? AppColors.blue.withOpacity(0.4) : AppColors.borderPrimary,
                        ),
                      ),
                      child: InkWell(
                        onTap: seleccionable
                            ? () {
                                if (esDePersona) {
                                  asignados[i] = -1;
                                  person.itemIndices.remove(i);
                                } else {
                                  asignados[i] = personIdx;
                                  person.itemIndices.add(i);
                                }
                                setLocalState(() {});
                                setDialogState(() {});
                              }
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          children: [
                            Icon(
                              esDePersona ? Icons.check_box_rounded : (disponible ? Icons.check_box_outline_blank_rounded : Icons.indeterminate_check_box_outlined),
                              color: esDePersona ? AppColors.blue : (disponible ? AppColors.textMuted : AppColors.red.withOpacity(0.4)),
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['nombre'] ?? '', style: TextStyle(
                                    color: seleccionable ? AppColors.textPrimary : AppColors.textMuted,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  )),
                                  Text('$cant x \$${precio.toStringAsFixed(0)}', style: TextStyle(
                                    color: seleccionable ? AppColors.textSecondary : AppColors.textMuted,
                                    fontSize: 11,
                                  )),
                                ],
                              ),
                            ),
                            Text('\$${itemTotal.toStringAsFixed(0)}', style: TextStyle(
                              color: esDePersona ? AppColors.blue : (disponible ? AppColors.textPrimary : AppColors.textMuted),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            )),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Listo', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processSplitPayments(MesaData mesa, List<_SplitPerson> personas) async {
    final splitGroupId = DateTime.now().millisecondsSinceEpoch.toString();
    double totalGeneral = 0;

    for (final p in personas) {
      double pTotal = 0;
      for (final idx in p.itemIndices) {
        final item = mesa.orden[idx];
        final cant = item['cantidad'] ?? 1;
        final precio = (item['precio'] as num?)?.toDouble() ?? 0;
        pTotal += precio * cant;
      }
      totalGeneral += pTotal;

      await FirebaseService.confirmarPago(
        mesa.docId,
        usuario: widget.meseroNombre,
        mesaNumero: mesa.numero,
        totalOrden: pTotal,
        atendidoPor: mesa.solicitudPago?['solicitadoPor'] ?? mesa.atendidoPor,
        splitGroupId: splitGroupId,
        subtotalSplit: pTotal,
      );
    }

    // Limpiar la mesa después de todos los splits
    await FirebaseService.clearMesa(mesa.docId);

    setState(() {
      _selectedMesa = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cuenta dividida en ${personas.length} pagos — Total \$${totalGeneral.toStringAsFixed(2)}'),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _simulatePrint(bool isFinalPayment) async {
    final mesa = _selectedMesa!;
    final subtotal = mesa.totalOrden;
    final propina = _isCustomTip ? _customTipAmount : (subtotal * _tipPercentage);
    final total = subtotal + propina;

    // Show a realistic print animation modal
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return _PrinterSimulatorDialog(
          mesa: mesa,
          subtotal: subtotal,
          propina: propina,
          total: total,
          paymentMethod: _paymentMethod,
          isFinalPayment: isFinalPayment,
        );
      },
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Cerrar Sesión', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('¿Desea salir de la terminal de cobro?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Salir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─── HIGH FIDELITY THERMAL TICKET PRINT SIMULATOR ────────────────────────────
class _PrinterSimulatorDialog extends StatefulWidget {
  final MesaData mesa;
  final double subtotal;
  final double propina;
  final double total;
  final String paymentMethod;
  final bool isFinalPayment;

  const _PrinterSimulatorDialog({
    required this.mesa,
    required this.subtotal,
    required this.propina,
    required this.total,
    required this.paymentMethod,
    required this.isFinalPayment,
  });

  @override
  State<_PrinterSimulatorDialog> createState() => _PrinterSimulatorDialogState();
}

class _PrinterSimulatorDialogState extends State<_PrinterSimulatorDialog> with SingleTickerProviderStateMixin {
  late AnimationController _printController;
  late Animation<double> _slideAnimation;
  bool _printingCompleted = false;

  @override
  void initState() {
    super.initState();
    _printController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // Printing duration
    );

    _slideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _printController, curve: Curves.easeOutQuad),
    );

    // Start printing automatically
    _printController.forward().then((_) {
      setState(() {
        _printingCompleted = true;
      });
    });
  }

  @override
  void dispose() {
    _printController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}";
    final paymentLabel = widget.paymentMethod == 'efectivo' 
        ? 'EFECTIVO' 
        : (widget.paymentMethod == 'tarjeta' ? 'TARJETA DE CRÉDITO/DÉBITO' : 'TRANSFERENCIA BANCARIA');

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // POS Printer top box mockup
              Container(
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2D35),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  boxShadow: [
                    BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _printingCompleted ? Colors.green : Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _printingCompleted ? 'IMPRESIÓN COMPLETA' : 'IMPRIMIENDO TICKET...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8
                      ),
                    ),
                  ],
                ),
              ),
              // Slot through which paper slides out
              Container(
                height: 6,
                color: Colors.black,
              ),
              // Receipt Paper wrapping container
              Expanded(
                child: AnimatedBuilder(
                animation: _slideAnimation,
                builder: (context, child) {
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: _slideAnimation.value,
                      child: child,
                    ),
                  );
                },
                child: SingleChildScrollView(
                  child: Container(
                    width: 380,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F9FB),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
                      ],
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      // Zigzag jagged header pattern
                      CustomPaint(
                        size: const Size(380, 10),
                        painter: _JaggedBorderPainter(),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                        child: Column(
                          children: [
                            // Restaurant Logo/Info
                            const Text(
                              'SERVESYNC RESTAURANT',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16, fontFamily: 'monospace'),
                              textAlign: TextAlign.center,
                            ),
                            const Text(
                              'SUCURSAL CENTRO',
                              style: TextStyle(color: Colors.black87, fontSize: 12, fontFamily: 'monospace'),
                              textAlign: TextAlign.center,
                            ),
                            const Text(
                              'AV. REFORMA #450, COL. CENTRO',
                              style: TextStyle(color: Colors.black87, fontSize: 11, fontFamily: 'monospace'),
                              textAlign: TextAlign.center,
                            ),
                            const Text(
                              'TEL: (555) 123-4567',
                              style: TextStyle(color: Colors.black87, fontSize: 11, fontFamily: 'monospace'),
                              textAlign: TextAlign.center,
                            ),
                            const Divider(color: Colors.black38, height: 20, thickness: 1),
                            
                            // Ticket info
                            _buildReceiptRow('TICKET:', widget.isFinalPayment ? '#PAG-0842' : '#PRE-0842'),
                            _buildReceiptRow('FECHA:', dateFormat),
                            _buildReceiptRow('MESA:', '${widget.mesa.numero} (${widget.mesa.salon})'),
                            _buildReceiptRow('MESERO:', widget.mesa.solicitudPago?['solicitadoPor'] ?? widget.mesa.atendidoPor ?? 'Mesero'),
                            const Divider(color: Colors.black38, height: 20, thickness: 1),
                            
                            // Order items list header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text('DESC (CANT)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace')),
                                Text('IMPORTE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace')),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Items list
                            ...widget.mesa.orden.map((item) {
                              final cant = item['cantidad'] ?? 1;
                              final precio = (item['precio'] as num?)?.toDouble() ?? 0.0;
                              final sub = precio * cant;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item['nombre']} (${cant}x)',
                                        style: const TextStyle(color: Colors.black, fontSize: 12, fontFamily: 'monospace'),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '\$${sub.toStringAsFixed(2)}',
                                      style: const TextStyle(color: Colors.black, fontSize: 12, fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            
                            const Divider(color: Colors.black38, height: 24, thickness: 1),
                            
                            // Totals
                            _buildReceiptRow('SUBTOTAL:', '\$${widget.subtotal.toStringAsFixed(2)}'),
                            _buildReceiptRow('PROPINA:', '\$${widget.propina.toStringAsFixed(2)}'),
                            _buildReceiptRow('I.V.A (16% INC):', '\$${(widget.subtotal * 0.16).toStringAsFixed(2)}'),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL:', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'monospace')),
                                Text('\$${widget.total.toStringAsFixed(2)}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'monospace')),
                              ],
                            ),
                            
                            const Divider(color: Colors.black38, height: 24, thickness: 1),
                            
                            if (widget.isFinalPayment) ...[
                              _buildReceiptRow('MÉTODO DE PAGO:', paymentLabel),
                              const SizedBox(height: 10),
                            ],

                            // Barcode simulation
                            Container(
                              height: 36,
                              width: 200,
                              color: Colors.black,
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: List.generate(40, (index) => Container(
                                  width: index % 3 == 0 ? 3 : 1,
                                  color: Colors.white,
                                )),
                              ),
                            ),
                            
                            const SizedBox(height: 12),
                            Text(
                              widget.isFinalPayment ? '*** GRACIAS POR SU VISITA ***' : '*** PRE-TICKET SOLO PARA REVISIÓN ***',
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      // Zigzag jagged footer pattern
                      CustomPaint(
                        size: const Size(380, 10),
                        painter: _JaggedBorderPainter(isBottom: true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
            const SizedBox(height: 24),
              // Close / OK button shown when print completes
              if (_printingCompleted)
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Aceptar',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black87, fontSize: 12, fontFamily: 'monospace')),
          Text(value, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

/// Modelo auxiliar para la división de cuentas
class _SplitPerson {
  String nombre;
  List<int> itemIndices;
  _SplitPerson(this.nombre, {List<int>? indices}) : itemIndices = indices ?? [];
}

// Painter for thermal paper jagged tear-off edge
class _JaggedBorderPainter extends CustomPainter {
  final bool isBottom;
  _JaggedBorderPainter({this.isBottom = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF9F9FB)
      ..style = PaintingStyle.fill;

    final path = Path();
    final jaggedWidth = 10.0;
    final jaggedHeight = 6.0;
    
    if (isBottom) {
      path.moveTo(0, 0);
      for (double i = 0; i < size.width; i += jaggedWidth) {
        path.lineTo(i + jaggedWidth / 2, jaggedHeight);
        path.lineTo(i + jaggedWidth, 0);
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
    } else {
      path.moveTo(0, size.height);
      for (double i = 0; i < size.width; i += jaggedWidth) {
        path.lineTo(i + jaggedWidth / 2, size.height - jaggedHeight);
        path.lineTo(i + jaggedWidth, size.height);
      }
      path.lineTo(size.width, 0);
      path.lineTo(0, 0);
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
