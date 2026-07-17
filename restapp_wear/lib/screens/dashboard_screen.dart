import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import '../widgets/notification_tile.dart';
import '../widgets/table_status_tile.dart';
import 'table_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FA),
        foregroundColor: const Color(0xFF1A1D23),
        elevation: 0,
        toolbarHeight: 28,
        title: const Text(
          'RestApp',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                _TabButton(
                  label: 'Alertas',
                  icon: Icons.notifications,
                  selected: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
                const SizedBox(width: 4),
                _TabButton(
                  label: 'Mesas',
                  icon: Icons.table_restaurant,
                  selected: _selectedTab == 1,
                  onTap: () => setState(() => _selectedTab = 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: _selectedTab == 0
                ? _buildHistorialTab()
                : _buildMesasTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorialTab() {
    return StreamBuilder<List<HistorialEvento>>(
      stream: FirestoreService.streamHistorial(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              child: Text(
                'Error: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFEF5350), fontSize: 8),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF2563EB),
              strokeWidth: 2,
            ),
          );
        }
        final eventos = snapshot.data!;
        if (eventos.isEmpty) {
          return const Center(
            child: Text(
              'Sin notificaciones',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: eventos.length,
          itemBuilder: (context, index) {
            final evento = eventos[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: NotificationTile(evento: evento),
            );
          },
        );
      },
    );
  }

  Widget _buildMesasTab() {
    return StreamBuilder<List<MesaData>>(
      stream: FirestoreService.streamMesas(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              child: Text(
                'Error: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFEF5350), fontSize: 8),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF2563EB),
              strokeWidth: 2,
            ),
          );
        }
        final mesas = snapshot.data!;
        final urgentes = mesas.where((m) => m.estado == 'pago').toList();
        final ocupadas = mesas.where((m) => m.estado == 'ocupada').toList();
        final libres = mesas.where((m) => m.estado == 'libre').toList();

        return ListView(
          padding: const EdgeInsets.all(4),
          children: [
            if (urgentes.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'SOLICITUDES DE PAGO',
                  style: TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              ...urgentes.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: TableStatusTile(
                      mesa: m,
                      onTap: () => _abrirMesa(m),
                    ),
                  )),
              SizedBox(height: urgentes.isNotEmpty && (ocupadas.isNotEmpty || libres.isNotEmpty) ? 4 : 0),
            ],
            if (ocupadas.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'OCUPADAS',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              ...ocupadas.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: TableStatusTile(
                      mesa: m,
                      onTap: () => _abrirMesa(m),
                    ),
                  )),
              SizedBox(height: ocupadas.isNotEmpty && libres.isNotEmpty ? 4 : 0),
            ],
            if (libres.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'LIBRES',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              ...libres.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: TableStatusTile(
                      mesa: m,
                      onTap: () => _abrirMesa(m),
                    ),
                  )),
            ],
            if (mesas.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(
                  child: Text(
                    'No hay mesas registradas',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _abrirMesa(MesaData mesa) {
    if (!kIsWeb) HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TableDetailScreen(mesa: mesa),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? const Color(0xFF2563EB) : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 10,
                color: selected
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF1A1D23)
                      : const Color(0xFF9CA3AF),
                  fontSize: 9,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
