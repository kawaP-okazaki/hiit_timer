import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// 通知プラグインの初期化
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // タイムゾーン（日本時間など）を初期化 👈 これを追加
  tz.initializeTimeZones();
  
  // オーディオセッション設定
  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers | AVAudioSessionCategoryOptions.duckOthers,
    androidAudioAttributes: const AndroidAudioAttributes(
      contentType: AndroidAudioContentType.music,
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
  ));

  // 通知の初期設定（iOS用）
  const initializationSettingsIOS = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  const initializationSettings = InitializationSettings(
    iOS: initializationSettingsIOS,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HIIT Interval Timer',
      theme: ThemeData(
        brightness: Brightness.dark,
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

class _TimerScreenState extends State<TimerScreen> with WidgetsBindingObserver {
  int _offSetting = 10;
  int _onSetting = 30;
  int _timeLeft = 0;
  bool _isOffTime = true;
  bool _isRunning = false;

  Timer? _timer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  DateTime? _backgroundTime;

  @override
  void initState() {
    super.initState();
    _audioPlayer.setLoopMode(LoopMode.off);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isRunning) return;

    if (state == AppLifecycleState.paused) {
      _backgroundTime = DateTime.now();
      _timer?.cancel();
      _scheduleBackgroundNotifications();
    } else if (state == AppLifecycleState.resumed) {
      flutterLocalNotificationsPlugin.cancelAll();
      if (_backgroundTime != null) {
        final elapsedSeconds = DateTime.now().difference(_backgroundTime!).inSeconds;
        _handleBackgroundElapsed(elapsedSeconds);
      }
    }
  }

  void _handleBackgroundElapsed(int elapsedSeconds) {
    int remaining = _timeLeft - elapsedSeconds;

    while (remaining < 0) {
      if (_isOffTime) {
        _isOffTime = false;
        remaining += _onSetting + 1;
      } else {
        _isOffTime = true;
        remaining += _offSetting + 1;
      }
    }

    setState(() {
      _timeLeft = remaining;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _tick();
    });
  }

  // 🔴【エラーの起きていた通知予約処理を最新ルールに修正！】
  void _scheduleBackgroundNotifications() async {
    int tempTimeLeft = _timeLeft;
    bool tempIsOffTime = _isOffTime;
    int delay = 0;

    // 現在の場所のローカルタイムゾーン（日本時間など）を取得
    final String timeZoneName = tz.local.name;
    final tz.Location location = tz.getLocation(timeZoneName);

    for (int i = 0; i < 5; i++) {
      delay += tempTimeLeft;
      
      final title = tempIsOffTime ? "ON TIME スタート！" : "OFF TIME スタート！";
      final body = tempIsOffTime ? "限界まで追い込みましょう！" : "しっかり休憩してください。";

      // 現時刻からdelay秒後の「TZDateTime」を正しく作成
      final scheduledDate = tz.TZDateTime.now(location).add(Duration(seconds: delay));

      await flutterLocalNotificationsPlugin.zonedSchedule(
        i,
        title,
        body,
        scheduledDate, // 👈 TZDateTime型に修正
        const NotificationDetails(
          iOS: DarwinNotificationDetails(presentSound: true, presentAlert: true),
        ),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime, // 👈 必須パラメータを追加
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // 👈 必須パラメータを追加
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
      );

      tempIsOffTime = !tempIsOffTime;
      tempTimeLeft = tempIsOffTime ? _offSetting : _onSetting;
    }
  }

  Future<void> _playSound(String fileName) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setAsset('assets/audio/$fileName');
      unawaited(_audioPlayer.play());
    } catch (e) {
      debugPrint("音声再生エラー: $e");
    }
  }

  void _showTimePicker({required bool isOffTime}) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => Container(
        height: 250,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: SafeArea(
          top: false,
          child: CupertinoTimerPicker(
            mode: CupertinoTimerPickerMode.ms,
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

  void _startTimer() {
    if (_isRunning) return;
    _playSound('ready.mp3');
    setState(() {
      _isRunning = true;
      _isOffTime = true;
      _timeLeft = _offSetting;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _tick();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    flutterLocalNotificationsPlugin.cancelAll();
    _playSound('finish.mp3');
    setState(() {
      _isRunning = false;
      _timeLeft = 0;
    });
  }

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
            if (!_isRunning) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  GestureDetector(
                    onTap: () => _showTimePicker(isOffTime: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
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
                  GestureDetector(
                    onTap: () => _showTimePicker(isOffTime: false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
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