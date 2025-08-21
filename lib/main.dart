/// Main Booth Drive - 메인 엔트리포인트
/// 음악 협업을 위한 데스크탑 클라우드 드라이브

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
// Core components
import 'core/drive_manager.dart';

// Utils
import 'utils/logger.dart';
import 'utils/auth_manager.dart';

// Screens
import 'ui/screens/main_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/settings_screen.dart';

// Config
import 'config/firebase_config.dart';

void main() async {
  // Flutter 바인딩 초기화
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 로거 초기화
    await Logger.initialize(enableFileLogging: true);
    final logger = Logger('Main');
    logger.info('Main Booth Drive 시작');

    // 데스크탑 환경 설정
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await _initializeDesktop();
    }

    // Firebase 초기화
    await _initializeFirebase();

    // 앱 실행
    runApp(const MainBoothDriveApp());
  } catch (e) {
    final logger = Logger('Main');
    logger.error('앱 초기화 실패', e);

    // 에러 다이얼로그 표시 후 종료
    runApp(ErrorApp(error: e.toString()));
  }
}

/// 데스크탑 환경 초기화
Future<void> _initializeDesktop() async {
  final logger = Logger('Desktop');

  try {
    // 윈도우 매니저 초기화
    await windowManager.ensureInitialized();

    // 윈도우 설정
    const windowOptions = WindowOptions(
      size: Size(1000, 700),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'Main Booth Drive',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    logger.info('데스크탑 환경 초기화 완료');
  } catch (e) {
    logger.error('데스크탑 환경 초기화 실패', e);
    rethrow;
  }
}

/// Firebase 초기화
Future<void> _initializeFirebase() async {
  final logger = Logger('Firebase');

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: FirebaseConfig.apiKey,
        authDomain: FirebaseConfig.authDomain,
        projectId: FirebaseConfig.projectId,
        storageBucket: FirebaseConfig.storageBucket,
        messagingSenderId: FirebaseConfig.messagingSenderId,
        appId: FirebaseConfig.appId,
      ),
    );

    logger.info('Firebase 초기화 완료');
  } catch (e) {
    logger.error('Firebase 초기화 실패', e);
    rethrow;
  }
}

/// 메인 애플리케이션
class MainBoothDriveApp extends StatefulWidget {
  const MainBoothDriveApp({Key? key}) : super(key: key);

  @override
  State<MainBoothDriveApp> createState() => _MainBoothDriveAppState();
}

class _MainBoothDriveAppState extends State<MainBoothDriveApp>
    with WindowListener {
  final Logger _logger = Logger('App');
  final SystemTray _systemTray = SystemTray();

  bool _isInitialized = false;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// 앱 초기화
  Future<void> _initializeApp() async {
    try {
      _logger.info('앱 초기화 시작');

      // 시스템 트레이 초기화
      await _initializeSystemTray();

      // Drive Manager 초기화
      await DriveManager.instance.initialize();

      // 인증 상태 확인
      final authManager = AuthManager.instance;
      await authManager.initialize();

      setState(() {
        _isAuthenticated = authManager.isAuthenticated;
        _isInitialized = true;
      });

      _logger.info('앱 초기화 완료');
    } catch (e) {
      _logger.error('앱 초기화 실패', e);
      // 에러 처리 - 최소한의 UI로 시작
      setState(() {
        _isInitialized = true;
        _isAuthenticated = false;
      });
    }
  }

  /// 시스템 트레이 초기화
  Future<void> _initializeSystemTray() async {
    try {
      await _systemTray.initSystemTray(
        iconPath: Platform.isMacOS
            ? 'assets/icons/tray_icon_macos.png'
            : 'assets/icons/tray_icon.png',
        title: 'Main Booth Drive',
        toolTip: 'Main Booth Drive - 음악 협업을 위한 클라우드 드라이브',
      );

      // 트레이 메뉴 설정
      final menu = Menu();
      menu.buildFrom([
        MenuItemLabel(
          label: '열기',
          onClicked: (menuItem) => _showWindow(),
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: DriveManager.instance.isRunning ? '정지' : '시작',
          onClicked: (menuItem) => _toggleDrive(),
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: '설정',
          onClicked: (menuItem) => _showSettings(),
        ),
        MenuItemLabel(
          label: '종료',
          onClicked: (menuItem) => _exitApp(),
        ),
      ]);

      await _systemTray.setContextMenu(menu);
    } catch (e) {
      _logger.error('시스템 트레이 초기화 실패', e);
    }
  }

  /// 윈도우 표시
  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// 드라이브 토글
  Future<void> _toggleDrive() async {
    final driveManager = DriveManager.instance;
    if (driveManager.isRunning) {
      await driveManager.stop();
    } else {
      await driveManager.start();
    }
    // 트레이 메뉴 업데이트
    await _initializeSystemTray();
  }

  /// 설정 화면 표시
  void _showSettings() {
    // 설정 화면을 새 창으로 열거나 기존 창에서 네비게이션
    _showWindow();
    // Navigator 사용하여 설정 화면으로 이동
  }

  /// 앱 종료
  Future<void> _exitApp() async {
    try {
      await DriveManager.instance.stop();
      await _systemTray.destroy();
      await windowManager.destroy();
      SystemNavigator.pop();
    } catch (e) {
      _logger.error('앱 종료 중 오류', e);
      exit(0);
    }
  }

  /// 로그인 성공 핸들러
  void _onLoginSuccess() {
    setState(() {
      _isAuthenticated = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Main Booth Drive',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: _buildHome(),
      routes: {
        '/login': (context) => LoginScreen(onLoginSuccess: _onLoginSuccess),
        '/main': (context) => const MainScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }

  /// 홈 화면 빌드
  Widget _buildHome() {
    if (!_isInitialized) {
      return const SplashScreen();
    }

    if (!_isAuthenticated) {
      return LoginScreen(onLoginSuccess: _onLoginSuccess);
    }

    return const MainScreen();
  }

  /// 라이트 테마
  ThemeData _buildTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1), // Indigo
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Pretendard',
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  /// 다크 테마
  ThemeData _buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1), // Indigo
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Pretendard',
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // WindowListener 메서드들
  @override
  void onWindowClose() async {
    // 창 닫기 시 트레이로 숨기기
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  @override
  void onWindowMinimize() {
    // 최소화 시 트레이로 숨기기
    windowManager.hide();
  }

  @override
  void onWindowFocus() {
    setState(() {});
  }
}

/// 스플래시 화면
class SplashScreen extends StatelessWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_queue,
              size: 80,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Main Booth Drive',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '음악 협업을 위한 클라우드 드라이브',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '초기화 중...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 오류 화면 앱
class ErrorApp extends StatelessWidget {
  final String error;

  const ErrorApp({Key? key, required this.error}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Main Booth Drive - Error',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Main Booth Drive 시작 오류',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  error,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => exit(0),
                  child: const Text('종료'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
