import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _cam = MethodChannel('agent/camera');
  int _texId = 0;
  String _clock = '';
  int _mic = 0;
  int _micHold = 0;
  String _last = '';
  Process? _micProc;
  Timer? _uiTimer, _snapTimer;

  @override
  void initState() {
    super.initState();
    final env = Platform.environment;
    _getTexture();
    _micLoop(env['VOICE_MIC_DEV'] ?? 'plughw:2,0',
        env['VOICE_MIC_CARD'] ?? '2', env['VOICE_MIC_GAIN'] ?? '7810', env);
    _tickClock();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_tickClock);
    });
    _snapTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      try {
        _cam.invokeMethod('snapshot');
      } catch (_) {}
    });
  }

  Future<void> _getTexture() async {
    for (var i = 0; i < 50; i++) {
      try {
        final id = await _cam.invokeMethod<int>('textureId');
        if (id != null && id != 0) {
          if (mounted) setState(() => _texId = id);
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
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
    _uiTimer?.cancel();
    _snapTimer?.cancel();
    _micProc?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: _texId == 0
            ? const Center(
                child: Text('正在启动摄像头…', style: TextStyle(color: ChinaColors.muted)))
            : Texture(textureId: _texId),
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
