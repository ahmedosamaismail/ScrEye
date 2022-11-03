import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutterfire_ui/auth.dart';
import 'app.dart';
import 'models/auth/firebase_options.dart';
import 'package:camera/camera.dart';
late List<CameraDescription> _cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FlutterFireUIAuth.configureProviders([
    const EmailProviderConfiguration(),
  ]);

  runApp(const MyApp());
}