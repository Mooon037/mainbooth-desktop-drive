/// Main Booth Drive 설정
/// 데스크탑 드라이브의 기본 설정 및 경로 관리

import 'dart:io';

class DriveConfig {
  // 드라이브 기본 정보
  static const String driveName = 'Main Booth Drive';
  static const String driveIdentifier = 'com.mainbooth.drive';
  static const String version = '1.0.0';

  // 드라이브 루트 경로
  static String get driveRootPath {
    if (Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Main Booth Drive';
    } else if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE']}\\Main Booth Drive';
    } else {
      return '${Platform.environment['HOME']}/Main Booth Drive';
    }
  }

  // 캐시 경로
  static String get cachePath {
    if (Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Library/Caches/$driveIdentifier';
    } else if (Platform.isWindows) {
      return '${Platform.environment['LOCALAPPDATA']}\\$driveIdentifier\\Cache';
    } else {
      return '${Platform.environment['HOME']}/.cache/$driveIdentifier';
    }
  }

  // 설정 파일 경로
  static String get configPath {
    if (Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Library/Application Support/$driveIdentifier';
    } else if (Platform.isWindows) {
      return '${Platform.environment['APPDATA']}\\$driveIdentifier';
    } else {
      return '${Platform.environment['HOME']}/.config/$driveIdentifier';
    }
  }

  // 로그 파일 경로
  static String get logPath {
    return '$configPath/logs';
  }

  // 데이터베이스 경로 (로컬 SQLite)
  static String get databasePath {
    return '$configPath/drive.db';
  }

  // 드라이브 구조
  static const List<String> projectFolders = [
    'Tracks',
    'References',
    'WorkRequests',
  ];

  // 파일 시스템 감시 설정
  static const Duration watcherDebounce = Duration(milliseconds: 500);
  static const List<String> ignoredPatterns = [
    '.DS_Store',
    'Thumbs.db',
    '*.tmp',
    '~*',
    '.metadata.json',
  ];

  // 동기화 우선순위
  static const Map<String, int> syncPriority = {
    'Tracks': 1,
    'WorkRequests': 2,
    'References': 3,
  };

  // 아이콘 경로 (macOS Finder / Windows Explorer)
  static const Map<String, String> folderIcons = {
    'Projects': 'folder-music',
    'Tracks': 'folder-audio',
    'References': 'folder-star',
    'WorkRequests': 'folder-document',
  };

  // 파일 상태 배지
  static const Map<String, String> statusBadges = {
    'pending': '☁️',
    'synced': '✅',
    'syncing': '🔄',
    'error': '⚠️',
    'conflict': '⚠️',
    'uploading': '⬆️',
    'downloading': '⬇️',
  };

  // 지원 파일 확장자
  static const List<String> supportedAudioFormats = [
    '.wav',
    '.mp3',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.aiff',
  ];

  static const List<String> supportedImageFormats = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
  ];

  static const List<String> supportedDocumentFormats = [
    '.pdf',
    '.doc',
    '.docx',
    '.txt',
    '.md',
    '.rtf',
  ];

  // 메타데이터 파일명
  static const String metadataFileName = '.metadata.json';
  static const String syncStateFileName = '.syncstate';
  static const String conflictSuffix = '_conflict';
}
