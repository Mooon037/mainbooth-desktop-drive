/// Main Booth Drive 관리자
/// 드라이브의 전체적인 동작을 관리하는 핵심 클래스

import 'dart:async';
import 'dart:io';
import '../sync/sync_engine.dart';
import '../utils/auth_manager.dart';
import '../utils/database_helper.dart';
import '../utils/logger.dart';
import '../utils/file_utils.dart';
import '../config/drive_config.dart';
import 'notification_manager.dart';
import 'status_manager.dart';

class DriveManager {
  static DriveManager? _instance;
  static DriveManager get instance => _instance ??= DriveManager._();

  final Logger _logger = Logger('DriveManager');
  final SyncEngine _syncEngine = SyncEngine.instance;
  final AuthManager _authManager = AuthManager.instance;
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final NotificationManager _notificationManager = NotificationManager.instance;
  final StatusManager _statusManager = StatusManager.instance;

  bool _isInitialized = false;
  bool _isRunning = false;
  Timer? _statusTimer;

  DriveManager._();

  /// 드라이브 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _logger.info('Main Booth Drive 초기화 시작');

      // 로거 초기화
      await Logger.initialize(enableFileLogging: true);

      // 설정 디렉토리 생성
      await _createConfigDirectories();

      // 데이터베이스 초기화
      await _databaseHelper.initialize();

      // 인증 관리자 초기화
      await _authManager.initialize();

      // 알림 관리자 초기화
      await _notificationManager.initialize();

      // 상태 관리자 초기화
      _statusManager.initialize();

