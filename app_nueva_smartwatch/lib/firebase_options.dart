import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS no soportado para RestApp Wear.');
      case TargetPlatform.macOS:
        throw UnsupportedError('macOS no soportado.');
      case TargetPlatform.windows:
        throw UnsupportedError('Windows no soportado.');
      case TargetPlatform.linux:
        throw UnsupportedError('Linux no soportado.');
      default:
        throw UnsupportedError('Plataforma no soportada.');
    }
  }

  // Proyecto Firebase: restaurant1-98
  // App ID para com.restapp.restapp_wear
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBT0RsyYbyrrX_SScm1QtfM1suRJrqBY9w',
    appId: '1:684017191171:android:23c3ece11ca293ab574136',
    messagingSenderId: '684017191171',
    projectId: 'restaurant1-98',
    storageBucket: 'restaurant1-98.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBT0RsyYbyrrX_SScm1QtfM1suRJrqBY9w',
    appId: '1:684017191171:android:436b3e9970aae0d9574136',
    messagingSenderId: '684017191171',
    projectId: 'restaurant1-98',
    storageBucket: 'restaurant1-98.firebasestorage.app',
  );
}
