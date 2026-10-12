import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YaruWindowTitleBar.ensureInitialized();
  runApp(const MyAgentApp());
}
