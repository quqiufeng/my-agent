import 'dart:async';
import 'dart:convert';
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
        title: 'agent',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.apply(yaru.theme),
        darkTheme: AppTheme.apply(yaru.darkTheme),
        themeMode: ThemeMode.system,
        builder: (context, child) => Scaffold(
          backgroundColor: ChinaColors.shuangdi,
          appBar: const YaruWindowTitleBar(
            onClose: YaruWindow.minimize,
            title: Text('agent · 语音助手'),
          ),
          body: child ?? const SizedBox.shrink(),
        ),
        home: const HomePage(),
      ),
    );
  }
}

/// 一路摄像头：ffmpeg 持续把画面写成 jpg（-update 1），UI 仅在文件更新时读字节。
class _Cam {
  _Cam(this.label, this.args, this.jpg);
  final String label;
  final List<String> args;
  final String jpg;
  Process? proc;
  Uint8List? bytes;
  int mtime = 0;

  void refresh() {
    try {
      final f = File(jpg);
      if (!f.existsSync()) return;
      final m = f.lastModifiedSync().millisecondsSinceEpoch;
      if (m == mtime) return;
      final b = f.readAsBytesSync();
      if (b.isNotEmpty) {
        bytes = b;
        mtime = m;
      }
    } catch (_) {}
  }
}

