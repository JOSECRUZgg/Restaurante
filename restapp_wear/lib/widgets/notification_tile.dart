import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';

class NotificationTile extends StatelessWidget {
  final HistorialEvento evento;

  const NotificationTile({super.key, required this.evento});

  IconData get _icon {
    switch (evento.tipo) {
      case 'pago_solicitado':
        return Icons.payments;
      case 'orden_agregada':
        return Icons.restaurant;
      case 'mesa_ocupada':
        return Icons.table_restaurant;
      case 'mesa_liberada':
        return Icons.check_circle;
      case 'pago_aprobado':
        return Icons.done_all;
      default:
        return Icons.notifications;
    }
  }

  Color get _color {
    switch (evento.tipo) {
      case 'pago_solicitado':
        return const Color(0xFFF59E0B);
      case 'orden_agregada':
        return const Color(0xFF3B82F6);
      case 'mesa_ocupada':
        return const Color(0xFFEF4444);
      case 'mesa_liberada':
        return const Color(0xFF10B981);
      case 'pago_aprobado':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _color.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (!kIsWeb) HapticFeedback.lightImpact();
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon, color: _color, size: 12),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evento.descripcion,
                      style: const TextStyle(
                        color: Color(0xFF1A1D23),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      evento.usuario,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatTime(evento.timestamp),
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
