/// 로깅 유틸리티
/// 앱 전반의 로그를 관리

import 'dart:io';
import '../config/drive_config.dart';

class Logger {
  final String name;
  static LogLevel _globalLevel = LogLevel.info;
  static final Map<String, Logger> _loggers = {};
  static File? _logFile;
  static IOSink? _logSink;

  Logger(this.name);

  factory Logger.getLogger(String name) {
    return _loggers.putIfAbsent(name, () => Logger(name));
  }

  static Future<void> initialize({
    LogLevel level = LogLevel.info,
    bool enableFileLogging = true,
  }) async {
    _globalLevel = level;

    if (enableFileLogging) {
      await _initializeFileLogging();
    }
  }

  static Future<void> _initializeFileLogging() async {
    try {
      final logDir = Directory(DriveConfig.logPath);
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final logPath = '${DriveConfig.logPath}/mainbooth_drive_$timestamp.log';

      _logFile = File(logPath);
      _logSink = _logFile!.openWrite(mode: FileMode.append);

      print('로그 파일 초기화: $logPath');
    } catch (e) {
      print('로그 파일 초기화 실패: $e');
    }
  }

  static Future<void> close() async {
    await _logSink?.flush();
    await _logSink?.close();
  }

  void debug(String message) {
    _log(LogLevel.debug, message);
  }

  void info(String message) {
    _log(LogLevel.info, message);
  }

  void warning(String message) {
    _log(LogLevel.warning, message);
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message);
    if (error != null) {
      _log(LogLevel.error, 'Error: $error');
    }
    if (stackTrace != null) {
      _log(LogLevel.error, 'StackTrace: $stackTrace');
    }
  }

  void _log(LogLevel level, String message) {
    if (level.index < _globalLevel.index) return;

    final timestamp = DateTime.now().toIso8601String();
    final levelStr = level.toString().split('.').last.toUpperCase().padRight(7);
    final nameStr = name.padRight(20);
    final logMessage = '$timestamp [$levelStr] [$nameStr] $message';

    // 콘솔 출력
    switch (level) {
      case LogLevel.debug:
        print('\x1B[36m$logMessage\x1B[0m'); // Cyan
        break;
      case LogLevel.info:
        print('\x1B[32m$logMessage\x1B[0m'); // Green
        break;
      case LogLevel.warning:
        print('\x1B[33m$logMessage\x1B[0m'); // Yellow
        break;
      case LogLevel.error:
        print('\x1B[31m$logMessage\x1B[0m'); // Red
        break;
    }

    // 파일 출력
    _logSink?.writeln(logMessage);
  }

  /// 최근 로그 조회
  static Future<List<String>> getRecentLogs({int lines = 100}) async {
    if (_logFile == null || !await _logFile!.exists()) {
      return [];
    }

    final allLines = await _logFile!.readAsLines();
    final startIndex = allLines.length > lines ? allLines.length - lines : 0;

    return allLines.sublist(startIndex);
  }

  /// 로그 파일 크기 확인
  static Future<int> getLogFileSize() async {
    if (_logFile == null || !await _logFile!.exists()) {
      return 0;
    }

    return await _logFile!.length();
  }

  /// 오래된 로그 파일 정리
  static Future<void> cleanupOldLogs(
      {Duration retention = const Duration(days: 7)}) async {
    try {
      final logDir = Directory(DriveConfig.logPath);
      if (!await logDir.exists()) return;

      final cutoffDate = DateTime.now().subtract(retention);

      await for (var entity in logDir.list()) {
        if (entity is File && entity.path.endsWith('.log')) {
          final modified = await entity.lastModified();
          if (modified.isBefore(cutoffDate)) {
            await entity.delete();
            print('오래된 로그 파일 삭제: ${entity.path}');
          }
        }
      }
    } catch (e) {
      print('로그 파일 정리 실패: $e');
    }
  }
}

enum LogLevel {
  debug,
  info,
  warning,
  error,
}