class _CamView extends StatelessWidget {
  const _CamView({required this.cam});
  final _Cam cam;
  @override
  Widget build(BuildContext context) {
    final bytes = cam.bytes;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF11110F)),
        if (bytes != null && bytes.isNotEmpty)
          Image.memory(bytes,
              gaplessPlayback: true, fit: BoxFit.contain, filterQuality: FilterQuality.low),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: ChinaColors.nenjulv,
                borderRadius: BorderRadius.circular(6)),
            child: Text(cam.label,
                style: const TextStyle(fontSize: 13, color: ChinaColors.ink)),
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
  String _clock = '';
  int _mic = 0;
  int _micHold = 0;
  String _last = '';
  Process? _micProc;
  Timer? _camTimer, _uiTimer;
  final ValueNotifier<int> _camTick = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    final env = Platform.environment;
    final usb = env['CAM_USB_INDEX'] ?? '0';
    final rtsp = env['RTSP_URL'] ?? '';
    if (env['CAM_USB_ONLY'] != '1') {
      _cams.add(_Cam('USB', [
        '-loglevel', 'error', '-f', 'v4l2', '-i', '/dev/video$usb',
        '-vf', 'scale=960:-2', '-r', '20', '-q:v', '5',
        '-f', 'image2', '-update', '1', '-y', '/tmp/myagent_cam_usb.jpg'
      ], '/tmp/myagent_cam_usb.jpg'));
    }
    if (rtsp.isNotEmpty) {
      _cams.add(_Cam('RTSP', [
        '-loglevel', 'error', '-rtsp_transport', 'tcp', '-i', rtsp,
        '-vf', 'scale=960:-2', '-r', '20', '-q:v', '5',
        '-f', 'image2', '-update', '1', '-y', '/tmp/myagent_cam_rtsp.jpg'
      ], '/tmp/myagent_cam_rtsp.jpg'));
    }
    for (final c in _cams) {
      _spawn(c);
    }
    _micLoop(env['VOICE_MIC_DEV'] ?? 'plughw:2,0',
        env['VOICE_MIC_CARD'] ?? '2', env['VOICE_MIC_GAIN'] ?? '7810', env);
    _tickClock();
    _camTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      for (final c in _cams) {
        c.refresh();
      }
      _camTick.value++;
    });
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_tickClock);
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

  List<int> _wavHeader(int dataLen) {
    final h = BytesBuilder();
    void s(String v) => h.add(ascii.encode(v));
    void u32(int v) => h.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
    void u16(int v) => h.add([v & 0xff, (v >> 8) & 0xff]);
    s('RIFF'); u32(36 + dataLen); s('WAVE'); s('fmt '); u32(16);
    u16(1); u16(1); u32(16000); u32(16000 * 2); u16(2); u16(16);
    s('data'); u32(dataLen);
    return h.toBytes();
  }

  Future<String> _transcribe(Uint8List pcm, Map<String, String> env) async {
    final bin = env['SENSEVOICE_BIN'] ?? '/opt/SenseVoice.cpp/bin/sense-voice-main';
    final model = env['SENSEVOICE_MODEL'] ?? '/data/models/sense-voice-small-q4_k.gguf';
    final lang = env['SENSEVOICE_LANG'] ?? 'zh';
    final wav = '/tmp/myagent_ui_$pid.wav';
    try {
      File(wav).writeAsBytesSync(_wavHeader(pcm.length) + pcm);
      final r = await Process.run(bin, ['-m', model, '-l', lang, '-t', '4', '-f', wav],
          stdoutEncoding: utf8);
      final out = (r.stdout as String?) ?? '';
      final re = RegExp(r'\[[0-9.]+-[0-9.]+\]\s*(.*)');
      final parts = <String>[];
      for (final line in out.split('\n')) {
        final m = re.firstMatch(line);
        if (m != null) {
          final t = m.group(1)!.replaceAll(RegExp(r'<\|[^|]*\|>'), '').trim();
          if (t.isNotEmpty) parts.add(t);
        }
      }
      return parts.join(' ').trim();
    } catch (_) {
      return '';
    } finally {
      try {
        File(wav).deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _micLoop(String dev, String card, String gain, Map<String, String> env) async {
    try {
      await Process.run('amixer', ['-c', card, 'sset', 'Mic', gain]);
    } catch (_) {}
    final silenceFrames = ((int.tryParse(env['VOICE_SILENCE_MS'] ?? '1200') ?? 1200) ~/ 128).clamp(1, 99);
    final minFrames = ((int.tryParse(env['VOICE_MIN_SPEECH_MS'] ?? '300') ?? 300) ~/ 128).clamp(1, 99);
    while (mounted) {
      try {
        final p = await Process.start('arecord',
            ['-D', dev, '-f', 'S16_LE', '-r', '16000', '-c', '1', '-q', '-t', 'raw', '-']);
        _micProc = p;
        final buf = <int>[];
        var noise = 200, silent = 0;
        var speaking = false;
        final acc = <int>[];
        await for (final chunk in p.stdout) {
          buf.addAll(chunk);
          while (buf.length >= 4096) {
            final frame = buf.sublist(0, 4096);
            buf.removeRange(0, 4096);
            double sum = 0;
            var peak = 0;
            for (var i = 0; i + 1 < frame.length; i += 2) {
              var v = frame[i] | (frame[i + 1] << 8);
              if (v >= 0x8000) v -= 0x10000;
              final a = v.abs();
              if (a > peak) peak = a;
              sum += v * v.toDouble();
            }
            final rms = math.sqrt(sum / (frame.length ~/ 2));
            final db = rms > 0 ? 20 * (math.log(rms / 32768) / math.ln10) : -90;
            final lvl = (((db + 60) / 50) * 100).clamp(0, 100).round();
            _micHold = lvl > _micHold ? lvl : (_micHold - 2).clamp(0, 100);
            if (mounted) setState(() => _mic = _micHold);

            final thr = math.max(500, noise * 2);
            if (!speaking) {
              noise = (noise * 3 + peak) ~/ 4;
              if (peak >= thr) {
                speaking = true;
                silent = 0;
                acc
                  ..clear()
                  ..addAll(frame);
              }
            } else {
              acc.addAll(frame);
              if (peak >= thr) {
                silent = 0;
              } else {
                silent++;
              }
              if (silent >= silenceFrames) {
                speaking = false;
                final speechFrames = acc.length ~/ 4096 - silent;
                if (speechFrames >= minFrames) {
                  final text = await _transcribe(Uint8List.fromList(acc), env);
                  if (mounted && text.isNotEmpty) setState(() => _last = text);
                }
                acc.clear();
                silent = 0;
              }
            }
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
    _camTimer?.cancel();
    _uiTimer?.cancel();
    _camTick.dispose();
    for (final c in _cams) {
      c.proc?.kill();
    }
    _micProc?.kill();
    super.dispose();
  }

  Widget _tree() {
    if (_full != 0 && _full <= _cams.length) {
      return _CamView(cam: _cams[_full - 1]);
    }
    if (_cams.length == 1) return _CamView(cam: _cams[0]);
    if (_cams.isEmpty) {
      return const Center(
          child: Text('无摄像头（设 CAM_USB_INDEX / RTSP_URL）',
              style: TextStyle(color: ChinaColors.muted)));
    }
    return Row(children: [
      for (final c in _cams) Expanded(child: _CamView(cam: c)),
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
          child: ValueListenableBuilder<int>(
            valueListenable: _camTick,
            builder: (_, __, ___) => _tree(),
          ),
        ),
      ),
      _statusBar(),
    ]);
  }

  Widget _statusBar() {
    final lc = _mic > 60 ? ChinaColors.zhusha : (_mic > 25 ? ChinaColors.warn : ChinaColors.qinglv);
    return Container(
      decoration: const BoxDecoration(
        color: ChinaColors.nenjulv,
        border: Border(top: BorderSide(color: ChinaColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: _mic > 25 ? ChinaColors.orange : ChinaColors.qinglv,
                    shape: BoxShape.circle)),
            const SizedBox(width: 12),
            const Text('等待语音', style: TextStyle(fontSize: 17, color: ChinaColors.ink)),
            const SizedBox(width: 24),
            const Text('MIC', style: TextStyle(fontSize: 11, color: ChinaColors.muted)),
            const SizedBox(width: 8),
            SizedBox(
              width: 220,
              height: 8,
              child: Stack(children: [
                Container(
                    decoration: BoxDecoration(
                        color: const Color(0xFFDCEBC2),
                        borderRadius: BorderRadius.circular(4))),
                FractionallySizedBox(
                  widthFactor: (_mic / 100).clamp(0.0, 1.0),
                  child: Container(
                      decoration: BoxDecoration(
                          color: lc, borderRadius: BorderRadius.circular(4))),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Text('$_mic', style: const TextStyle(fontSize: 12, color: ChinaColors.muted)),
            const Spacer(),
            Text(_clock,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: ChinaColors.ink)),
          ]),
          const SizedBox(height: 8),
          Text(_last.isEmpty ? '（等待识别…）' : _last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, color: ChinaColors.daiLan)),
        ],
      ),
    );
  }
}
