import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:yaru/yaru.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YaruWindowTitleBar.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyAgentApp());
}
