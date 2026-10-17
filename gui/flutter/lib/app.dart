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

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  static const _cam = MethodChannel('agent/camera');
  int _texId = 0;
  List<int> _streamIds = const [];
  List<int> _wh = const []; // 每路纹理尺寸 [usbW,usbH, 流1W,流1H, ...]
  int? _full; // 双击某路后全屏显示该路的索引；null=分屏
  String _clock = '';
  int _mic = 0;
  int _micHold = 0;
  String _last = '';
  String _song = '';
  bool _musicPlaying = false;
  bool _musicPaused = false;
  bool _wxAttention = false;
  int _wxMiss = 0;
  late final AnimationController _wxAnim;
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
    _getStreams();
    _micLoop(env['VOICE_MIC_DEV'] ?? 'plughw:2,0',
        env['VOICE_MIC_CARD'] ?? '2', env['VOICE_MIC_GAIN'] ?? '7810', env);
    _tickClock();
    _wxAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(_tickClock);
        unawaited(_refreshWechat());
        unawaited(_refreshMusic());
      }
    });
    _snapTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      try {
        _cam.invokeMethod('snapshot');
        if (_streamIds.isNotEmpty) _cam.invokeMethod('snapshot2');
      } catch (_) {}
      unawaited(_refreshSizes());
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

  // 纹理实际尺寸：让每格按视频自身宽高比显示，避免竖屏流被撑扁。
  Future<void> _refreshSizes() async {
    try {
      final v = await _cam.invokeMethod<List<Object?>>('textureSizes');
      if (v == null) return;
      final l = v.whereType<int>().toList();
      if (l.toString() != _wh.toString()) {
        if (mounted) setState(() => _wh = l);
      }
    } catch (_) {}
  }

  // 第二路起（萤石等 URL 流）。原生未启用时返回空列表 → 只显示 USB。
  Future<void> _getStreams() async {
    for (var i = 0; i < 50; i++) {
      try {
        final ids = await _cam.invokeMethod<List<Object?>>('streamIds');
        final list = (ids ?? const [])
            .whereType<int>()
            .where((e) => e != 0)
            .toList();
        if (list.isNotEmpty) {
          if (mounted) setState(() => _streamIds = list);
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }
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
    // VOICE_MIC_URL：从网络音频源（手机 /audio）取 16k 单声道 PCM，替代本机声卡
    final micUrl = (env['VOICE_MIC_URL'] ?? '').trim();
    if (micUrl.isEmpty) {
      try {
        await Process.run('amixer', ['-c', card, 'sset', 'Mic', gain]);
      } catch (_) {}
    }
    final silenceFrames = ((int.tryParse(env['VOICE_SILENCE_MS'] ?? '1200') ?? 1200) ~/ 128).clamp(1, 99);
    final minFrames = ((int.tryParse(env['VOICE_MIN_SPEECH_MS'] ?? '300') ?? 300) ~/ 128).clamp(1, 99);
    while (mounted) {
      try {
        final p = micUrl.isNotEmpty
            ? await Process.start('ffmpeg', [
                '-loglevel', 'error', '-i', micUrl,
                '-f', 's16le', '-ar', '16000', '-ac', '1', '-',
              ])
            : await Process.start('arecord',
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

  // 微信是否有未读：双信号取 OR，提高成功率
  //   ① 微信窗口 _NET_WM_STATE=DEMANDS_ATTENTION（任务栏底线同源）
  //   ② 托盘微信绿图标是否在闪（隔 0.22s 两次采样该区域，不同=在闪）
  Future<void> _refreshWechat() async {
    var att = false, blink = false;
    try {
      final r = await Process.run('bash', [
        '-lc',
        r'W=$(xdotool search --name 微信 2>/dev/null | head -1); '
            r'[ -n "$W" ] && xprop -id "$W" _NET_WM_STATE 2>/dev/null'
      ]);
      att = ((r.stdout as String?) ?? '').contains('DEMANDS_ATTENTION');
      final r2 = await Process.run('bash', [
        '-lc',
        r'A=/tmp/myagent_wx_a.png; B=/tmp/myagent_wx_b.png; '
            r'import -window root -crop 64x28+2348+1410 +repage "$A" 2>/dev/null; sleep 0.22; '
            r'import -window root -crop 64x28+2348+1410 +repage "$B" 2>/dev/null; '
            r'cmp -s "$A" "$B" && echo same || echo diff'
      ]);
      blink = ((r2.stdout as String?) ?? '').trim() == 'diff';
    } catch (_) {}
    final on = att || blink;
    // 抖动可能导致信号断续：连续 3 次未命中才熄灭
    if (on) {
      _wxMiss = 0;
    } else {
      _wxMiss++;
    }
    final show = on || _wxMiss < 3;
    if (show != _wxAttention) {
      _wxAttention = show;
      if (show) {
        _wxAnim.repeat(reverse: true);
      } else {
        _wxAnim.stop();
        _wxAnim.value = 0;
      }
      if (mounted) setState(() {});
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

  // 读取当前播放状态（music.lua→/tmp/myagent_music_{now,pid}，tv.sh→/tmp/myagent_tv_{now,pid}）
  // 优先 tv，其次 music，其次按进程名找 vlc；名称取对应 now 文件
  Future<void> _refreshMusic() async {
    var playing = false, paused = false;
    var song = '';
    try {
      final r = await Process.run('bash', [
        '-lc',
        r'TVP=/tmp/myagent_tv.pid; MUSP=/tmp/myagent_music.pid; '
            r'if [ -f "$TVP" ] && [ -d "/proc/$(cat "$TVP" 2>/dev/null)" ]; then echo "$(cat "$TVP")|tv"; '
            r'elif [ -f "$MUSP" ] && [ -d "/proc/$(cat "$MUSP" 2>/dev/null)" ]; then echo "$(cat "$MUSP")|music"; '
            r'else p=$(pgrep -x vlc | head -1); [ -n "$p" ] && echo "$p|?"; fi'
      ]);
      final out = ((r.stdout as String?) ?? '').trim();
      final pid = out.split('|').first.trim();
      final src = out.contains('|') ? out.split('|').last.trim() : '?';
      if (pid.isNotEmpty) {
        final pf = File(src == 'tv' ? '/tmp/myagent_tv.pid' : '/tmp/myagent_music.pid');
        if (!pf.existsSync() || pf.readAsStringSync().trim() != pid) {
          try {
            pf.writeAsStringSync(pid);
          } catch (_) {}
        }
        playing = true;
        try {
          final st = File('/proc/$pid/status').readAsStringSync();
          final m = RegExp(r'State:\s+(\S)').firstMatch(st);
          paused = m != null && m.group(1) == 'T';
        } catch (_) {}
      }
      for (final f in <String>[
        if (src == 'tv') '/tmp/myagent_tv_now' else '/tmp/myagent_music_now',
        if (src == 'tv') '/tmp/myagent_music_now' else '/tmp/myagent_tv_now',
      ]) {
        final nf = File(f);
        if (nf.existsSync()) {
          final s = nf.readAsStringSync().trim();
          if (s.isNotEmpty) {
            song = s;
            break;
          }
        }
      }
      // 兜底：now 文件为空时从 vlc 的 URL 解析名称
      if (playing && song.isEmpty) {
        final rr = await Process.run('bash', [
          '-lc',
          'tr "\\0" "\\n" < /proc/$pid/cmdline | grep -m1 "^http" | sed "s#.*/##" | '
              'python3 -c "import sys,urllib.parse;sys.stdout.write(urllib.parse.unquote(sys.stdin.read().strip()))"'
        ]);
        song = ((rr.stdout as String?) ?? '').trim();
      }
      // 去掉媒体扩展名
      song = song.replaceAll(
          RegExp(r'\.(mkv|mp4|avi|mov|flv|wmv|ts|rmvb|m4v|ape|flac|mp3|m4a|wav|aac|ogg)$',
              caseSensitive: false),
          '');
    } catch (_) {}
    if (playing != _musicPlaying || paused != _musicPaused || song != _song) {
      final wasPlaying = _musicPlaying;
      _musicPlaying = playing;
      _musicPaused = paused;
      _song = song;
      // 刚开始播放时回待唤态（静默）；不静音麦克风，保证仍可被唤醒
      if (playing && !wasPlaying && _awake) {
        _awake = false;
        _awakeTimer?.cancel();
      }
      if (mounted) setState(() {});
    }
  }

  // 暂停/继续：对播放器（音乐/美剧）pid 发 SIGSTOP / SIGCONT
  Future<void> _toggleMusic() async {
    try {
      final r = await Process.run('bash', [
        '-lc',
        r'TVP=/tmp/myagent_tv.pid; MUSP=/tmp/myagent_music.pid; '
            r'if [ -f "$TVP" ] && [ -d "/proc/$(cat "$TVP" 2>/dev/null)" ]; then echo "$(cat "$TVP")|tv"; '
            r'elif [ -f "$MUSP" ] && [ -d "/proc/$(cat "$MUSP" 2>/dev/null)" ]; then echo "$(cat "$MUSP")|music"; '
            r'else p=$(pgrep -x vlc | head -1); [ -n "$p" ] && echo "$p|?"; fi'
      ]);
      final out = ((r.stdout as String?) ?? '').trim();
      final pid = out.split('|').first.trim();
      if (pid.isEmpty) return;
      final sig = _musicPaused ? '-CONT' : '-STOP';
      await Process.run('kill', [sig, pid]);
      await Future.delayed(const Duration(milliseconds: 200));
      await _refreshMusic();
    } catch (_) {}
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _snapTimer?.cancel();
    _awakeTimer?.cancel();
    _wxAnim.dispose();
    _micProc?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panes = <Widget>[
      _camView(_texId, 0),
      for (var i = 0; i < _streamIds.length; i++) _camView(_streamIds[i], i + 1),
    ];
    Widget body;
    if (_texId == 0) {
      body = const Center(
          child: Text('正在启动摄像头…', style: TextStyle(color: ChinaColors.muted)));
    } else if (_full != null && _full! < panes.length) {
      // 双击全屏：叠加返回图标
      body = Stack(children: [
        Positioned.fill(child: panes[_full!]),
        Positioned(left: 12, top: 12, child: _backBtn()),
      ]);
    } else if (panes.length == 1) {
      body = _tapPane(panes, 0);
    } else {
      // 网格排版：≤2 路一行两格；3~4 路 2x2。格子等分对齐，画面按比例居中
      body = Column(children: [
        for (var r = 0; r * _perRow < panes.length; r++) ...[
          if (r > 0) Container(height: 2, color: ChinaColors.border),
          Expanded(
            child: Row(children: [
              for (var i = r * _perRow;
                  i < (r + 1) * _perRow && i < panes.length;
                  i++) ...[
                if (i > r * _perRow) Container(width: 2, color: ChinaColors.border),
                Expanded(child: _tapPane(panes, i)),
              ]
            ]),
          ),
        ],
      ]);
    }
    return Column(children: [Expanded(child: body), _statusBar()]);
  }

  // 双击某路 → 全屏
  Widget _tapPane(List<Widget> panes, int i) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => setState(() => _full = i),
        child: panes[i],
      );

  // 全屏时的返回图标（点它回到分屏）
  Widget _backBtn() => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() => _full = null),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
          ),
        ),
      );

  // 每行几路：1~2 路一行放，3~4 路两行放
  int get _perRow => 2;

  // 该路的宽高比（未知时按 16:9）
  double _aspect(int slot) {
    if (slot * 2 + 1 < _wh.length) {
      final w = _wh[slot * 2], h = _wh[slot * 2 + 1];
      if (w > 0 && h > 0) return w / h;
    }
    return 16 / 9;
  }

  // 分屏时该路占的宽度权重（正比于宽高比，高度一致 → 不裁不扁）
  int _paneFlex(int slot) => (_aspect(slot) * 1000).round().clamp(100, 10000);

  // 单路画面：黑底，按实际分辨率等比缩放居中（不拉伸、不裁切）
  Widget _camView(int id, int slot) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
              aspectRatio: _aspect(slot), child: Texture(textureId: id)),
        ),
      );

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
            const SizedBox(width: 16),
            AnimatedBuilder(
              animation: _wxAnim,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, -3 * _wxAnim.value),
                child: child,
              ),
              child: Icon(Icons.chat,
                  size: 20,
                  color: _wxAttention
                      ? const Color(0xFF07C160)
                      : ChinaColors.muted),
            ),
            const Spacer(),
            Text(_clock,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: ChinaColors.ink)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(_last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, color: ChinaColors.daiLan)),
            ),
            if (_musicPlaying) ...[
              const SizedBox(width: 12),
              Icon(_musicPaused ? Icons.music_off : Icons.music_note,
                  size: 16, color: ChinaColors.daiLan),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(_song.isEmpty ? '正在播放' : _song,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        color: _musicPaused ? ChinaColors.muted : ChinaColors.daiLan)),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _toggleMusic,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(_musicPaused ? Icons.play_arrow : Icons.pause,
                      size: 22, color: ChinaColors.zhusha),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ]),
        ],
      ),
    );
  }
}
