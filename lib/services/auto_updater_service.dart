/// 자동 업데이트 서비스
/// GitHub Releases를 통한 앱 자동 업데이트 관리

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import '../utils/logger.dart';
import '../config/drive_config.dart';

class AutoUpdaterService {
  static AutoUpdaterService? _instance;
  static AutoUpdaterService get instance =>
      _instance ??= AutoUpdaterService._();

  final Logger _logger = Logger('AutoUpdater');
  final Dio _dio = Dio();

  Timer? _updateCheckTimer;
  bool _isCheckingForUpdates = false;
  bool _isUpdateAvailable = false;
  bool _isDownloading = false;
  UpdateInfo? _latestUpdate;

  // 업데이트 관련 이벤트 스트림
  final StreamController<UpdateEvent> _updateEventController =
      StreamController<UpdateEvent>.broadcast();

  Stream<UpdateEvent> get updateEventStream => _updateEventController.stream;

  AutoUpdaterService._();

  /// 자동 업데이트 서비스 초기화
  Future<void> initialize({
    Duration checkInterval = const Duration(hours: 24),
    bool autoDownload = false,
    bool autoInstall = false,
  }) async {
    try {
      _logger.info('자동 업데이트 서비스 초기화');

      // HTTP 클라이언트 설정
      _dio.options = BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
        headers: {
          'User-Agent': 'MainBoothDrive/${DriveConfig.version}',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      // 정기 업데이트 확인 타이머 시작
      _startUpdateCheckTimer(checkInterval);

      // 초기 업데이트 확인 (앱 시작 후 1분 뒤)
      Timer(const Duration(minutes: 1), () => checkForUpdates());

      _logger.info('자동 업데이트 서비스 초기화 완료');
    } catch (e) {
      _logger.error('자동 업데이트 서비스 초기화 실패', e);
    }
  }

  /// 업데이트 확인
  Future<UpdateInfo?> checkForUpdates() async {
    if (_isCheckingForUpdates) {
      _logger.debug('이미 업데이트 확인 중');
      return null;
    }

    _isCheckingForUpdates = true;
    _updateEventController.add(UpdateEvent(UpdateEventType.checkingForUpdates));

    try {
      _logger.info('업데이트 확인 시작');

      // GitHub API에서 최신 릴리스 정보 가져오기
      final response = await _dio.get(
          'https://api.github.com/repos/mainbooth/desktop-drive/releases/latest');

      if (response.statusCode == 200) {
        final releaseData = response.data;
        final latestVersion = releaseData['tag_name'] as String;
        final currentVersion = 'v${DriveConfig.version}';

        _logger.info('현재 버전: $currentVersion, 최신 버전: $latestVersion');

        if (_isNewerVersion(latestVersion, currentVersion)) {
          _latestUpdate = UpdateInfo.fromGitHubRelease(releaseData);
          _isUpdateAvailable = true;

          _updateEventController.add(UpdateEvent(
            UpdateEventType.updateAvailable,
            updateInfo: _latestUpdate,
          ));

          _logger.info('새 업데이트 사용 가능: ${_latestUpdate!.version}');
          return _latestUpdate;
        } else {
          _isUpdateAvailable = false;
          _updateEventController
              .add(UpdateEvent(UpdateEventType.noUpdateAvailable));
          _logger.info('최신 버전을 사용 중입니다');
        }
      }
    } catch (e) {
      _logger.error('업데이트 확인 실패', e);
      _updateEventController.add(UpdateEvent(
        UpdateEventType.error,
        error: e.toString(),
      ));
    } finally {
      _isCheckingForUpdates = false;
    }

    return null;
  }

  /// 업데이트 다운로드
  Future<String?> downloadUpdate(UpdateInfo updateInfo) async {
    if (_isDownloading) {
      _logger.warning('이미 다운로드 중');
      return null;
    }

    _isDownloading = true;

    try {
      _logger.info('업데이트 다운로드 시작: ${updateInfo.version}');

      final downloadUrl = updateInfo.downloadUrl;
      final fileName = updateInfo.fileName;
      final downloadPath = '${DriveConfig.cachePath}/updates/$fileName';

      // 다운로드 디렉토리 생성
      final downloadDir = Directory('${DriveConfig.cachePath}/updates');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      _updateEventController.add(UpdateEvent(
        UpdateEventType.downloadStarted,
        updateInfo: updateInfo,
      ));

      // 파일 다운로드 (진행률 포함)
      await _dio.download(
        downloadUrl,
        downloadPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            _updateEventController.add(UpdateEvent(
              UpdateEventType.downloadProgress,
              updateInfo: updateInfo,
              progress: progress,
            ));
          }
        },
      );

      // 파일 무결성 검증
      if (updateInfo.sha256 != null) {
        final isValid =
            await _verifyFileIntegrity(downloadPath, updateInfo.sha256!);
        if (!isValid) {
          throw Exception('다운로드된 파일의 무결성 검증 실패');
        }
      }

      _updateEventController.add(UpdateEvent(
        UpdateEventType.downloadCompleted,
        updateInfo: updateInfo,
        downloadPath: downloadPath,
      ));

      _logger.info('업데이트 다운로드 완료: $downloadPath');
      return downloadPath;
    } catch (e) {
      _logger.error('업데이트 다운로드 실패', e);
      _updateEventController.add(UpdateEvent(
        UpdateEventType.error,
        error: e.toString(),
      ));
      return null;
    } finally {
      _isDownloading = false;
    }
  }

  /// 업데이트 설치
  Future<bool> installUpdate(String updatePath) async {
    try {
      _logger.info('업데이트 설치 시작: $updatePath');

      _updateEventController.add(UpdateEvent(UpdateEventType.installStarted));

      if (Platform.isMacOS) {
        return await _installMacOSUpdate(updatePath);
      } else if (Platform.isWindows) {
        return await _installWindowsUpdate(updatePath);
      } else if (Platform.isLinux) {
        return await _installLinuxUpdate(updatePath);
      } else {
        throw UnsupportedError('지원되지 않는 플랫폼');
      }
    } catch (e) {
      _logger.error('업데이트 설치 실패', e);
      _updateEventController.add(UpdateEvent(
        UpdateEventType.error,
        error: e.toString(),
      ));
      return false;
    }
  }

  /// macOS 업데이트 설치
  Future<bool> _installMacOSUpdate(String dmgPath) async {
    try {
      // DMG 마운트
      final result = await Process.run('hdiutil', ['attach', dmgPath]);
      if (result.exitCode != 0) {
        throw Exception('DMG 마운트 실패: ${result.stderr}');
      }

      // 마운트된 볼륨에서 앱 찾기
      final volumePath = _extractMountPath(result.stdout);
      final appPath = '$volumePath/mainbooth_drive.app';

      if (!await Directory(appPath).exists()) {
        throw Exception('앱 파일을 찾을 수 없습니다');
      }

      // 기존 앱 백업
      final currentAppPath = '/Applications/mainbooth_drive.app';
      final backupPath = '/Applications/mainbooth_drive.app.backup';

      if (await Directory(currentAppPath).exists()) {
        await Process.run('mv', [currentAppPath, backupPath]);
      }

      // 새 앱 복사
      final copyResult =
          await Process.run('cp', ['-R', appPath, '/Applications/']);
      if (copyResult.exitCode != 0) {
        // 복사 실패 시 백업 복원
        if (await Directory(backupPath).exists()) {
          await Process.run('mv', [backupPath, currentAppPath]);
        }
        throw Exception('앱 복사 실패: ${copyResult.stderr}');
      }

      // DMG 언마운트
      await Process.run('hdiutil', ['detach', volumePath]);

      // 백업 파일 삭제
      if (await Directory(backupPath).exists()) {
        await Directory(backupPath).delete(recursive: true);
      }

      _updateEventController.add(UpdateEvent(UpdateEventType.installCompleted));
      return true;
    } catch (e) {
      _logger.error('macOS 업데이트 설치 실패', e);
      return false;
    }
  }

  /// Windows 업데이트 설치
  Future<bool> _installWindowsUpdate(String installerPath) async {
    try {
      // 관리자 권한으로 설치 프로그램 실행
      final result = await Process.run(
        'powershell',
        [
          '-Command',
          'Start-Process -FilePath "$installerPath" -Verb RunAs -Wait'
        ],
      );

      if (result.exitCode == 0) {
        _updateEventController
            .add(UpdateEvent(UpdateEventType.installCompleted));
        return true;
      } else {
        throw Exception('설치 프로그램 실행 실패: ${result.stderr}');
      }
    } catch (e) {
      _logger.error('Windows 업데이트 설치 실패', e);
      return false;
    }
  }

  /// Linux 업데이트 설치
  Future<bool> _installLinuxUpdate(String appImagePath) async {
    try {
      // 현재 실행 파일 경로 확인
      final currentExePath = Platform.resolvedExecutable;
      final backupPath = '$currentExePath.backup';

      // 기존 파일 백업
      if (await File(currentExePath).exists()) {
        await File(currentExePath).copy(backupPath);
      }

      // 새 AppImage 복사
      await File(appImagePath).copy(currentExePath);

      // 실행 권한 부여
      await Process.run('chmod', ['+x', currentExePath]);

      // 백업 파일 삭제
      if (await File(backupPath).exists()) {
        await File(backupPath).delete();
      }

      _updateEventController.add(UpdateEvent(UpdateEventType.installCompleted));
      return true;
    } catch (e) {
      _logger.error('Linux 업데이트 설치 실패', e);
      return false;
    }
  }

  /// 앱 재시작
  Future<void> restartApp() async {
    try {
      _logger.info('앱 재시작 중...');

      _updateEventController.add(UpdateEvent(UpdateEventType.restartRequired));

      if (Platform.isMacOS) {
        await Process.start('open', ['/Applications/mainbooth_drive.app']);
      } else if (Platform.isWindows) {
        await Process.start(Platform.resolvedExecutable, []);
      } else if (Platform.isLinux) {
        await Process.start(Platform.resolvedExecutable, []);
      }

      // 현재 앱 종료
      exit(0);
    } catch (e) {
      _logger.error('앱 재시작 실패', e);
    }
  }

  /// 버전 비교
  bool _isNewerVersion(String latestVersion, String currentVersion) {
    // v1.2.3 형태의 버전을 1.2.3으로 변환
    final latest = latestVersion.replaceFirst('v', '');
    final current = currentVersion.replaceFirst('v', '');

    final latestParts = latest.split('.').map(int.parse).toList();
    final currentParts = current.split('.').map(int.parse).toList();

    // 버전 파트 길이 맞추기
    while (latestParts.length < 3) latestParts.add(0);
    while (currentParts.length < 3) currentParts.add(0);

    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) {
        return true;
      } else if (latestParts[i] < currentParts[i]) {
        return false;
      }
    }

    return false; // 동일한 버전
  }

  /// 파일 무결성 검증
  Future<bool> _verifyFileIntegrity(
      String filePath, String expectedSha256) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString() == expectedSha256.toLowerCase();
    } catch (e) {
      _logger.error('파일 무결성 검증 실패', e);
      return false;
    }
  }

  /// DMG 마운트 경로 추출
  String _extractMountPath(String hdiutilOutput) {
    final lines = hdiutilOutput.split('\n');
    for (final line in lines) {
      if (line.contains('/Volumes/')) {
        final parts = line.split('\t');
        for (final part in parts) {
          if (part.trim().startsWith('/Volumes/')) {
            return part.trim();
          }
        }
      }
    }
    throw Exception('마운트 경로를 찾을 수 없습니다');
  }

  /// 업데이트 확인 타이머 시작
  void _startUpdateCheckTimer(Duration interval) {
    _updateCheckTimer?.cancel();
    _updateCheckTimer = Timer.periodic(interval, (_) {
      checkForUpdates();
    });
  }

  /// 정리
  void dispose() {
    _updateCheckTimer?.cancel();
    _updateEventController.close();
  }

  // Getters
  bool get isUpdateAvailable => _isUpdateAvailable;
  bool get isCheckingForUpdates => _isCheckingForUpdates;
  bool get isDownloading => _isDownloading;
  UpdateInfo? get latestUpdate => _latestUpdate;
}

