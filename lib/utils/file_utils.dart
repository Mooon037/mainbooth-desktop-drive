/// 파일 유틸리티
/// 파일 처리 관련 헬퍼 함수들

import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../config/drive_config.dart';

class FileUtils {
  /// 파일 해시 계산 (SHA-256)
  static Future<String> calculateFileHash(File file) async {
    if (!await file.exists()) {
      throw Exception('파일이 존재하지 않습니다: ${file.path}');
    }

    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 파일 크기를 읽기 쉬운 형식으로 변환
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 파일 확장자 추출
  static String getFileExtension(String filePath) {
    final parts = filePath.split('.');
    if (parts.length > 1) {
      return '.${parts.last.toLowerCase()}';
    }
    return '';
  }

  /// 파일 이름 추출 (확장자 제외)
  static String getFileNameWithoutExtension(String filePath) {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final parts = fileName.split('.');
    if (parts.length > 1) {
      parts.removeLast();
      return parts.join('.');
    }
    return fileName;
  }

  /// 파일이 지원되는 오디오 형식인지 확인
  static bool isSupportedAudioFormat(String filePath) {
    final extension = getFileExtension(filePath);
    return DriveConfig.supportedAudioFormats.contains(extension);
  }

  /// 파일이 지원되는 이미지 형식인지 확인
  static bool isSupportedImageFormat(String filePath) {
    final extension = getFileExtension(filePath);
    return DriveConfig.supportedImageFormats.contains(extension);
  }

  /// 파일이 지원되는 문서 형식인지 확인
  static bool isSupportedDocumentFormat(String filePath) {
    final extension = getFileExtension(filePath);
    return DriveConfig.supportedDocumentFormats.contains(extension);
  }

  /// 안전한 파일 이름 생성 (특수문자 제거)
  static String sanitizeFileName(String fileName) {
    // 파일 시스템에서 문제가 될 수 있는 문자 제거
    final invalidChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
    var sanitized = fileName.replaceAll(invalidChars, '_');

    // 연속된 공백을 하나로
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ');

    // 앞뒤 공백 제거
    sanitized = sanitized.trim();

    // 빈 문자열인 경우
    if (sanitized.isEmpty) {
      sanitized = 'untitled';
    }

    // 예약된 파일명 처리 (Windows)
    final reserved = ['CON', 'PRN', 'AUX', 'NUL', 'COM1', 'LPT1'];
    if (reserved.contains(sanitized.toUpperCase())) {
      sanitized = '${sanitized}_file';
    }

    return sanitized;
  }

  /// 디렉토리 크기 계산
  static Future<int> getDirectorySize(Directory dir) async {
    int totalSize = 0;

    if (!await dir.exists()) {
      return totalSize;
    }

    await for (var entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }

    return totalSize;
  }

  /// 캐시 크기 확인
  static Future<int> getCacheSize() async {
    final cacheDir = Directory(DriveConfig.cachePath);
    return await getDirectorySize(cacheDir);
  }

  /// 캐시 정리
  static Future<void> clearCache({
    Duration? olderThan,
    int? maxSize,
  }) async {
    final cacheDir = Directory(DriveConfig.cachePath);
    if (!await cacheDir.exists()) return;

    final cutoffDate =
        olderThan != null ? DateTime.now().subtract(olderThan) : null;

    final files = <FileSystemEntity>[];
    await for (var entity in cacheDir.list(recursive: true)) {
      if (entity is File) {
        files.add(entity);
      }
    }

    // 수정 시간 기준으로 정렬 (오래된 것부터)
    files.sort((a, b) {
      final aTime = (a as File).lastModifiedSync();
      final bTime = (b as File).lastModifiedSync();
      return aTime.compareTo(bTime);
    });

    int totalSize = await getCacheSize();

    for (var entity in files) {
      if (entity is File) {
        bool shouldDelete = false;

        // 날짜 기준 삭제
        if (cutoffDate != null) {
          final modified = await entity.lastModified();
          shouldDelete = modified.isBefore(cutoffDate);
        }

        // 크기 기준 삭제
        if (maxSize != null && totalSize > maxSize) {
          shouldDelete = true;
        }

        if (shouldDelete) {
          final fileSize = await entity.length();
          await entity.delete();
          totalSize -= fileSize;
        }
      }
    }
  }

  /// 파일 복사 (진행률 콜백 포함)
  static Future<void> copyFileWithProgress(
    File source,
    File destination, {
    void Function(double progress)? onProgress,
  }) async {
    if (!await source.exists()) {
      throw Exception('원본 파일이 존재하지 않습니다: ${source.path}');
    }

    final sourceSize = await source.length();
    if (sourceSize == 0) {
      await destination.writeAsBytes([]);
      onProgress?.call(1.0);
      return;
    }

    // 대상 디렉토리 생성
    final destDir = destination.parent;
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    const bufferSize = 1024 * 1024; // 1MB 버퍼
    final sourceStream = source.openRead();
    final destSink = destination.openWrite();

    int bytesWritten = 0;

    try {
      await for (var chunk in sourceStream) {
        destSink.add(chunk);
        bytesWritten += chunk.length;

        if (onProgress != null) {
          final progress = bytesWritten / sourceSize;
          onProgress(progress.clamp(0.0, 1.0));
        }
      }

      await destSink.flush();
      await destSink.close();

      onProgress?.call(1.0);
    } catch (e) {
      await destSink.close();

      // 실패 시 부분적으로 생성된 파일 삭제
      if (await destination.exists()) {
        await destination.delete();
      }

      rethrow;
    }
  }

  /// 임시 파일 생성
  static Future<File> createTempFile(String prefix, String extension) async {
    final tempDir = await Directory.systemTemp.createTemp('mainbooth_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempPath = '${tempDir.path}/$prefix$timestamp$extension';
    return File(tempPath);
  }

  /// JSON 파일 읽기
  static Future<Map<String, dynamic>?> readJsonFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return null;
      }

      final contents = await file.readAsString();
      return json.decode(contents) as Map<String, dynamic>;
    } catch (e) {
      print('JSON 파일 읽기 실패: $path - $e');
      return null;
    }
  }

  /// JSON 파일 쓰기
  static Future<void> writeJsonFile(
      String path, Map<String, dynamic> data) async {
    final file = File(path);

    // 디렉토리 생성
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    await file.writeAsString(jsonString);
  }

  /// 파일 권한 확인 (읽기/쓰기)
  static Future<FilePermissions> checkFilePermissions(String path) async {
    final file = File(path);
    final exists = await file.exists();

    if (!exists) {
      // 파일이 없으면 부모 디렉토리 권한 확인
      final parent = file.parent;
      return FilePermissions(
        exists: false,
        readable: await _canRead(parent.path),
        writable: await _canWrite(parent.path),
      );
    }

    return FilePermissions(
      exists: true,
      readable: await _canRead(path),
      writable: await _canWrite(path),
    );
  }

  static Future<bool> _canRead(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.open(mode: FileMode.read).then((f) => f.close());
        return true;
      }

      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.list(followLinks: false).first;
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> _canWrite(String path) async {
    try {
      final testFile =
          File('$path/.write_test_${DateTime.now().millisecondsSinceEpoch}');
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// 파일 권한 정보
class FilePermissions {
  final bool exists;
  final bool readable;
  final bool writable;

  FilePermissions({
    required this.exists,
    required this.readable,
    required this.writable,
  });
}
