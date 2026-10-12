import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
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

/// 一路摄像头：由 ffmpeg 持续把画面写成 jpg（-update 1），UI 定时刷新。
class _Cam {
  _Cam(this.label, this.args, this.jpg);
  final String label;
  final List<String> args;
  final String jpg;
  Process? proc;
  Uint8List? bytes;
  int mtime = 0;

  // 仅当文件更新（mtime 变）才读字节，避免无谓解码
  void refresh() {
    try {
      final f = File(jpg);
      if (!f.existsSync()) return;
      final m = f.lastModifiedSync().millisecondsSinceEpoch;
      if (m == mtime) return;
      final b = f.readAsBytesSync();
      if (b.isNotEmpty) { bytes = b; mtime = m; }
    } catch (_) {}
  }
}

class _CamView extends StatelessWidget {
  const _CamView({required this.cam, required this.tick});
  final _Cam cam;
  final int tick;

  @override
  Widget build(BuildContext context) {
    final bytes = cam.bytes;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF11110F)),
        if (bytes != null && bytes.isNotEmpty)
          Image.memory(bytes,
              gaplessPlayback: true, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Kami.parchment,
                borderRadius: BorderRadius.circular(6)),
            child: Text(cam.label,
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
  final List<_Cam> _cams = [];
  int _full = 0;
  int _tick = 0;
  String _clock = '';
  Timer? _timer;
  int _mic = 0; // 0..100
  int _micHold = 0;
  Process? _micProc;

  @override
  void initState() {
    super.initState();
    final env = Platform.environment;
    final usb = env['CAM_USB_INDEX'] ?? '0';
    final rtsp = env['RTSP_URL'] ?? '';
    if (env['CAM_USB_ONLY'] != '1') {
      _cams.add(_Cam(
        'USB',
        ['-loglevel', 'error', '-f', 'v4l2', '-i', '/dev/video$usb',
         '-vf', 'scale=1280:-2', '-r', '15', '-q:v', '2',
         '-f', 'image2', '-update', '1', '-y', '/tmp/myagent_cam_usb.jpg'],
        '/tmp/myagent_cam_usb.jpg',
      ));
    }
    if (rtsp.isNotEmpty) {
      _cams.add(_Cam(
        'RTSP',
        ['-loglevel', 'error', '-rtsp_transport', 'tcp', '-i', rtsp,
         '-vf', 'scale=1280:-2', '-r', '15', '-q:v', '2',
         '-f', 'image2', '-update', '1', '-y', '/tmp/myagent_cam_rtsp.jpg'],
        '/tmp/myagent_cam_rtsp.jpg',
      ));
    }
    for (final c in _cams) {
      _spawn(c);
    }
    _startMic(env['VOICE_MIC_DEV'] ?? 'plughw:2,0',
        env['VOICE_MIC_CARD'] ?? '2', env['VOICE_MIC_GAIN'] ?? '7810');
    _tickClock();
    _timer = Timer.periodic(const Duration(milliseconds: 55), (_) {
      _tickClock();
      for (final c in _cams) {
        c.refresh();
      }
      if (mounted) setState(() => _tick++);
    });
  }

  Future<void> _spawn(_Cam c) async {
    try {
      c.proc = await Process.start('ffmpeg', c.args);
      c.proc!.stderr.listen((_) {});
    } catch (e) {
      debugPrint('[cam ${c.label}] $e');
    }
  }

  // 麦克风电平：流式 arecord，按 ~128ms 帧算 RMS → dB 映射 + 峰值保持衰减
  Future<void> _startMic(String dev, String card, String gain) async {
    try {
      await Process.run('amixer', ['-c', card, 'sset', 'Mic', gain]);
    } catch (_) {}
    while (mounted) {
      try {
        final p = await Process.start('arecord',
            ['-D', dev, '-f', 'S16_LE', '-r', '16000', '-c', '1', '-q', '-t', 'raw', '-']);
        _micProc = p;
        final buf = <int>[];
        await for (final chunk in p.stdout) {
          buf.addAll(chunk);
          while (buf.length >= 4096) {
            final frame = buf.sublist(0, 4096);
            buf.removeRange(0, 4096);
            double sum = 0;
            final n = frame.length ~/ 2;
            for (var i = 0; i + 1 < frame.length; i += 2) {
              var v = frame[i] | (frame[i + 1] << 8);
              if (v >= 0x8000) v -= 0x10000;
              sum += v * v.toDouble();
            }
            final rms = math.sqrt(sum / n);
            final db = rms > 0 ? 20 * (math.log(rms / 32768) / math.ln10) : -90;
            final lvl = (((db + 60) / 50) * 100).clamp(0, 100).round();
            _micHold = lvl > _micHold ? lvl : (_micHold - 2).clamp(0, 100);
            if (mounted) setState(() => _mic = _micHold);
          }
        }
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  void _tickClock() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    _clock = '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _cams) {
      c.proc?.kill();
    }
    _micProc?.kill();
    super.dispose();
  }

  Widget _tree() {
    if (_full != 0 && _full <= _cams.length) {
      return _CamView(cam: _cams[_full - 1], tick: _tick);
    }
    if (_cams.length == 1) return _CamView(cam: _cams[0], tick: _tick);
    if (_cams.isEmpty) {
      return const Center(
          child: Text('无摄像头（设 CAM_USB_INDEX / RTSP_URL）',
              style: TextStyle(fontFamily: 'MapleMonoNF', color: Kami.muted)));
    }
    return Row(children: [
      for (final c in _cams) Expanded(child: _CamView(cam: c, tick: _tick)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: GestureDetector(
          onDoubleTapDown: (d) {
            final w = context.findRenderObject() is RenderBox
                ? (context.findRenderObject() as RenderBox).size.width
                : 1.0;
            setState(() {
              if (_full != 0) {
                _full = 0;
              } else if (_cams.length > 1) {
                _full = d.localPosition.dx < w / 2 ? 1 : 2;
              } else if (_cams.isNotEmpty) {
                _full = 1;
              }
            });
          },
          child: _tree(),
        ),
      ),
      _statusBar(),
    ]);
  }

  Widget _statusBar() {
    final lc = _mic > 60 ? Kami.error : (_mic > 25 ? ChinaColors.warn : ChinaColors.qinglv);
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Kami.surface,
        border: Border(top: BorderSide(color: Kami.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: _mic > 25 ? ChinaColors.orange : ChinaColors.qinglv,
                shape: BoxShape.circle)),
        const SizedBox(width: 12),
        const Text('等待语音',
            style: TextStyle(fontFamily: 'MapleMonoNF', fontSize: 15, color: Kami.ink)),
        const SizedBox(width: 24),
        const Text('MIC',
            style: TextStyle(fontFamily: 'MapleMonoNF', fontSize: 11, color: Kami.muted)),
        const SizedBox(width: 8),
        SizedBox(
          width: 220,
          height: 8,
          child: Stack(children: [
            Container(decoration: BoxDecoration(color: Kami.tint, borderRadius: BorderRadius.circular(4))),
            FractionallySizedBox(
              widthFactor: (_mic / 100).clamp(0.0, 1.0),
              child: Container(decoration: BoxDecoration(color: lc, borderRadius: BorderRadius.circular(4))),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Text('$_mic',
            style: const TextStyle(fontFamily: 'MapleMonoNF', fontSize: 12, color: Kami.muted)),
        const Spacer(),
        Text(_clock,
            style: const TextStyle(
                fontFamily: 'MapleMonoNF',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Kami.ink)),
      ]),
    );
  }
}