/// 업데이트 정보
class UpdateInfo {
  final String version;
  final String title;
  final String description;
  final String downloadUrl;
  final String fileName;
  final int fileSize;
  final String? sha256;
  final DateTime publishedAt;

  UpdateInfo({
    required this.version,
    required this.title,
    required this.description,
    required this.downloadUrl,
    required this.fileName,
    required this.fileSize,
    this.sha256,
    required this.publishedAt,
  });

  factory UpdateInfo.fromGitHubRelease(Map<String, dynamic> releaseData) {
    final version = releaseData['tag_name'] as String;
    final title = releaseData['name'] as String;
    final description = releaseData['body'] as String? ?? '';
    final publishedAt = DateTime.parse(releaseData['published_at']);

    // 현재 플랫폼에 맞는 에셋 찾기
    final assets = releaseData['assets'] as List;
    Map<String, dynamic>? targetAsset;

    if (Platform.isMacOS) {
      targetAsset = assets.firstWhere(
        (asset) => asset['name'].toString().contains('-mac.dmg'),
        orElse: () => null,
      );
    } else if (Platform.isWindows) {
      targetAsset = assets.firstWhere(
        (asset) => asset['name'].toString().contains('-windows.exe'),
        orElse: () => null,
      );
    } else if (Platform.isLinux) {
      targetAsset = assets.firstWhere(
        (asset) => asset['name'].toString().contains('-linux.AppImage'),
        orElse: () => null,
      );
    }

    if (targetAsset == null) {
      throw Exception('현재 플랫폼에 맞는 업데이트 파일을 찾을 수 없습니다');
    }

    return UpdateInfo(
      version: version,
      title: title,
      description: description,
      downloadUrl: targetAsset['browser_download_url'],
      fileName: targetAsset['name'],
      fileSize: targetAsset['size'],
      publishedAt: publishedAt,
    );
  }

  String get formattedFileSize {
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}

/// 업데이트 이벤트
class UpdateEvent {
  final UpdateEventType type;
  final UpdateInfo? updateInfo;
  final double? progress;
  final String? downloadPath;
  final String? error;

  UpdateEvent(
    this.type, {
    this.updateInfo,
    this.progress,
    this.downloadPath,
    this.error,
  });
}

/// 업데이트 이벤트 타입
enum UpdateEventType {
  checkingForUpdates,
  updateAvailable,
  noUpdateAvailable,
  downloadStarted,
  downloadProgress,
  downloadCompleted,
  installStarted,
  installCompleted,
  restartRequired,
  error,
}
