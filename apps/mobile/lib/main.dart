import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'core/config.dart';
import 'core/token_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(buildApp(baseUrl: apiBaseUrl, storage: const SecureSessionStorage()));
}