      _isInitialized = true;
      _logger.info('Main Booth Drive 초기화 완료');
    } catch (e) {
      _logger.error('드라이브 초기화 실패', e);
      rethrow;
    }
  }

  /// 드라이브 시작
  Future<void> start() async {
    if (!_isInitialized) {
      throw Exception('드라이브가 초기화되지 않았습니다');
    }

    if (_isRunning) {
      _logger.warning('드라이브가 이미 실행 중입니다');
      return;
    }

    try {
      _logger.info('Main Booth Drive 시작');

      // 인증 확인
      if (!_authManager.isAuthenticated) {
        throw Exception('로그인이 필요합니다');
      }

      // 동기화 엔진 시작
      await _syncEngine.start();

      // 상태 업데이트 타이머 시작
      _startStatusTimer();

      _isRunning = true;
      _statusManager.setDriveStatus(DriveStatus.running);

      // 시작 알림
      _notificationManager.showNotification(
        title: 'Main Booth Drive',
        message: '드라이브가 시작되었습니다',
      );

      _logger.info('Main Booth Drive 시작 완료');
    } catch (e) {
      _logger.error('드라이브 시작 실패', e);
      _statusManager.setDriveStatus(DriveStatus.error);
      rethrow;
    }
  }

  /// 드라이브 정지
  Future<void> stop() async {
    if (!_isRunning) return;

    try {
      _logger.info('Main Booth Drive 정지 시작');

      _statusTimer?.cancel();

      // 동기화 엔진 정지
      await _syncEngine.stop();

      _isRunning = false;
      _statusManager.setDriveStatus(DriveStatus.stopped);

      // 정지 알림
      _notificationManager.showNotification(
        title: 'Main Booth Drive',
        message: '드라이브가 정지되었습니다',
      );

      _logger.info('Main Booth Drive 정지 완료');
    } catch (e) {
      _logger.error('드라이브 정지 실패', e);
      rethrow;
    }
  }

  /// 드라이브 재시작
  Future<void> restart() async {
    _logger.info('Main Booth Drive 재시작');

    await stop();
    await Future.delayed(Duration(seconds: 2));
    await start();
  }

  /// 로그인
  Future<bool> signIn(String email, String password) async {
    try {
      final success = await _authManager.signInWithEmail(email, password);

      if (success && !_isRunning) {
        // 로그인 성공 시 자동 시작
        await start();
      }

      return success;
    } catch (e) {
      _logger.error('로그인 실패', e);
      rethrow;
    }
  }

  /// 로그아웃
  Future<void> signOut() async {
    try {
      // 드라이브 정지
      if (_isRunning) {
        await stop();
      }

      // 로그아웃
      await _authManager.signOut();

      // 캐시 정리
      await _clearLocalCache();
    } catch (e) {
      _logger.error('로그아웃 실패', e);
      rethrow;
    }
  }

  /// 설정 디렉토리 생성
  Future<void> _createConfigDirectories() async {
    final directories = [
      DriveConfig.configPath,
      DriveConfig.cachePath,
      DriveConfig.logPath,
      DriveConfig.driveRootPath,
    ];

    for (var dirPath in directories) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        _logger.debug('디렉토리 생성: $dirPath');
      }
    }
  }

  /// 상태 업데이트 타이머 시작
  void _startStatusTimer() {
    _statusTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _updateStatus();
    });
  }

  /// 상태 업데이트
  Future<void> _updateStatus() async {
    try {
      // 동기화 큐 상태
      final queueStatus = _syncEngine.syncQueue.getQueueStatus();
      _statusManager.updateSyncStatus(queueStatus);

      // 디스크 사용량
      final cacheSize = await FileUtils.getCacheSize();
      final driveSize = await FileUtils.getDirectorySize(
        Directory(DriveConfig.driveRootPath),
      );

      _statusManager.updateStorageStatus({
        'cacheSize': cacheSize,
        'driveSize': driveSize,
        'totalSize': cacheSize + driveSize,
      });

      // 데이터베이스 통계
      final stats = await _databaseHelper.getStatistics();
      _statusManager.updateStatistics(stats);
    } catch (e) {
      _logger.error('상태 업데이트 실패', e);
    }
  }

  /// 로컬 캐시 정리
  Future<void> _clearLocalCache() async {
    try {
      _logger.info('로컬 캐시 정리 시작');

      // 캐시 디렉토리 정리
      await FileUtils.clearCache();

      // 드라이브 디렉토리 정리
      final driveDir = Directory(DriveConfig.driveRootPath);
      if (await driveDir.exists()) {
        await for (var entity in driveDir.list()) {
          if (entity is Directory) {
            await entity.delete(recursive: true);
          } else if (entity is File) {
            await entity.delete();
          }
        }
      }

      // 데이터베이스 정리
      await _databaseHelper.cleanup();

      _logger.info('로컬 캐시 정리 완료');
    } catch (e) {
      _logger.error('캐시 정리 실패', e);
    }
  }

  /// 드라이브 설정
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    try {
      final settingsPath = '${DriveConfig.configPath}/settings.json';
      await FileUtils.writeJsonFile(settingsPath, settings);

      _logger.info('설정 업데이트 완료');

      // 설정 변경에 따른 재시작 필요 여부 확인
      if (settings['requireRestart'] == true && _isRunning) {
        await restart();
      }
    } catch (e) {
      _logger.error('설정 업데이트 실패', e);
      rethrow;
    }
  }

  /// 드라이브 설정 로드
  Future<Map<String, dynamic>> loadSettings() async {
    try {
      final settingsPath = '${DriveConfig.configPath}/settings.json';
      final settings = await FileUtils.readJsonFile(settingsPath);

      return settings ?? _getDefaultSettings();
    } catch (e) {
      _logger.error('설정 로드 실패', e);
      return _getDefaultSettings();
    }
  }

  /// 기본 설정
  Map<String, dynamic> _getDefaultSettings() {
    return {
      'autoStart': true,
      'syncInterval': 30,
      'maxCacheSize': 5 * 1024 * 1024 * 1024, // 5GB
      'notifications': true,
      'selectiveSync': false,
      'conflictResolution': 'ask', // ask, local, remote
    };
  }

  /// 드라이브 상태
  bool get isInitialized => _isInitialized;
  bool get isRunning => _isRunning;
  bool get isAuthenticated => _authManager.isAuthenticated;

  /// 사용자 정보
  String? get userId => _authManager.userId;
  String get userName => _authManager.userName;

  /// 프로젝트 열기 (Finder/Explorer에서)
  Future<void> openProject(String projectId) async {
    try {
      final projectPath = '${DriveConfig.driveRootPath}/Projects/$projectId';
      final projectDir = Directory(projectPath);

      if (!await projectDir.exists()) {
        throw Exception('프로젝트 폴더를 찾을 수 없습니다');
      }

      if (Platform.isMacOS) {
        await Process.run('open', [projectPath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [projectPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [projectPath]);
      }
    } catch (e) {
      _logger.error('프로젝트 열기 실패', e);
      rethrow;
    }
  }

  /// 종료
  Future<void> shutdown() async {
    try {
      _logger.info('Main Booth Drive 종료 시작');

      if (_isRunning) {
        await stop();
      }

      await _databaseHelper.close();
      await Logger.close();

      _logger.info('Main Booth Drive 종료 완료');
    } catch (e) {
      _logger.error('종료 실패', e);
    }
  }
}
