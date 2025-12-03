import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for Clipboard
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'dart:developer' as dev;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'package:workmanager/workmanager.dart';
import 'background_uploader.dart';
import 'queue_store.dart';

// Day 3 demo: go straight to camera flow.
// If you prefer AuthGate first, swap to: home: AuthGate()
import 'capture_screen.dart';
// import 'src/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase init (yours)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check (yours)
  if (Platform.isAndroid) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } else if (Platform.isIOS || Platform.isMacOS) {
    await FirebaseAppCheck.instance.activate(
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.appAttestWithDeviceCheckFallback,
    );
  }

  // Day 3 init
  await QueueStore.init();
  await ensureUploaderRegistered();

  // (Optional) your auth logging — safe to keep
  await wireAuthLogging();

  // 🔽 ADD THIS LINE
  await copyFirebaseIdTokenOnce();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'CoTCamera',
      debugShowCheckedModeBanner: false,
      home: CaptureScreen(), // <-- Day 3: go straight to camera
      // home: AuthGate(),   // <-- use this later if you want login first
    );
  }
}

Future<void> _logAuthSnapshot(User? user) async {
  if (user == null) { dev.log('auth: signed out', name: 'auth'); return; }
  final idTok = await user.getIdTokenResult(true);
  final claims = idTok.claims ?? {};
  final roles = (claims['roles'] is List)
      ? (claims['roles'] as List).map((e) => e.toString()).toList()
      : <String>[];
  final isAdmin = roles.contains('admin') || claims['admin'] == true;
  dev.log('auth: UID: ${user.uid}', name: 'auth');
  dev.log('auth: Claims: $claims', name: 'auth');
  dev.log('auth: Is admin? $isAdmin', name: 'auth');
}

Future<void> wireAuthLogging() async {
  final auth = FirebaseAuth.instance;
  await _logAuthSnapshot(auth.currentUser);
  auth.idTokenChanges().listen((user) async => await _logAuthSnapshot(user));
}

Future<void> copyFirebaseIdTokenOnce() async {
  try {
    final auth = FirebaseAuth.instance;

    // Ensure we have a user (anon is fine)
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
    // Force refresh to be safe
    final String? idToken = await user.getIdToken(true);

    if (idToken == null || idToken.isEmpty) {
      debugPrint('IDTOKEN_ERROR: null or empty');
      return;
    }

    // 1) Log full token to Debug Console / Logcat
    debugPrint('IDTOKEN: $idToken');

    // 2) Copy to clipboard so you can paste in PowerShell
    await Clipboard.setData(ClipboardData(text: idToken));
    debugPrint('IDTOKEN_COPIED_TO_CLIPBOARD');

  } catch (e, st) {
    debugPrint('IDTOKEN_ERROR: $e');
    // optional: dev.log('IDTOKEN_ERROR', name: 'auth', error: e, stackTrace: st);
  }
}
