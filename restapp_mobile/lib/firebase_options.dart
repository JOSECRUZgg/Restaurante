// Archivo generado manualmente con los datos del google-services.json
// Proyecto Firebase: restaurant1-98

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Opciones de configuración predeterminadas de Firebase para este proyecto.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions no están configuradas para iOS. '
          'Agrega un GoogleService-Info.plist y regenera las opciones.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions no están configuradas para macOS.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions no están configuradas para Windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions no están configuradas para Linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions no están configuradas para esta plataforma.',
        );
    }
  }

  // Opciones para Android (tomadas del google-services.json)
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBT0RsyYbyrrX_SScm1QtfM1suRJrqBY9w',
    appId: '1:684017191171:android:436b3e9970aae0d9574136',
    messagingSenderId: '684017191171',
    projectId: 'restaurant1-98',
    storageBucket: 'restaurant1-98.firebasestorage.app',
  );

  // Opciones para Web (si se activa más adelante)
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBT0RsyYbyrrX_SScm1QtfM1suRJrqBY9w',
    appId: '1:684017191171:android:436b3e9970aae0d9574136',
    messagingSenderId: '684017191171',
    projectId: 'restaurant1-98',
    storageBucket: 'restaurant1-98.firebasestorage.app',
  );
}
