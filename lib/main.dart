import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/cupertino.dart';

void main() async {
  // Flutterの初期化を保証
  WidgetsFlutterBinding.ensureInitialized();
  
  // YouTubeの音を止めないためのオーディオセッション設定
  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
    androidAudioAttributes: const AndroidAudioAttributes(
      contentType: AndroidAudioContentType.music,
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HIIT Interval Timer',
      theme: ThemeData(
        brightness: Brightness.dark, // トレーニングアプリっぽくダークモードに
        primarySwatch: Colors.blue,
      ),
      home: const TimerScreen(),
    );
  }
}

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  // 設定用の秒数（初期値）
  int _offSetting = 10;
  int _onSetting = 30;

  // 現在の状態管理
  int _timeLeft = 0;
  bool _isOffTime = true; // true: OFFタイム, false: ONタイム
  bool _isRunning = false;

  Timer? _timer;
  
  // オーディオプレイヤー（just_audio）
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // 音声を再生する関数（assetsに保存したパスを指定）
  Future<void> _playSound(String fileName) async {
    try {
      await _audioPlayer.setAsset('assets/audio/$fileName');
      _audioPlayer.play();
    } catch (e) {
      debugPrint("音声再生エラー: $e");
    }
  }

  // iOS風のタイマー設定ピッカーを表示する関数
  void _showTimePicker({required bool isOffTime}) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => Container(
        height: 250,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: SafeArea(
          top: false,
          child: CupertinoTimerPicker(
            mode: CupertinoTimerPickerMode.ms, // 「分:秒」の選択モード
            initialTimerDuration: Duration(
              seconds: isOffTime ? _offSetting : _onSetting,
            ),
            onTimerDurationChanged: (Duration newDuration) {
              setState(() {
                if (isOffTime) {
                  _offSetting = newDuration.inSeconds;
                  if (!_isRunning && _isOffTime) _timeLeft = _offSetting;
                } else {
                  _onSetting = newDuration.inSeconds;
                  if (!_isRunning && !_isOffTime) _timeLeft = _onSetting;
                }
              });
            },
          ),
        ),
      ),
    );
  }

  // タイマー開始
  void _startTimer() {
    if (_isRunning) return;

    _playSound('ready.mp3');

    setState(() {
      _isRunning = true;
      _isOffTime = true; // OFFタイムからスタート
      _timeLeft = _offSetting;
    });

    // 1秒ごとに実行されるタイマー
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _tick();
    });
  }

  // タイマー停止
  void _stopTimer() {
    _timer?.cancel();

    _playSound('finish.mp3');
    
    setState(() {
      _isRunning = false;
      _timeLeft = 0;
    });
  }

  // 1秒ごとの処理（メインロジック）
  void _tick() {
    if (_timeLeft == 4) _playSound('count3.mp3');
    if (_timeLeft == 3) _playSound('count2.mp3');
    if (_timeLeft == 2) _playSound('count1.mp3');
    if (_timeLeft == 1) _playSound('count0.mp3');

    setState(() {
      _timeLeft--;

      if (_timeLeft < 0) {
        if (_isOffTime) {
          _isOffTime = false;
          _timeLeft = _onSetting;
          _playSound('go.mp3');
        } else {
          _isOffTime = true;
          _timeLeft = _offSetting;
          _playSound('rest.mp3');
        }
      }
    });
  }

  // 「〇分〇秒」の形にきれいに表示するためのヘルパー関数
  String _formatDuration(int totalSeconds) {
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return "$minutes分 $seconds秒";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HIIT タイマー')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 🔴【ここを書き換えました！】
            // プラス・マイナスのボタンを廃止し、タップするとiOS風ピッカーが出るボタンに変更
            if (!_isRunning) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // --- OFFタイム設定 ---
                  GestureDetector(
                    onTap: () => _showTimePicker(isOffTime: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.5)), // 👈 ここを書き換え
                      ),
                      child: Column(
                        children: [
                          const Text("OFFタイム", style: TextStyle(fontSize: 14, color: Colors.grey)),
                          const SizedBox(height: 8),
                          Text(
                            _formatDuration(_offSetting),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // --- ONタイム設定 ---
                  GestureDetector(
                    onTap: () => _showTimePicker(isOffTime: false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.5)), // 👈 ここを書き換え
                      ),
                      child: Column(
                        children: [
                          const Text("ONタイム", style: TextStyle(fontSize: 14, color: Colors.grey)),
                          const SizedBox(height: 8),
                          Text(
                            _formatDuration(_onSetting),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 60),
            ],

            // 現在のステータス表示（実行中のみ）
            if (_isRunning) ...[
              Text(
                _isOffTime ? "OFF TIME" : "ON TIME",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: _isOffTime ? Colors.blue : Colors.red,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '$_timeLeft',
                style: const TextStyle(fontSize: 96, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 60),
            ],

            // 操作ボタン
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _isRunning ? null : _startTimer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  ),
                  child: const Text('START', style: TextStyle(fontSize: 20, color: Colors.white)),
                ),
                const SizedBox(width: 40),
                ElevatedButton(
                  onPressed: _isRunning ? _stopTimer : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  ),
                  child: const Text('STOP', style: TextStyle(fontSize: 20, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}