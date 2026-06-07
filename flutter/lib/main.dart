import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: CodexColors.ink,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: CodexColors.ink,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const CodexLanApp());
}
