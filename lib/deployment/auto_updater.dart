/// 자동 업데이트 시스템
/// 앱 버전 체크, 자동 다운로드, 설치 관리

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../utils/logger.dart';

class AutoUpdater {
  static AutoUpdater? _instance;
  static AutoUpdater get instance => _instance ??= AutoUpdater._();

  final Logger _logger = Logger('AutoUpdater');

  // 업데이트 설정
  String updateServerUrl = 'https://api.mainbooth.com/updates';
  String currentVersion = '1.0.0';
  Duration checkInterval = Duration(hours: 24);
  bool autoDownload = true;
  bool autoInstall = false; // 사용자 승인 필요

  // 상태 관리
  UpdateInfo? _latestUpdate;
  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  // 콜백
  Function(UpdateInfo)? onUpdateAvailable;
  Function(double)? onDownloadProgress;
  Function(UpdateInfo)? onUpdateReady;
  Function(String)? onError;

  AutoUpdater._();

  /// 초기화 및 주기적 체크 시작
  void initialize({
    required String updateServerUrl,
    required String currentVersion,
    Duration? checkInterval,
    bool? autoDownload,
    bool? autoInstall,
  }) {
    this.updateServerUrl = updateServerUrl;
    this.currentVersion = currentVersion;
    this.checkInterval = checkInterval ?? this.checkInterval;
    this.autoDownload = autoDownload ?? this.autoDownload;
    this.autoInstall = autoInstall ?? this.autoInstall;

    _logger.info('자동 업데이터 초기화: v$currentVersion');

    // 시작 시 한 번 체크
    checkForUpdates();

    // 주기적 체크 설정
    _startPeriodicCheck();
  }

