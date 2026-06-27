import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipo de evento para el historial
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

  factory HistorialEvento.fromFirestore(
      String id, Map<String, dynamic> data) {
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

/// Servicio centralizado para todas las operaciones con Firebase
class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── COLECCIONES ───────────────────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> get _meseros =>
      _db.collection('meseros');
  static CollectionReference<Map<String, dynamic>> get _mesas =>
      _db.collection('mesas');
  static CollectionReference<Map<String, dynamic>> get _historial =>
      _db.collection('historial');
  static DocumentReference<Map<String, dynamic>> get _config =>
      _db.collection('config').doc('general');
  static CollectionReference<Map<String, dynamic>> get _platillos =>
      _db.collection('platillos');

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

      final rol = data['rol'] ?? (id.toUpperCase() == 'ADMIN' ? 'admin' : 'mesero');
      return {...data, 'docId': query.docs.first.id, 'rol': rol};
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
    double? totalCobrar,
    Timestamp? ocupadaDesde,
    String usuario = 'admin',
    int mesaNumero = 0,
    String? oldStatus,
    String? atendidoPor,
    double? totalOrden,
  }) async {
    final data = <String, dynamic>{'status': status};
    if (totalCobrar != null) data['totalCobrar'] = totalCobrar;
    if (atendidoPor != null) data['atendidoPor'] = atendidoPor;
    if (ocupadaDesde != null) {
      data['ocupadaDesde'] = ocupadaDesde;
    } else if (status == 'libre') {
      data['totalCobrar'] = FieldValue.delete();
      data['ocupadaDesde'] = FieldValue.delete();
      data['atendidoPor'] = FieldValue.delete();
    }
    await _mesas.doc(docId).update(data);
    final datos = <String, dynamic>{
      'docId': docId,
      'status': status,
      'oldStatus': oldStatus ?? '',
      'mesaNumero': mesaNumero,
    };
    if (totalOrden != null) datos['totalOrden'] = totalOrden;
    logEvent(
      tipo: 'cambio_estado',
      descripcion: 'Mesa $mesaNumero → $status',
      usuario: usuario,
      datos: datos,
    );
  }

  // ─── CRUD DE MESAS ──────────────────────────────────────────────────────────

  /// Crea una nueva mesa
  static Future<void> createMesa(
      int numero, int capacidad, String salon,
      {String usuario = 'admin'}) async {
    await _mesas.add({
      'numero': numero,
      'capacidad': capacidad,
      'salon': salon,
      'status': 'libre',
    });
    logEvent(
      tipo: 'mesa_creada',
      descripcion: 'Mesa $numero creada ($salon, $capacidad pax)',
      usuario: usuario,
      datos: {'numero': numero, 'capacidad': capacidad, 'salon': salon},
    );
  }

  /// Elimina una mesa por su docId
  static Future<void> deleteMesa(String docId,
      {String usuario = 'admin', int mesaNumero = 0}) async {
    await _mesas.doc(docId).delete();
    logEvent(
      tipo: 'mesa_eliminada',
      descripcion: 'Mesa $mesaNumero eliminada',
      usuario: usuario,
      datos: {'mesaNumero': mesaNumero},
    );
  }

  /// Actualiza campos específicos de una mesa
  static Future<void> updateMesa(
    String docId,
    Map<String, dynamic> data, {
    String usuario = 'admin',
    int mesaNumero = 0,
  }) async {
    final doc = await _mesas.doc(docId).get();
    final oldData = {...doc.data() ?? {}};
    oldData.remove('orden');
    oldData.remove('ocupadaDesde');
    await _mesas.doc(docId).update(data);
    logEvent(
      tipo: 'mesa_modificada',
      descripcion: 'Mesa $mesaNumero modificada',
      usuario: usuario,
      datos: {
        'docId': docId,
        'mesaNumero': mesaNumero,
        'cambios': data,
        'oldData': oldData,
      },
    );
  }

  // ─── CRUD DE MESEROS ─────────────────────────────────────────────────────────

  /// Stream de todos los meseros
  static Stream<List<Map<String, dynamic>>> getMeserosStream() {
    return _meseros.snapshots().map((snap) {
      return snap.docs
          .map((d) => {...d.data(), 'docId': d.id})
          .toList();
    });
  }

  /// Stream de un mesero individual por docId
  static Stream<Map<String, dynamic>?> getMeseroStream(String docId) {
    return _meseros.doc(docId).snapshots().map((snap) =>
        snap.exists ? {...snap.data()!, 'docId': snap.id} : null);
  }

  /// Crea un nuevo mesero
  static Future<void> createMesero(
      String id, String nombre, String pin, String rol,
      {String turno = 'Matutino'}) async {
    final data = <String, dynamic>{
      'id': id.toUpperCase(),
      'nombre': nombre,
      'rol': rol,
      'turno': turno,
      'activo': true,
    };
    if (pin.isNotEmpty) data['pin'] = pin;
    await _meseros.doc(id.toUpperCase()).set(data);
  }

  /// Actualiza un mesero
  static Future<void> updateMesero(
      String docId, Map<String, dynamic> data) async {
    await _meseros.doc(docId).update(data);
  }

  /// Elimina un mesero
  static Future<void> deleteMesero(String docId) async {
    await _meseros.doc(docId).delete();
  }

  /// Actualiza el salón de todas las mesas que tenían el nombre anterior
  static Future<void> updateMesasSalon(String oldName, String newName) async {
    final query = await _mesas.where('salon', isEqualTo: oldName).get();
    if (query.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in query.docs) {
      batch.update(doc.reference, {'salon': newName});
    }
    await batch.commit();
  }

  // ─── PLATILLOS (MENÚ) ───────────────────────────────────────────────────────

  /// Stream de todos los platillos ordenados por nombre
  static Stream<List<Platillo>> getPlatillosStream() {
    return _platillos.orderBy('nombre').snapshots().map((snap) {
      return snap.docs
          .map((d) => Platillo.fromFirestore(d.id, d.data()))
          .toList();
    });
  }

  /// Crea un nuevo platillo
  static Future<void> createPlatillo(
    String nombre,
    String descripcion,
    double precio, {
    String? foto,
    String seccion = 'Platillos',
  }) async {
    await _platillos.add({
      'nombre': nombre,
      'descripcion': descripcion,
      'precio': precio,
      'foto': foto ?? '',
      'disponible': true,
      'seccion': seccion,
    });
  }

  /// Actualiza un platillo
  static Future<void> updatePlatillo(
      String docId, Map<String, dynamic> data) async {
    await _platillos.doc(docId).update(data);
  }

  /// Elimina un platillo
  static Future<void> deletePlatillo(String docId) async {
    await _platillos.doc(docId).delete();
  }

  /// Actualiza nombre/precio de un platillo en todas las órdenes activas de mesas
  static Future<void> updatePlatilloInAllOrdenes(
      String platilloId, Map<String, dynamic> cambios) async {
    final mesasSnap =
        await _mesas.where('status', whereIn: ['ocupada', 'pago']).get();
    if (mesasSnap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in mesasSnap.docs) {
      final orden = List<Map<String, dynamic>>.from(doc.data()['orden'] ?? []);
      bool modified = false;
      for (int i = 0; i < orden.length; i++) {
        if (orden[i]['platilloId'] == platilloId) {
          if (cambios.containsKey('nombre')) orden[i]['nombre'] = cambios['nombre'];
          if (cambios.containsKey('precio')) orden[i]['precio'] = cambios['precio'];
          modified = true;
        }
      }
      if (modified) {
        batch.update(doc.reference, {'orden': orden});
      }
    }
    await batch.commit();
  }

  // ─── ÓRDENES EN MESAS ────────────────────────────────────────────────────────

  /// Agrega un item a la orden de una mesa
  static Future<void> addItemToOrden(
      String mesaDocId, Map<String, dynamic> item) async {
    await _mesas.doc(mesaDocId).update({
      'orden': FieldValue.arrayUnion([item]),
    });
  }

  /// Elimina un item de la orden de una mesa
  static Future<void> removeItemFromOrden(
      String mesaDocId, Map<String, dynamic> item) async {
    await _mesas.doc(mesaDocId).update({
      'orden': FieldValue.arrayRemove([item]),
    });
  }

  /// Limpia la orden de una mesa
  static Future<void> clearOrden(String mesaDocId) async {
    await _mesas.doc(mesaDocId).update({
      'orden': FieldValue.delete(),
    });
  }

  /// Reemplaza toda la orden de una mesa
  static Future<void> setOrden(
      String mesaDocId, List<Map<String, dynamic>> items) async {
    await _mesas.doc(mesaDocId).update({'orden': items});
  }

  // ─── CONFIGURACIÓN ──────────────────────────────────────────────────────────

  /// Stream de la configuración general
  static Stream<Map<String, dynamic>?> getConfigStream() {
    return _config.snapshots().map((snap) => snap.data());
  }

  /// Guarda la configuración general
  static Future<void> saveConfig(Map<String, dynamic> data) async {
    await _config.set(data, SetOptions(merge: true));
  }

  // ─── HISTORIAL ──────────────────────────────────────────────────────────────

  /// Registra un evento en el historial
  static Future<void> logEvent({
    required String tipo,
    required String descripcion,
    required String usuario,
    Map<String, dynamic> datos = const {},
  }) async {
    await _historial.add({
      'tipo': tipo,
      'descripcion': descripcion,
      'usuario': usuario,
      'timestamp': FieldValue.serverTimestamp(),
      'datos': datos,
    });
  }

  /// Stream del historial ordenado por fecha descendente
  static Stream<List<HistorialEvento>> getHistorialStream() {
    return _historial
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => HistorialEvento.fromFirestore(d.id, d.data()))
            .toList());
  }

  /// Consulta única de historial por usuario para el día de hoy
  static Future<List<HistorialEvento>> getHistorialHoyByUsuario(String usuario) async {
    final inicio = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final fin = inicio.add(const Duration(days: 1));
    final snap = await _historial
        .where('usuario', isEqualTo: usuario)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .where('timestamp', isLessThan: Timestamp.fromDate(fin))
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs
        .map((d) => HistorialEvento.fromFirestore(d.id, d.data()))
        .toList();
  }

  /// Actualiza la sección de todos los platillos que tenían una sección anterior
  static Future<void> updatePlatilloSeccion(
      String oldSeccion, String newSeccion) async {
    final snap =
        await _platillos.where('seccion', isEqualTo: oldSeccion).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'seccion': newSeccion});
    }
    await batch.commit();
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
        'rol': 'mesero',
        'activo': true,
      });
      await _meseros.doc('M002').set({
        'id': 'M002',
        'nombre': 'Ana García',
        'pin': '5678',
        'rol': 'mesero',
        'activo': true,
      });
      await _meseros.doc('ADMIN').set({
        'id': 'ADMIN',
        'nombre': 'Administrador',
        'rol': 'admin',
        'activo': true,
      });
    }

    // Verificar si ya hay config
    final configSnap = await _config.get();
    if (!configSnap.exists) {
      await _config.set({
        'nombreRestaurante': 'Sucursal Centro',
        'salones': ['Salón Principal', 'Terraza', 'Barra'],
        'capacidadDefault': 4,
        'menuSecciones': ['Platillos', 'Postres', 'Bebidas'],
      });
    }

    // Verificar si ya hay platillos
    final platillosSnap = await _platillos.limit(1).get();
    if (platillosSnap.docs.isEmpty) {
      final batch = _db.batch();
      final List<Map<String, dynamic>> platillos = [
        {'nombre': 'Hamburguesa Clásica', 'descripcion': 'Carne angus 200g, queso, lechuga, tomate', 'precio': 189.0, 'foto': '', 'disponible': true, 'seccion': 'Platillos'},
        {'nombre': 'Pizza Pepperoni', 'descripcion': 'Pizza personal de pepperoni con queso mozzarella', 'precio': 159.0, 'foto': '', 'disponible': true, 'seccion': 'Platillos'},
        {'nombre': 'Ensalada César', 'descripcion': 'Lechuga romana, crutones, parmesano, aderezo césar', 'precio': 129.0, 'foto': '', 'disponible': true, 'seccion': 'Platillos'},
        {'nombre': 'Tacos al Pastor', 'descripcion': '3 tacos de pastor con piña, cebolla y cilantro', 'precio': 99.0, 'foto': '', 'disponible': true, 'seccion': 'Platillos'},
        {'nombre': 'Pastel de Chocolate', 'descripcion': 'Rebanada de pastel de chocolate con ganache', 'precio': 79.0, 'foto': '', 'disponible': true, 'seccion': 'Postres'},
        {'nombre': 'Flan Napolitano', 'descripcion': 'Flan napolitano con caramelo', 'precio': 69.0, 'foto': '', 'disponible': true, 'seccion': 'Postres'},
        {'nombre': 'Refresco', 'descripcion': 'Coca-Cola, Sprite o Fanta 355ml', 'precio': 35.0, 'foto': '', 'disponible': true, 'seccion': 'Bebidas'},
        {'nombre': 'Agua Natural', 'descripcion': 'Agua purificada 500ml', 'precio': 25.0, 'foto': '', 'disponible': true, 'seccion': 'Bebidas'},
      ];
      for (final p in platillos) {
        batch.set(_platillos.doc(), p);
      }
      await batch.commit();
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
  final double? totalCobrar;
  final DateTime? ocupadaDesde;
  final List<Map<String, dynamic>> orden;

  MesaData({
    required this.docId,
    required this.numero,
    required this.capacidad,
    required this.status,
    this.salon = 'Salón Principal',
    this.totalCobrar,
    this.ocupadaDesde,
    this.orden = const [],
  });

  factory MesaData.fromFirestore(String docId, Map<String, dynamic> data) {
    Timestamp? ts = data['ocupadaDesde'];
    return MesaData(
      docId: docId,
      numero: (data['numero'] as num).toInt(),
      capacidad: (data['capacidad'] as num).toInt(),
      status: MesaStatusExt.fromString(data['status'] ?? 'libre'),
      salon: data['salon'] ?? 'Salón Principal',
      totalCobrar: data['totalCobrar'] != null
          ? (data['totalCobrar'] as num).toDouble()
          : null,
      ocupadaDesde: ts?.toDate(),
      orden: data['orden'] != null
          ? List<Map<String, dynamic>>.from(data['orden'])
          : [],
    );
  }

  double get totalOrden {
    double total = 0;
    for (final item in orden) {
      total += ((item['precio'] as num?)?.toDouble() ?? 0) *
          ((item['cantidad'] as num?)?.toInt() ?? 1);
    }
    return total;
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

/// Modelo para un platillo del menú
class Platillo {
  final String docId;
  final String nombre;
  final String descripcion;
  final double precio;
  final String? foto;
  final bool disponible;
  final String seccion;

  Platillo({
    required this.docId,
    required this.nombre,
    required this.descripcion,
    required this.precio,
    this.foto,
    this.disponible = true,
    this.seccion = 'Platillos',
  });

  factory Platillo.fromFirestore(String docId, Map<String, dynamic> data) {
    return Platillo(
      docId: docId,
      nombre: data['nombre'] ?? '',
      descripcion: data['descripcion'] ?? '',
      precio: (data['precio'] as num?)?.toDouble() ?? 0,
      foto: data['foto'],
      disponible: data['disponible'] ?? true,
      seccion: data['seccion'] ?? 'Platillos',
    );
  }
}
