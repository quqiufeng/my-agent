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
  bool _awake = false;
  DateTime? _awakeUntil;
  int _awakeLeft = 0;
  List<String> _wake = const ['你好星期五', '你好礼拜五'];
  String _wakeLabel = '你好 星期五';
  int _awakeMs = 60000;
  String _wakeReply = '在的，老板';
  String _ackTpl = '';
  String _agentUrl = 'http://localhost:4097';
  String _prefix = '[语音输入]';
  Map<String, String> _env = const {};
  Timer? _awakeTimer;
  Process? _micProc;
  Timer? _uiTimer, _snapTimer;

  @override
  void initState() {
    super.initState();
    final env = Platform.environment;
    _env = env;
    final wake = env['VOICE_WAKE'];
    if (wake != null && wake.trim().isNotEmpty) {
      _wake = wake
          .split(',')
          .map((e) => _norm(e))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    _wakeLabel = env['VOICE_WAKE_LABEL'] ?? '你好 星期五';
    _awakeMs = int.tryParse(env['VOICE_AWAKE_MS'] ?? '60000') ?? 60000;
    _wakeReply = env['VOICE_WAKE_REPLY'] ?? '在的，老板';
    _ackTpl = env['VOICE_ACK'] ?? '';
    _agentUrl = env['AGENT_URL'] ?? 'http://localhost:4097';
    _prefix = env['VOICE_PREFIX'] ?? '[语音输入]';
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

  // 归一化：去掉空白与标点，便于唤醒词模糊匹配
  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\u3000]'), '')
      .replaceAll(RegExp(r'[，。、！？,.!?:;；：（）()\[\]【】\-—~…]'), '');

  // 调试日志
  void _vlog(String s) {
    try {
      File('/tmp/myagent_voice.log')
          .writeAsStringSync('${DateTime.now().toIso8601String()} $s\n',
              mode: FileMode.append);
    } catch (_) {}
  }

  // 从原句中剥离唤醒词（容忍字间空格与标点），返回剩余指令
  String? _commandFrom(String text) {
    final norm = _norm(text);
    for (final w in _wake) {
      if (w.isEmpty || !norm.contains(w)) continue;
      final pat = RegExp(w.split('').map(RegExp.escape).join(r'[\s\u3000，。、,.!！?？]*'));
      final rest = text.replaceFirst(pat, '');
      final cleaned = rest.replaceAll(RegExp(r'^[\s\u3000，。、,.!！?？]+'), '').trim();
      return cleaned;
    }
    return null;
  }

  void _onCommand(String cmd) {
    // 收到指令：保持唤醒并续期（1 分钟内无新指令才回静默）
    if (mounted) {
      setState(() {
        _awake = true;
        _last = cmd;
      });
    } else {
      _awake = true;
    }
    _armAwake();
    _vlog('forward cmd="$cmd"');
    unawaited(_forwardBrain(cmd));
    final ack = _ackTpl.replaceAll('{cmd}', cmd).trim();
    if (ack.isNotEmpty) unawaited(_say(ack));
  }

  // 转发到大脑（opencode TUI @4097）：append-prompt → submit-prompt
  Future<void> _forwardBrain(String cmd) async {
    if (cmd.trim().isEmpty) return;
    try {
      final attached =
          await Process.run('pgrep', ['-f', 'opencode[ ]attach']);
      if (attached.exitCode != 0) {
        await Process.run('/opt/my-agent/operator/ensure_tui.sh', []);
      }
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      Future<void> post(String path, String body) async {
        final req = await client.postUrl(Uri.parse('$_agentUrl$path'));
        req.headers.contentType = ContentType.json;
        req.write(body);
        final resp = await req.close();
        await resp.drain<void>();
      }

      await post('/tui/append-prompt',
          jsonEncode({'text': '$_prefix $cmd'}));
      await post('/tui/submit-prompt', '{}');
      client.close();
      _vlog('forward OK "$cmd"');
    } catch (e) {
      _vlog('forward FAIL "$cmd" $e');
    }
  }

  void _handleHeard(String text) {
    final cmd = _commandFrom(text);
    _vlog('heard="$text" awake=$_awake wake=${cmd != null}');
    if (cmd != null) {
      // 命中唤醒词：若同句里还带着指令，直接执行；否则进入聆听态并语音应答
      if (cmd.isNotEmpty) {
        _onCommand(cmd);
      } else {
        _wakeUp();
      }
      return;
    }
    // 已在聆听态：这句就是指令
    if (_awake) _onCommand(text);
  }

  // 语音回复：调用 voice/say.sh（内部会置 /tmp/myagent_tts_active 防回环）
  Future<void> _say(String text) async {
    if (text.trim().isEmpty) return;
    final bin = _env['SAY_SH'] ?? '/opt/my-agent/voice/say.sh';
    try {
      await Process.run(bin, [text]);
    } catch (_) {}
  }

  // 唤醒窗口计时：到期未见指令 → 回静默，重新等待唤醒词
  void _armAwake() {
    _awakeTimer?.cancel();
    _awakeUntil = DateTime.now().add(Duration(milliseconds: _awakeMs));
    _awakeLeft = (_awakeMs / 1000).ceil();
    _awakeTimer = Timer(Duration(milliseconds: _awakeMs), () {
      if (mounted) {
        setState(() {
          _awake = false;
          _awakeUntil = null;
          _awakeLeft = 0;
        });
      }
    });
  }

  void _wakeUp() {
    _vlog('WAKE ack="$_wakeReply"');
    if (mounted) setState(() => _awake = true);
    _armAwake();
    unawaited(_say(_wakeReply).then((_) {
      // 应答播完后重新计时，保证播报结束后仍有完整聆听窗口
      if (mounted && _awake) _armAwake();
    }));
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

            // TTS 播报期间静音输入，避免把自己的声音当成指令（回环）
            // 兜底：标志超过 30s 视为陈旧（脚本异常退出未清理），不再静音
            final ttsFlag = File('/tmp/myagent_tts_active');
            if (ttsFlag.existsSync() &&
                DateTime.now().difference(ttsFlag.statSync().modified).inSeconds < 30) {
              if (acc.isNotEmpty) acc.clear();
              speaking = false;
              silent = 0;
              continue;
            }

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
                  if (mounted && text.isNotEmpty) _handleHeard(text);
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
    if (_awake && _awakeUntil != null) {
      final left = _awakeUntil!.difference(n).inSeconds;
      _awakeLeft = left < 0 ? 0 : left;
    }
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _snapTimer?.cancel();
    _awakeTimer?.cancel();
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
                    color: _awake
                        ? ChinaColors.orange
                        : (_mic > 25 ? ChinaColors.orange : ChinaColors.qinglv),
                    shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Text(
                _awake
                    ? '正在聆听指令… ${_awakeLeft}s'
                    : '等待唤醒词「$_wakeLabel」',
                style: TextStyle(
                    fontSize: 17,
                    color: _awake ? ChinaColors.zhusha : ChinaColors.ink)),
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
          Text(_last.isEmpty ? '（说「$_wakeLabel」唤醒我）' : _last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, color: ChinaColors.daiLan)),
        ],
      ),
    );
  }
}
