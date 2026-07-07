import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class TableStatusTile extends StatelessWidget {
  final MesaData mesa;
  final VoidCallback onTap;

  const TableStatusTile({
    super.key,
    required this.mesa,
    required this.onTap,
  });

  Color get _estadoColor {
    switch (mesa.estado) {
      case 'libre':
        return const Color(0xFF2ECC71);
      case 'ocupada':
        return const Color(0xFFEF5350);
      case 'pago':
        return const Color(0xFFFFA726);
      case 'reservada':
        return const Color(0xFF42A5F5);
      default:
        return const Color(0xFF90A4AE);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A1E24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _estadoColor.withValues(alpha: 0.4),
          width: mesa.estado == 'pago' ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _estadoColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    mesa.numero,
                    style: TextStyle(
                      color: _estadoColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mesa ${mesa.numero}',
                      style: const TextStyle(
                        color: Color(0xFFF0F6FC),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      mesa.salon,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: _estadoColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  mesa.estadoLabel,
                  style: TextStyle(
                    color: _estadoColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
