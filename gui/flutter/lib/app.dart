import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:yaru/yaru.dart';

import 'theme/app_theme.dart';

class MyAgentApp extends StatelessWidget {
  const MyAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      builder: (context, yaru, child) => MaterialApp(
        title: 'My Agent',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.apply(yaru.theme),
        darkTheme: AppTheme.apply(yaru.darkTheme),
        themeMode: ThemeMode.system,
        builder: (context, child) => Scaffold(
          backgroundColor: Kami.parchment,
          appBar: const YaruWindowTitleBar(
            onClose: YaruWindow.minimize,
            title: Text('My Agent · 语音助手'),
          ),
          body: child ?? const SizedBox.shrink(),
        ),
        home: const HomePage(),
      ),
    );
  }
}

/// 单路摄像头（media_kit / mpv）。双击由父级处理。
class CameraPane extends StatefulWidget {
  const CameraPane({super.key, required this.source, required this.label});
  final String source;
  final String label;

  @override
  State<CameraPane> createState() => _CameraPaneState();
}

class _CameraPaneState extends State<CameraPane> {
  late final Player player;
  late final VideoController controller;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    player.open(Media(widget.source), play: true);
    player.stream.error.listen((e) => debugPrint('[cam ${widget.label}] $e'));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        Video(controller: controller, controls: NoVideoControls, fit: BoxFit.contain),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Kami.parchment,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(widget.label,
                style: const TextStyle(
                    fontFamily: 'MapleMonoNF', fontSize: 13, color: Kami.ink)),
          ),
        ),
      ],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<({String source, String label})> _cameras = [];
  int _full = 0; // 0=分屏, 1/2=某路全屏
  String _clock = '';
  Timer? _t;
  final String _last = '';
  final bool _speaking = false;

  @override
  void initState() {
    super.initState();
    final env = Platform.environment;
    final usbIndex = env['CAM_USB_INDEX'] ?? '0';
    final rtsp = env['RTSP_URL'] ?? '';
    if (env['CAM_USB_ONLY'] != '1') {
      _cameras.add((source: 'av://v4l2:/dev/video$usbIndex', label: 'USB'));
    }
    if (rtsp.isNotEmpty) {
      _cameras.add((source: rtsp, label: 'RTSP'));
    }
    if (_cameras.isEmpty) {
      _cameras.add((source: 'av://v4l2:/dev/video$usbIndex', label: 'USB'));
    }
    _tick();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    setState(() => _clock = '${two(n.hour)}:${two(n.minute)}:${two(n.second)}');
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Widget _cameraTree() {
    if (_full != 0 && _full <= _cameras.length) {
      return CameraPane(
          source: _cameras[_full - 1].source, label: _cameras[_full - 1].label);
    }
    if (_cameras.length == 1) {
      return CameraPane(source: _cameras[0].source, label: _cameras[0].label);
    }
    return Row(children: [
      for (final c in _cameras) Expanded(child: CameraPane(source: c.source, label: c.label)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onDoubleTapDown: (d) {
              final box = context.findRenderObject() as RenderBox?;
              final w = box?.size.width ?? 1;
              setState(() {
                if (_full != 0) {
                  _full = 0;
                } else if (_cameras.length > 1) {
                  _full = d.localPosition.dx < w / 2 ? 1 : 2;
                } else {
                  _full = 1;
                }
              });
            },
            child: _cameraTree(),
          ),
        ),
        _statusBar(),
      ],
    );
  }

  Widget _statusBar() {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Kami.surface,
        border: Border(top: BorderSide(color: Kami.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _speaking ? ChinaColors.orange : ChinaColors.qinglv,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          const Text('等待语音',
              style: TextStyle(fontFamily: 'MapleMonoNF', fontSize: 15, color: Kami.ink)),
          const SizedBox(width: 24),
          const Text('MIC',
              style: TextStyle(fontFamily: 'MapleMonoNF', fontSize: 11, color: Kami.muted)),
          const SizedBox(width: 8),
          Container(
            width: 220,
            height: 8,
            decoration: BoxDecoration(
              color: Kami.tint,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const Spacer(),
          if (_last.isNotEmpty)
            Text('识别: $_last',
                style: const TextStyle(
                    fontFamily: 'MapleMonoNF', fontSize: 14, color: Kami.muted)),
          const SizedBox(width: 20),
          Text(_clock,
              style: const TextStyle(
                  fontFamily: 'MapleMonoNF',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Kami.ink)),
        ],
      ),
    );
  }
}
