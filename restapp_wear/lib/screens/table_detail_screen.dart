import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';

class TableDetailScreen extends StatelessWidget {
  final MesaData mesa;

  const TableDetailScreen({super.key, required this.mesa});

  Color get _estadoColor {
    switch (mesa.estado) {
      case 'libre':
        return const Color(0xFF10B981);
      case 'ocupada':
        return const Color(0xFFEF4444);
      case 'pago':
        return const Color(0xFFF59E0B);
      case 'reservada':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FA),
        foregroundColor: const Color(0xFF1A1D23),
        title: Text('Mesa ${mesa.numero}', style: const TextStyle(fontSize: 12)),
        centerTitle: true,
        elevation: 0,
        toolbarHeight: 26,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _estadoColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(
                    mesa.numero,
                    style: TextStyle(
                      color: _estadoColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _estadoColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  mesa.estadoLabel,
                  style: TextStyle(
                    color: _estadoColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                mesa.salon,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 9,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Capacidad: ${mesa.capacidad} pers.',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 8,
                ),
              ),
              if (mesa.total > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '\$${mesa.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF1A1D23),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const Spacer(),
              if (mesa.estado == 'pago') ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _aprobarPago(context),
                    icon: const Icon(Icons.check_circle, size: 12),
                    label: const Text('Aprobar Pago', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              if (mesa.estado == 'ocupada' || mesa.estado == 'pago') ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _liberarMesa(context),
                    icon: const Icon(Icons.close, size: 12),
                    label: const Text('Liberar Mesa', style: TextStyle(fontSize: 10)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
              if (mesa.estado == 'libre') ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _ocuparMesa(context),
                    icon: const Icon(Icons.table_restaurant, size: 12),
                    label: const Text('Marcar Ocupada', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  void _aprobarPago(BuildContext context) {
    if (!kIsWeb) HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        content: const Text(
          '¿Aprobar pago y liberar la mesa?',
          style: TextStyle(color: Color(0xFF1A1D23)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              FirestoreService.aprobarPago(mesa.id);
              if (!kIsWeb) HapticFeedback.heavyImpact();
              Navigator.pop(context);
            },
            child: const Text('Aprobar',
                style: TextStyle(color: Color(0xFF10B981))),
          ),
        ],
      ),
    );
  }

  void _liberarMesa(BuildContext context) {
    if (!kIsWeb) HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        content: const Text(
          '¿Liberar la mesa? Se perderá la orden actual.',
          style: TextStyle(color: Color(0xFF1A1D23)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              FirestoreService.aprobarPago(mesa.id);
              if (!kIsWeb) HapticFeedback.heavyImpact();
              Navigator.pop(context);
            },
            child: const Text('Liberar',
                style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
  }

  void _ocuparMesa(BuildContext context) {
    if (!kIsWeb) HapticFeedback.heavyImpact();
    FirestoreService.actualizarEstadoMesa(mesa.id, 'ocupada');
    Navigator.pop(context);
  }
}
