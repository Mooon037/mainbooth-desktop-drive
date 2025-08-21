/// 파일 시스템 감시자
/// 로컬 드라이브의 파일 변경사항을 감지하고 알림

import 'dart:io';
import 'dart:async';
import '../config/drive_config.dart';
import '../utils/logger.dart';

class FileWatcher {
  final Logger _logger = Logger('FileWatcher');
  final Map<String, StreamSubscription<FileSystemEvent>> _watchers = {};
  final Map<String, DateTime> _lastEventTime = {};

  bool _isRunning = false;
  Function(FileSystemEvent)? _onFileChanged;

  /// 파일 감시 시작
  void start(String rootPath, Function(FileSystemEvent) onFileChanged) {
    if (_isRunning) return;

    _logger.info('파일 감시자 시작: $rootPath');
    _isRunning = true;
    _onFileChanged = onFileChanged;

    _watchDirectory(rootPath);
  }

  /// 파일 감시 중지
  void stop() {
    if (!_isRunning) return;

    _logger.info('파일 감시자 중지');
    _isRunning = false;

    for (var watcher in _watchers.values) {
      watcher.cancel();
    }
    _watchers.clear();
    _lastEventTime.clear();
  }

  /// 디렉토리 감시
  void _watchDirectory(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return;

    // 이미 감시 중인 경우 스킵
    if (_watchers.containsKey(path)) return;

    try {
      final stream = dir.watch(recursive: true);
      _watchers[path] = stream.listen(
        _handleFileSystemEvent,
        onError: (error) {
          _logger.error('파일 감시 오류 ($path): $error');
        },
      );

      _logger.debug('디렉토리 감시 시작: $path');
    } catch (e) {
      _logger.error('디렉토리 감시 실패: $e');
    }
  }

  /// 파일 시스템 이벤트 처리
  void _handleFileSystemEvent(FileSystemEvent event) {
    // 디바운싱: 짧은 시간 내 중복 이벤트 무시
    final now = DateTime.now();
    final lastTime = _lastEventTime[event.path];

    if (lastTime != null &&
        now.difference(lastTime) < DriveConfig.watcherDebounce) {
      return;
    }

    _lastEventTime[event.path] = now;

    // 무시할 파일 패턴 확인
    if (_shouldIgnoreFile(event.path)) {
      return;
    }

    // 이벤트 타입별 로깅
    String eventType = '';
    if (event is FileSystemCreateEvent) {
      eventType = 'CREATE';
    } else if (event is FileSystemModifyEvent) {
      eventType = 'MODIFY';
    } else if (event is FileSystemDeleteEvent) {
      eventType = 'DELETE';
    } else if (event is FileSystemMoveEvent) {
      eventType = 'MOVE';
    }

    _logger.debug('파일 이벤트: $eventType - ${event.path}');

    // 콜백 호출
    _onFileChanged?.call(event);
  }

  /// 파일 무시 여부 확인
  bool _shouldIgnoreFile(String path) {
    final fileName = path.split(Platform.pathSeparator).last;

    for (var pattern in DriveConfig.ignoredPatterns) {
      if (pattern.contains('*')) {
        // 와일드카드 패턴 처리
        final regex = pattern
            .replaceAll('.', r'\.')
            .replaceAll('*', '.*')
            .replaceAll('?', '.');
        if (RegExp(regex).hasMatch(fileName)) {
          return true;
        }
      } else if (fileName == pattern) {
        return true;
      }
    }

    // 메타데이터 파일 무시
    if (fileName.endsWith('.metadata') || fileName.endsWith('.syncstate')) {
      return true;
    }

    // 임시 파일 무시
    if (fileName.startsWith('~') ||
        fileName.startsWith('.') ||
        fileName.endsWith('.tmp')) {
      return true;
    }

    return false;
  }

  /// 특정 경로 감시 추가
  void addPath(String path) {
    if (!_isRunning) return;
    _watchDirectory(path);
  }

  /// 특정 경로 감시 제거
  void removePath(String path) {
    final watcher = _watchers[path];
    if (watcher != null) {
      watcher.cancel();
      _watchers.remove(path);
      _logger.debug('디렉토리 감시 중지: $path');
    }
  }

  /// 감시 중인 경로 목록
  List<String> get watchedPaths => _watchers.keys.toList();

  /// 감시 중인지 확인
  bool isWatching(String path) => _watchers.containsKey(path);
}
