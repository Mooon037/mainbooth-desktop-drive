/// 충돌 해결 관리자
/// 파일 동기화 시 발생하는 충돌을 감지하고 해결

import 'dart:io';
import '../config/drive_config.dart';
import '../utils/logger.dart';
import '../utils/file_utils.dart';

class ConflictResolver {
  final Logger _logger = Logger('ConflictResolver');

  /// 충돌 감지
  Future<ConflictType?> detectConflict(
    File localFile,
    String remoteHash,
    DateTime remoteModified,
  ) async {
    if (!await localFile.exists()) {
      return null; // 로컬 파일이 없으면 충돌 없음
    }

    // 로컬 파일 해시 계산
    final localHash = await FileUtils.calculateFileHash(localFile);
    final localModified = await localFile.lastModified();

    // 해시가 다르고 수정 시간도 다른 경우
    if (localHash != remoteHash) {
      if (localModified.isAfter(remoteModified)) {
        return ConflictType.localNewer;
      } else if (remoteModified.isAfter(localModified)) {
        return ConflictType.remoteNewer;
      } else {
        return ConflictType.bothModified;
      }
    }

    return null; // 충돌 없음
  }

  /// 충돌 해결
  Future<ConflictResolution> resolveConflict(
    File localFile,
    String remoteUrl,
    ConflictType conflictType, {
    String? userId,
  }) async {
    _logger.warning('충돌 감지: ${localFile.path} - $conflictType');

    switch (conflictType) {
      case ConflictType.localNewer:
        // 로컬이 더 최신인 경우 - 로컬 파일을 업로드
        return ConflictResolution(
          action: ResolutionAction.uploadLocal,
          message: '로컬 파일이 더 최신입니다. 업로드합니다.',
        );

      case ConflictType.remoteNewer:
        // 원격이 더 최신인 경우 - 원격 파일을 다운로드
        return ConflictResolution(
          action: ResolutionAction.downloadRemote,
          message: '원격 파일이 더 최신입니다. 다운로드합니다.',
        );

      case ConflictType.bothModified:
        // 양쪽 모두 수정된 경우 - 충돌 파일 생성
        final conflictPath = await _createConflictFile(localFile, userId);

        return ConflictResolution(
          action: ResolutionAction.createConflict,
          conflictPath: conflictPath,
          message: '양쪽 모두 수정되었습니다. 충돌 파일을 생성했습니다: $conflictPath',
        );
    }
  }

  /// 충돌 파일 생성
  Future<String> _createConflictFile(File originalFile, String? userId) async {
    final dir = originalFile.parent.path;
    final fileName = originalFile.path.split(Platform.pathSeparator).last;
    final nameWithoutExt = fileName.split('.').first;
    final extension = fileName.split('.').last;

    // 충돌 파일명 생성
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final userSuffix = userId ?? 'unknown';
    final conflictName =
        '${nameWithoutExt}${DriveConfig.conflictSuffix}_${userSuffix}_$timestamp.$extension';
    final conflictPath = '$dir${Platform.pathSeparator}$conflictName';

    // 원본 파일을 충돌 파일로 복사
    await originalFile.copy(conflictPath);

    _logger.info('충돌 파일 생성: $conflictPath');
    return conflictPath;
  }

  /// 자동 해결 가능 여부 확인
  bool canAutoResolve(ConflictType conflictType) {
    // 원격이 더 최신인 경우만 자동 해결
    return conflictType == ConflictType.remoteNewer;
  }

  /// 충돌 파일 목록 조회
  Future<List<ConflictFile>> getConflictFiles(String projectPath) async {
    final conflictFiles = <ConflictFile>[];
    final dir = Directory(projectPath);

    if (!await dir.exists()) {
      return conflictFiles;
    }

    await for (var entity in dir.list(recursive: true)) {
      if (entity is File) {
        final path = entity.path;
        if (path.contains(DriveConfig.conflictSuffix)) {
          final fileName = path.split(Platform.pathSeparator).last;
          final parts = fileName.split(DriveConfig.conflictSuffix);

          if (parts.length >= 2) {
            final originalName = parts[0];
            final conflictInfo = parts[1];

            // 충돌 정보 파싱
            final infoParts = conflictInfo.split('_');
            final userId = infoParts.length > 1 ? infoParts[1] : 'unknown';
            final timestamp = infoParts.length > 2 ? infoParts[2] : '';

            conflictFiles.add(ConflictFile(
              path: path,
              originalName: originalName,
              userId: userId,
              timestamp: _parseTimestamp(timestamp),
              size: await entity.length(),
            ));
          }
        }
      }
    }

    return conflictFiles;
  }

  /// 타임스탬프 파싱
  DateTime? _parseTimestamp(String timestamp) {
    try {
      // ISO 8601 형식 복원
      final isoString = timestamp.replaceAll('-', ':');
      return DateTime.parse(isoString);
    } catch (e) {
      return null;
    }
  }

  /// 충돌 파일 정리
  Future<void> cleanupConflictFiles(
    String projectPath, {
    Duration? olderThan,
  }) async {
    final conflictFiles = await getConflictFiles(projectPath);
    final cutoffDate =
        olderThan != null ? DateTime.now().subtract(olderThan) : null;

    for (var conflictFile in conflictFiles) {
      bool shouldDelete = false;

      if (cutoffDate != null && conflictFile.timestamp != null) {
        shouldDelete = conflictFile.timestamp!.isBefore(cutoffDate);
      }

      if (shouldDelete) {
        try {
          final file = File(conflictFile.path);
          if (await file.exists()) {
            await file.delete();
            _logger.info('충돌 파일 삭제: ${conflictFile.path}');
          }
        } catch (e) {
          _logger.error('충돌 파일 삭제 실패: ${conflictFile.path} - $e');
        }
      }
    }
  }
}

/// 충돌 타입
enum ConflictType {
  localNewer, // 로컬이 더 최신
  remoteNewer, // 원격이 더 최신
  bothModified, // 양쪽 모두 수정됨
}

/// 충돌 해결 방법
class ConflictResolution {
  final ResolutionAction action;
  final String message;
  final String? conflictPath;

  ConflictResolution({
    required this.action,
    required this.message,
    this.conflictPath,
  });
}

/// 해결 액션
enum ResolutionAction {
  uploadLocal, // 로컬 파일 업로드
  downloadRemote, // 원격 파일 다운로드
  createConflict, // 충돌 파일 생성
}

/// 충돌 파일 정보
class ConflictFile {
  final String path;
  final String originalName;
  final String userId;
  final DateTime? timestamp;
  final int size;

  ConflictFile({
    required this.path,
    required this.originalName,
    required this.userId,
    this.timestamp,
    required this.size,
  });
}
