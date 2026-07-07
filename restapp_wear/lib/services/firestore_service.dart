import 'package:cloud_firestore/cloud_firestore.dart';

class HistorialEvento {
  final String id;
  final String tipo;
  final String descripcion;
  final String usuario;
  final DateTime timestamp;
  final Map<String, dynamic> datos;

  HistorialEvento({
    required this.id,
    required this.tipo,
    required this.descripcion,
    required this.usuario,
    required this.timestamp,
    this.datos = const {},
  });

  factory HistorialEvento.fromFirestore(String id, Map<String, dynamic> data) {
    return HistorialEvento(
      id: id,
      tipo: data['tipo'] ?? '',
      descripcion: data['descripcion'] ?? '',
      usuario: data['usuario'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      datos: data['datos'] ?? {},
    );
  }
}

class MesaData {
  final String id;
  final String numero;
  final String salon;
  final String estado;
  final int capacidad;
  final List<Map<String, dynamic>>? orden;
  final String? atendidoPor;

  MesaData({
    required this.id,
    required this.numero,
    required this.salon,
    required this.estado,
    required this.capacidad,
    this.orden,
    this.atendidoPor,
  });

  factory MesaData.fromFirestore(String id, Map<String, dynamic> data) {
    final ordenData = data['orden'];
    return MesaData(
      id: id,
      numero: data['numero']?.toString() ?? '',
      salon: data['salon'] ?? '',
      estado: data['status'] ?? 'libre',
      capacidad: (data['capacidad'] as num?)?.toInt() ?? 0,
      orden: ordenData is List ? List<Map<String, dynamic>>.from(ordenData) : null,
      atendidoPor: data['atendidoPor'] as String?,
    );
  }

  double get total {
    if (orden == null) return 0;
    double totalCalc = 0;
    for (final item in orden!) {
      totalCalc += ((item['precio'] as num?)?.toDouble() ?? 0) *
          ((item['cantidad'] as num?)?.toInt() ?? 1);
    }
    return totalCalc;
  }

  bool get requiereAtencion =>
      estado == 'pago' || estado == 'ocupada';

  String get estadoLabel {
    switch (estado) {
      case 'libre':
        return 'Libre';
      case 'ocupada':
        return 'Ocupada';
      case 'pago':
        return 'Pago';
      case 'reservada':
        return 'Reservada';
      default:
        return estado;
    }
  }
}

class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _mesas =>
      _db.collection('mesas');
  static CollectionReference<Map<String, dynamic>> get _historial =>
      _db.collection('historial');
  static Stream<List<MesaData>> streamMesas() {
    return _mesas.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return MesaData.fromFirestore(doc.id, doc.data());
      }).toList();
    });
  }

  static Stream<List<HistorialEvento>> streamHistorial({int limit = 50}) {
    return _historial
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return HistorialEvento.fromFirestore(doc.id, doc.data());
      }).toList();
    });
  }

  static Future<void> actualizarEstadoMesa(
      String mesaId, String nuevoEstado) async {
    try {
      await _mesas.doc(mesaId).update({'status': nuevoEstado});
    } catch (e) {
      // silent
    }
  }

  static Future<void> aprobarPago(String mesaId) async {
    try {
      await _mesas.doc(mesaId).update({
        'status': 'libre',
        'orden': [],
      });
    } catch (e) {
      // silent
    }
  }
}
