// File generated for Main Booth Desktop Drive
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDWADQu1oBsYZV3YcBl5U1b79h7I7FJ3Vs',
    appId: '1:770315997596:web:a1b2c3d4e5f6g7h8i9j0k1',
    messagingSenderId: '770315997596',
    projectId: 'mainboothmyh',
    authDomain: 'mainboothmyh.firebaseapp.com',
    storageBucket: 'mainboothmyh.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDWADQu1oBsYZV3YcBl5U1b79h7I7FJ3Vs',
    appId: '1:770315997596:android:a1b2c3d4e5f6g7h8i9j0k2',
    messagingSenderId: '770315997596',
    projectId: 'mainboothmyh',
    storageBucket: 'mainboothmyh.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAHCCJUjEzY3FQNa_FEtI0_gOyBWiJUAxo',
    appId: '1:770315997596:ios:a1b2c3d4e5f6g7h8i9j0k3',
    messagingSenderId: '770315997596',
    projectId: 'mainboothmyh',
    storageBucket: 'mainboothmyh.firebasestorage.app',
    iosClientId:
        '770315997596-trjjqrlrdmjuh7rsgmhbchnrg4q49684.apps.googleusercontent.com',
    iosBundleId: 'com.mainbooth.drive',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAHCCJUjEzY3FQNa_FEtI0_gOyBWiJUAxo',
    appId: '1:770315997596:ios:a1b2c3d4e5f6g7h8i9j0k4',
    messagingSenderId: '770315997596',
    projectId: 'mainboothmyh',
    storageBucket: 'mainboothmyh.firebasestorage.app',
    iosClientId:
        '770315997596-trjjqrlrdmjuh7rsgmhbchnrg4q49684.apps.googleusercontent.com',
    iosBundleId: 'com.mainbooth.drive',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDWADQu1oBsYZV3YcBl5U1b79h7I7FJ3Vs',
    appId: '1:770315997596:web:a1b2c3d4e5f6g7h8i9j0k5',
    messagingSenderId: '770315997596',
    projectId: 'mainboothmyh',
    authDomain: 'mainboothmyh.firebaseapp.com',
    storageBucket: 'mainboothmyh.firebasestorage.app',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyDWADQu1oBsYZV3YcBl5U1b79h7I7FJ3Vs',
    appId: '1:770315997596:web:a1b2c3d4e5f6g7h8i9j0k6',
    messagingSenderId: '770315997596',
    projectId: 'mainboothmyh',
    authDomain: 'mainboothmyh.firebaseapp.com',
    storageBucket: 'mainboothmyh.firebasestorage.app',
  );
}