  /// 수동 업데이트 체크
  Future<UpdateInfo?> checkForUpdates() async {
    if (_isChecking) {
      _logger.debug('이미 업데이트 체크 중');
      return null;
    }

    _isChecking = true;

    try {
      _logger.info('업데이트 체크 시작');

      final response = await http.get(
        Uri.parse('$updateServerUrl/check'),
        headers: {
          'User-Agent': 'MainBoothDrive/$currentVersion',
          'X-Platform': Platform.operatingSystem,
          'X-Architecture': _getArchitecture(),
          'X-Current-Version': currentVersion,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('업데이트 서버 응답 오류: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final updateInfo = UpdateInfo.fromJson(data);

      if (_isNewVersionAvailable(updateInfo.version)) {
        _logger.info('새로운 업데이트 발견: v${updateInfo.version}');
        _latestUpdate = updateInfo;

        onUpdateAvailable?.call(updateInfo);

        if (autoDownload) {
          await downloadUpdate(updateInfo);
        }

        return updateInfo;
      } else {
        _logger.debug('최신 버전 사용 중');
        return null;
      }
    } catch (e) {
      _logger.error('업데이트 체크 실패: $e');
      onError?.call('업데이트 체크 실패: $e');
      return null;
    } finally {
      _isChecking = false;
    }
  }

  /// 업데이트 다운로드
  Future<bool> downloadUpdate(UpdateInfo updateInfo) async {
    if (_isDownloading) {
      _logger.debug('이미 다운로드 중');
      return false;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;

    try {
      _logger.info('업데이트 다운로드 시작: v${updateInfo.version}');

      final downloadUrl = _getDownloadUrl(updateInfo);
      final tempFile = await _createTempFile(updateInfo);

      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception('다운로드 실패: ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;

      final sink = tempFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        if (totalBytes > 0) {
          _downloadProgress = downloadedBytes / totalBytes;
          onDownloadProgress?.call(_downloadProgress);
        }
      }

      await sink.close();

      // 파일 무결성 검증
      if (!await _verifyDownload(tempFile, updateInfo)) {
        await tempFile.delete();
        throw Exception('다운로드 파일 무결성 검증 실패');
      }

      // 다운로드 완료
      updateInfo.localPath = tempFile.path;
      _logger.info('업데이트 다운로드 완료: ${tempFile.path}');

      onUpdateReady?.call(updateInfo);

      if (autoInstall) {
        await installUpdate(updateInfo);
      }

      return true;
    } catch (e) {
      _logger.error('업데이트 다운로드 실패: $e');
      onError?.call('업데이트 다운로드 실패: $e');
      return false;
    } finally {
      _isDownloading = false;
    }
  }

  /// 업데이트 설치
  Future<bool> installUpdate(UpdateInfo updateInfo) async {
    if (updateInfo.localPath == null ||
        !await File(updateInfo.localPath!).exists()) {
      _logger.error('설치할 업데이트 파일을 찾을 수 없음');
      return false;
    }

    try {
      _logger.info('업데이트 설치 시작: v${updateInfo.version}');

      if (Platform.isMacOS) {
        return await _installMacOSUpdate(updateInfo);
      } else if (Platform.isWindows) {
        return await _installWindowsUpdate(updateInfo);
      } else {
        throw UnsupportedError('지원하지 않는 플랫폼');
      }
    } catch (e) {
      _logger.error('업데이트 설치 실패: $e');
      onError?.call('업데이트 설치 실패: $e');
      return false;
    }
  }

  /// 업데이트 연기
  void postponeUpdate(UpdateInfo updateInfo, Duration delay) {
    _logger.info('업데이트 연기: ${delay.inHours}시간');

    Future.delayed(delay, () {
      onUpdateAvailable?.call(updateInfo);
    });
  }

  /// 업데이트 거부 (이 버전 건너뛰기)
  void skipUpdate(UpdateInfo updateInfo) {
    _logger.info('업데이트 건너뛰기: v${updateInfo.version}');
    _saveSkippedVersion(updateInfo.version);
  }

  /// 현재 상태 조회
  UpdaterStatus getStatus() {
    return UpdaterStatus(
      isChecking: _isChecking,
      isDownloading: _isDownloading,
      downloadProgress: _downloadProgress,
      latestUpdate: _latestUpdate,
      currentVersion: currentVersion,
    );
  }

  // 내부 메서드들

  void _startPeriodicCheck() {
    Stream.periodic(checkInterval).listen((_) {
      checkForUpdates();
    });
  }

  bool _isNewVersionAvailable(String latestVersion) {
    final current = _parseVersion(currentVersion);
    final latest = _parseVersion(latestVersion);

    for (int i = 0; i < 3; i++) {
      if (latest[i] > current[i]) {
        return true;
      } else if (latest[i] < current[i]) {
        return false;
      }
    }

    return false;
  }

  List<int> _parseVersion(String version) {
    return version.split('.').map(int.parse).toList();
  }

  String _getArchitecture() {
    if (Platform.isWindows) {
      return Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'x64';
    } else if (Platform.isMacOS) {
      return 'universal'; // Universal binary
    } else {
      return 'unknown';
    }
  }

  String _getDownloadUrl(UpdateInfo updateInfo) {
    final platform = Platform.operatingSystem;
    final architecture = _getArchitecture();

    return updateInfo.downloadUrls['$platform-$architecture'] ??
        updateInfo.downloadUrls[platform] ??
        updateInfo.downloadUrls['default']!;
  }

  Future<File> _createTempFile(UpdateInfo updateInfo) async {
    final tempDir = Directory.systemTemp;
    final fileName =
        'MainBoothDrive_v${updateInfo.version}_${Platform.operatingSystem}';
    final extension =
        Platform.isWindows ? '.exe' : (Platform.isMacOS ? '.dmg' : '');

    return File('${tempDir.path}/$fileName$extension');
  }

  Future<bool> _verifyDownload(File file, UpdateInfo updateInfo) async {
    if (updateInfo.sha256Hash == null) {
      _logger.warning('해시값이 제공되지 않아 무결성 검증을 건너뜀');
      return true;
    }

    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();

    return hash == updateInfo.sha256Hash;
  }

  Future<bool> _installMacOSUpdate(UpdateInfo updateInfo) async {
    final dmgPath = updateInfo.localPath!;

    // DMG 마운트
    final mountResult =
        await Process.run('hdiutil', ['attach', dmgPath, '-nobrowse']);
    if (mountResult.exitCode != 0) {
      throw Exception('DMG 마운트 실패');
    }

    try {
      // 마운트된 경로에서 앱 찾기
      final mountPath = _extractMountPath(mountResult.stdout);
      final appPath = await _findAppInMount(mountPath);

      if (appPath == null) {
        throw Exception('업데이트 앱을 찾을 수 없음');
      }

      // 현재 앱 경로
      final currentAppPath = Platform.resolvedExecutable
          .replaceAll(RegExp(r'/Contents/MacOS/.*'), '');

      // 백업 생성
      final backupPath = '$currentAppPath.backup';
      await Process.run('mv', [currentAppPath, backupPath]);

      // 새 앱 복사
      await Process.run('cp', ['-R', appPath, currentAppPath]);

      // 권한 설정
      await Process.run('chmod', ['+x', '$currentAppPath/Contents/MacOS/*']);

      _logger.info('macOS 앱 업데이트 완료');

      // 재시작 예약
      _scheduleRestart();

      return true;
    } finally {
      // DMG 언마운트
      await Process.run(
          'hdiutil', ['detach', _extractMountPath(mountResult.stdout)]);
    }
  }

  Future<bool> _installWindowsUpdate(UpdateInfo updateInfo) async {
    final installerPath = updateInfo.localPath!;

    // 설치 프로그램 실행 (관리자 권한)
    final result = await Process.run('powershell', [
      'Start-Process',
      '-FilePath', '"$installerPath"',
      '-ArgumentList', '"/S"', // 무음 설치
      '-Verb', 'RunAs',
      '-Wait',
    ]);

    if (result.exitCode != 0) {
      throw Exception('Windows 업데이트 설치 실패');
    }

    _logger.info('Windows 앱 업데이트 완료');

    // 재시작 예약
    _scheduleRestart();

    return true;
  }

  String _extractMountPath(String output) {
    final lines = output.split('\n');
    for (final line in lines) {
      if (line.contains('/Volumes/')) {
        return line.split('\t').last.trim();
      }
    }
    throw Exception('마운트 경로를 찾을 수 없음');
  }

  Future<String?> _findAppInMount(String mountPath) async {
    final dir = Directory(mountPath);
    await for (final entity in dir.list()) {
      if (entity is Directory && entity.path.endsWith('.app')) {
        return entity.path;
      }
    }
    return null;
  }

  void _scheduleRestart() {
    _logger.info('앱 재시작 예약');

    Future.delayed(Duration(seconds: 3), () {
      if (Platform.isMacOS) {
        Process.run('open', [Platform.resolvedExecutable]);
      } else if (Platform.isWindows) {
        Process.run(Platform.resolvedExecutable, []);
      }

      exit(0);
    });
  }

  void _saveSkippedVersion(String version) {
    // 건너뛴 버전을 로컬 설정에 저장
    // 실제 구현에서는 SharedPreferences 등 사용
  }
}

class UpdateInfo {
  final String version;
  final String releaseNotes;
  final DateTime releaseDate;
  final Map<String, String> downloadUrls;
  final String? sha256Hash;
  final bool isRequired;
  final int fileSize;
  String? localPath;

  UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.releaseDate,
    required this.downloadUrls,
    this.sha256Hash,
    required this.isRequired,
    required this.fileSize,
    this.localPath,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'],
      releaseNotes: json['releaseNotes'],
      releaseDate: DateTime.parse(json['releaseDate']),
      downloadUrls: Map<String, String>.from(json['downloadUrls']),
      sha256Hash: json['sha256Hash'],
      isRequired: json['isRequired'] ?? false,
      fileSize: json['fileSize'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'releaseNotes': releaseNotes,
      'releaseDate': releaseDate.toIso8601String(),
      'downloadUrls': downloadUrls,
      'sha256Hash': sha256Hash,
      'isRequired': isRequired,
      'fileSize': fileSize,
      'localPath': localPath,
    };
  }
}

class UpdaterStatus {
  final bool isChecking;
  final bool isDownloading;
  final double downloadProgress;
  final UpdateInfo? latestUpdate;
  final String currentVersion;

  UpdaterStatus({
    required this.isChecking,
    required this.isDownloading,
    required this.downloadProgress,
    this.latestUpdate,
    required this.currentVersion,
  });

  Map<String, dynamic> toJson() {
    return {
      'isChecking': isChecking,
      'isDownloading': isDownloading,
      'downloadProgress': downloadProgress,
      'latestUpdate': latestUpdate?.toJson(),
      'currentVersion': currentVersion,
    };
  }
}
