import 'package:cloud_firestore/cloud_firestore.dart';

/// Servicio centralizado para todas las operaciones con Firebase
class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── COLECCIONES ───────────────────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> get _meseros =>
      _db.collection('meseros');
  static CollectionReference<Map<String, dynamic>> get _mesas =>
      _db.collection('mesas');

  // ─── AUTENTICACIÓN ─────────────────────────────────────────────────────────

  /// Valida un mesero por su ID (y PIN opcional).
  /// Devuelve el documento del mesero si existe, o null si no.
  static Future<Map<String, dynamic>?> loginMesero(
      String id, String pin) async {
    try {
      final query =
          await _meseros.where('id', isEqualTo: id.toUpperCase()).limit(1).get();

      if (query.docs.isEmpty) return null;

      final data = query.docs.first.data();

      // Validar PIN si existe
      if (data.containsKey('pin') && data['pin'] != pin) return null;

      return {...data, 'docId': query.docs.first.id};
    } catch (e) {
      return null;
    }
  }

  // ─── MESAS EN TIEMPO REAL ──────────────────────────────────────────────────

  /// Stream de todas las mesas ordenadas por número
  static Stream<List<MesaData>> getMesasStream() {
    return _mesas.orderBy('numero').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return MesaData.fromFirestore(doc.id, doc.data());
      }).toList();
    });
  }

  /// Actualiza el estado de una mesa en Firestore
  static Future<void> updateMesaStatus(
    String docId,
    String status, {
    int? comensales,
    double? totalCobrar,
    Timestamp? ocupadaDesde,
  }) async {
    final data = <String, dynamic>{'status': status};
    if (comensales != null) data['comensales'] = comensales;
    if (totalCobrar != null) data['totalCobrar'] = totalCobrar;
    if (ocupadaDesde != null) {
      data['ocupadaDesde'] = ocupadaDesde;
    } else if (status == 'libre') {
      // Limpiar campos cuando se libera la mesa
      data['comensales'] = FieldValue.delete();
      data['totalCobrar'] = FieldValue.delete();
      data['ocupadaDesde'] = FieldValue.delete();
    }
    await _mesas.doc(docId).update(data);
  }

  // ─── SEED DE DATOS INICIALES ───────────────────────────────────────────────

  /// Crea datos de ejemplo en Firestore si las colecciones están vacías.
  /// Se llama una sola vez después del primer login exitoso.
  static Future<void> seedDataIfEmpty() async {
    // Verificar si ya hay mesas
    final mesasSnap = await _mesas.limit(1).get();
    if (mesasSnap.docs.isEmpty) {
      // Crear 10 mesas de ejemplo
      final batch = _db.batch();
      final List<Map<String, dynamic>> mesas = [
        {'numero': 1, 'capacidad': 2, 'status': 'libre', 'salon': 'Salón Principal'},
        {'numero': 2, 'capacidad': 4, 'status': 'libre', 'salon': 'Salón Principal'},
        {'numero': 3, 'capacidad': 4, 'status': 'libre', 'salon': 'Salón Principal'},
        {'numero': 4, 'capacidad': 6, 'status': 'libre', 'salon': 'Terraza'},
        {'numero': 5, 'capacidad': 6, 'status': 'libre', 'salon': 'Terraza'},
        {'numero': 6, 'capacidad': 2, 'status': 'libre', 'salon': 'Barra'},
        {'numero': 7, 'capacidad': 8, 'status': 'libre', 'salon': 'Salón Principal'},
        {'numero': 8, 'capacidad': 4, 'status': 'libre', 'salon': 'Salón Principal'},
        {'numero': 9, 'capacidad': 4, 'status': 'libre', 'salon': 'Terraza'},
        {'numero': 10, 'capacidad': 10, 'status': 'libre', 'salon': 'Salón Principal'},
      ];
      for (final mesa in mesas) {
        batch.set(_mesas.doc(), mesa);
      }
      await batch.commit();
    }

    // Verificar si ya hay meseros
    final meserosSnap = await _meseros.limit(1).get();
    if (meserosSnap.docs.isEmpty) {
      // Crear meseros de ejemplo
      await _meseros.doc('M001').set({
        'id': 'M001',
        'nombre': 'Carlos López',
        'pin': '1234',
        'activo': true,
      });
      await _meseros.doc('M002').set({
        'id': 'M002',
        'nombre': 'Ana García',
        'pin': '5678',
        'activo': true,
      });
      await _meseros.doc('ADMIN').set({
        'id': 'ADMIN',
        'nombre': 'Administrador',
        'activo': true,
      });
    }
  }

}

// ─── MODELO DE DATOS ──────────────────────────────────────────────────────────

enum MesaStatus { libre, ocupada, pago, reservada }

extension MesaStatusExt on MesaStatus {
  String get value {
    switch (this) {
      case MesaStatus.libre: return 'libre';
      case MesaStatus.ocupada: return 'ocupada';
      case MesaStatus.pago: return 'pago';
      case MesaStatus.reservada: return 'reservada';
    }
  }

  static MesaStatus fromString(String s) {
    switch (s) {
      case 'ocupada': return MesaStatus.ocupada;
      case 'pago': return MesaStatus.pago;
      case 'reservada': return MesaStatus.reservada;
      default: return MesaStatus.libre;
    }
  }
}

class MesaData {
  final String docId;
  final int numero;
  final int capacidad;
  final MesaStatus status;
  final String salon;
  final int? comensales;
  final double? totalCobrar;
  final DateTime? ocupadaDesde;

  MesaData({
    required this.docId,
    required this.numero,
    required this.capacidad,
    required this.status,
    this.salon = 'Salón Principal',
    this.comensales,
    this.totalCobrar,
    this.ocupadaDesde,
  });

  factory MesaData.fromFirestore(String docId, Map<String, dynamic> data) {
    Timestamp? ts = data['ocupadaDesde'];
    return MesaData(
      docId: docId,
      numero: (data['numero'] as num).toInt(),
      capacidad: (data['capacidad'] as num).toInt(),
      status: MesaStatusExt.fromString(data['status'] ?? 'libre'),
      salon: data['salon'] ?? 'Salón Principal',
      comensales: data['comensales'] != null
          ? (data['comensales'] as num).toInt()
          : null,
      totalCobrar: data['totalCobrar'] != null
          ? (data['totalCobrar'] as num).toDouble()
          : null,
      ocupadaDesde: ts?.toDate(),
    );
  }

  Duration? get tiempoOcupada {
    if (ocupadaDesde == null) return null;
    return DateTime.now().difference(ocupadaDesde!);
  }

  String get tiempoStr {
    final t = tiempoOcupada;
    if (t == null) return '';
    final h = t.inHours;
    final m = t.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
