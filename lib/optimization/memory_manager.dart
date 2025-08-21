/// 메모리 관리자
/// 캐시 관리, 메모리 사용량 최적화, 가비지 컬렉션 최적화

import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import '../utils/logger.dart';

class MemoryManager {
  static MemoryManager? _instance;
  static MemoryManager get instance => _instance ??= MemoryManager._();

  final Logger _logger = Logger('MemoryManager');

  // 메모리 제한 설정
  int maxMemoryUsage = 200 * 1024 * 1024; // 200MB
  int maxCacheSize = 100 * 1024 * 1024; // 100MB
  int cacheCleanupThreshold = 80; // 80% 사용시 정리

  // 캐시 저장소
  final Map<String, CacheEntry> _memoryCache = {};
  final Map<String, FileInfo> _fileInfoCache = {};

  // 메모리 사용량 추적
  int _currentMemoryUsage = 0;
  int _currentCacheSize = 0;

  // 정리 타이머
  Timer? _cleanupTimer;

  MemoryManager._() {
    _startCleanupTimer();
  }

  /// 메모리 캐시에 데이터 저장
  Future<void> cacheData(String key, Uint8List data, {Duration? ttl}) async {
    final entry = CacheEntry(
      key: key,
      data: data,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      ttl: ttl ?? Duration(hours: 1),
      size: data.length,
    );

    // 메모리 체크
    if (_currentCacheSize + data.length > maxCacheSize) {
      await _evictLeastRecentlyUsed(data.length);
    }

    // 기존 항목 제거
    if (_memoryCache.containsKey(key)) {
      final oldEntry = _memoryCache[key]!;
      _currentCacheSize -= oldEntry.size;
      _currentMemoryUsage -= oldEntry.size;
    }

    _memoryCache[key] = entry;
    _currentCacheSize += data.length;
    _currentMemoryUsage += data.length;

    _logger.debug('캐시 저장: $key (${_formatBytes(data.length)})');
  }

  /// 메모리 캐시에서 데이터 조회
  Uint8List? getCachedData(String key) {
    final entry = _memoryCache[key];
    if (entry == null) {
      return null;
    }

    // TTL 체크
    if (entry.isExpired()) {
      _memoryCache.remove(key);
      _currentCacheSize -= entry.size;
      _currentMemoryUsage -= entry.size;
      _logger.debug('캐시 만료: $key');
      return null;
    }

    // 액세스 시간 업데이트
    entry.lastAccessed = DateTime.now();
    entry.accessCount++;

    _logger.debug('캐시 조회: $key (${_formatBytes(entry.size)})');
    return entry.data;
  }

  /// 파일 정보 캐시
  void cacheFileInfo(String path, FileInfo info) {
    _fileInfoCache[path] = info;

    // 파일 정보 캐시는 크기 제한 (1000개)
    if (_fileInfoCache.length > 1000) {
      final oldestKey = _fileInfoCache.keys.first;
      _fileInfoCache.remove(oldestKey);
    }
  }

  /// 파일 정보 조회
  FileInfo? getFileInfo(String path) {
    return _fileInfoCache[path];
  }

  /// 스마트 프리로딩
  Future<void> preloadFiles(List<String> filePaths) async {
    final availableMemory = maxMemoryUsage - _currentMemoryUsage;
    int usedMemory = 0;

    for (final path in filePaths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;

        final fileSize = await file.length();

        // 사용 가능한 메모리 체크
        if (usedMemory + fileSize > availableMemory) {
          _logger.debug('프리로딩 중단: 메모리 부족');
          break;
        }

        // 작은 파일만 프리로딩 (10MB 이하)
        if (fileSize <= 10 * 1024 * 1024) {
          final data = await file.readAsBytes();
          await cacheData(path, Uint8List.fromList(data));
          usedMemory += fileSize;

          _logger.debug('프리로딩 완료: $path (${_formatBytes(fileSize)})');
        }
      } catch (e) {
        _logger.warning('프리로딩 실패: $path - $e');
      }
    }
  }

  /// 적응적 캐시 정리
  Future<void> adaptiveCleanup() async {
    final memoryUsagePercent = (_currentMemoryUsage / maxMemoryUsage) * 100;

    if (memoryUsagePercent > cacheCleanupThreshold) {
      _logger.info('적응적 캐시 정리 시작: ${memoryUsagePercent.toStringAsFixed(1)}%');

      if (memoryUsagePercent > 95) {
        // 긴급: 50% 정리
        await _evictByPercentage(0.5);
      } else if (memoryUsagePercent > 90) {
        // 경고: 30% 정리
        await _evictByPercentage(0.3);
      } else {
        // 일반: 20% 정리
        await _evictByPercentage(0.2);
      }
    }
  }

  /// 메모리 압축
  Future<void> compressMemory() async {
    _logger.info('메모리 압축 시작');

    final entriesWithLowAccess =
        _memoryCache.values.where((entry) => entry.accessCount < 2).toList();

    for (final entry in entriesWithLowAccess) {
      try {
        final compressed = await _compressData(entry.data);
        if (compressed.length < entry.data.length * 0.8) {
          // 20% 이상 압축되면 교체
          final newEntry = CacheEntry(
            key: entry.key,
            data: compressed,
            createdAt: entry.createdAt,
            lastAccessed: entry.lastAccessed,
            ttl: entry.ttl,
            size: compressed.length,
            accessCount: entry.accessCount,
            isCompressed: true,
          );

          _memoryCache[entry.key] = newEntry;
          _currentCacheSize -= (entry.size - compressed.length);
          _currentMemoryUsage -= (entry.size - compressed.length);
        }
      } catch (e) {
        _logger.warning('압축 실패: ${entry.key} - $e');
      }
    }

    _logger.info('메모리 압축 완료');
  }

  /// 가비지 컬렉션 최적화
  Future<void> optimizeGarbageCollection() async {
    _logger.info('가비지 컬렉션 최적화 시작');

    // 참조 해제
    final expiredKeys = <String>[];
    for (final entry in _memoryCache.entries) {
      if (entry.value.isExpired()) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      final entry = _memoryCache.remove(key)!;
      _currentCacheSize -= entry.size;
      _currentMemoryUsage -= entry.size;
    }

    // 시스템 GC 권장
    if (expiredKeys.isNotEmpty) {
      _logger.info('만료된 캐시 ${expiredKeys.length}개 정리 완료');
    }
  }

  /// 메모리 사용량 통계
  Map<String, dynamic> getMemoryStats() {
    final stats = <String, dynamic>{
      'totalMemoryUsage': _currentMemoryUsage,
      'totalMemoryUsageMB': _currentMemoryUsage / 1024 / 1024,
      'maxMemoryUsage': maxMemoryUsage,
      'maxMemoryUsageMB': maxMemoryUsage / 1024 / 1024,
      'memoryUsagePercent': (_currentMemoryUsage / maxMemoryUsage) * 100,
      'cacheSize': _currentCacheSize,
      'cacheSizeMB': _currentCacheSize / 1024 / 1024,
      'maxCacheSize': maxCacheSize,
      'maxCacheSizeMB': maxCacheSize / 1024 / 1024,
      'cacheUsagePercent': (_currentCacheSize / maxCacheSize) * 100,
      'cacheEntries': _memoryCache.length,
      'fileInfoEntries': _fileInfoCache.length,
    };

    // 캐시 히트율 계산
    final totalAccess =
        _memoryCache.values.map((e) => e.accessCount).fold(0, (a, b) => a + b);
    stats['totalCacheAccess'] = totalAccess;

    return stats;
  }

  /// 캐시 무효화
  void invalidateCache(String pattern) {
    final keysToRemove =
        _memoryCache.keys.where((key) => key.contains(pattern)).toList();

    for (final key in keysToRemove) {
      final entry = _memoryCache.remove(key)!;
      _currentCacheSize -= entry.size;
      _currentMemoryUsage -= entry.size;
    }

    _logger.info('캐시 무효화: $pattern (${keysToRemove.length}개 항목)');
  }

  /// 전체 캐시 정리
  void clearAllCache() {
    _memoryCache.clear();
    _fileInfoCache.clear();
    _currentCacheSize = 0;
    _currentMemoryUsage = 0;

    _logger.info('전체 캐시 정리 완료');
  }

  // 내부 메서드들

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      adaptiveCleanup();
      optimizeGarbageCollection();
    });
  }

  Future<void> _evictLeastRecentlyUsed(int requiredSpace) async {
    final entries = _memoryCache.values.toList();
    entries.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));

    int freedSpace = 0;
    for (final entry in entries) {
      _memoryCache.remove(entry.key);
      _currentCacheSize -= entry.size;
      _currentMemoryUsage -= entry.size;
      freedSpace += entry.size;

      _logger.debug('LRU 제거: ${entry.key} (${_formatBytes(entry.size)})');

      if (freedSpace >= requiredSpace) {
        break;
      }
    }
  }

  Future<void> _evictByPercentage(double percentage) async {
    final targetSize = (_currentCacheSize * (1 - percentage)).round();
    final entries = _memoryCache.values.toList();

    // 우선순위: 액세스 빈도가 낮고 오래된 순
    entries.sort((a, b) {
      final scoreA = a.accessCount /
          DateTime.now().difference(a.createdAt).inHours.clamp(1, 1000);
      final scoreB = b.accessCount /
          DateTime.now().difference(b.createdAt).inHours.clamp(1, 1000);
      return scoreA.compareTo(scoreB);
    });

    while (_currentCacheSize > targetSize && entries.isNotEmpty) {
      final entry = entries.removeAt(0);
      _memoryCache.remove(entry.key);
      _currentCacheSize -= entry.size;
      _currentMemoryUsage -= entry.size;
    }

    _logger.info(
        '정리 완료: ${(percentage * 100).round()}% (${_formatBytes(_currentCacheSize)} 남음)');
  }

  Future<Uint8List> _compressData(Uint8List data) async {
    // 실제 구현에서는 압축 라이브러리 사용
    await Future.delayed(Duration(milliseconds: 1)); // 시뮬레이션
    return data; // 임시로 원본 반환
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  void dispose() {
    _cleanupTimer?.cancel();
    clearAllCache();
  }
}

class CacheEntry {
  final String key;
  Uint8List data;
  final DateTime createdAt;
  DateTime lastAccessed;
  final Duration ttl;
  final int size;
  int accessCount;
  final bool isCompressed;

  CacheEntry({
    required this.key,
    required this.data,
    required this.createdAt,
    required this.lastAccessed,
    required this.ttl,
    required this.size,
    this.accessCount = 0,
    this.isCompressed = false,
  });

  bool isExpired() {
    return DateTime.now().difference(createdAt) > ttl;
  }

  double get priority {
    final age = DateTime.now().difference(createdAt).inHours;
    final timeSinceAccess = DateTime.now().difference(lastAccessed).inMinutes;

    // 액세스 빈도와 최근성을 고려한 우선순위
    return accessCount / (age.clamp(1, 1000) + timeSinceAccess.clamp(1, 1000));
  }
}

class FileInfo {
  final String path;
  final int size;
  final DateTime lastModified;
  final String contentType;
  final String hash;

  FileInfo({
    required this.path,
    required this.size,
    required this.lastModified,
    required this.contentType,
    required this.hash,
  });

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'size': size,
      'lastModified': lastModified.toIso8601String(),
      'contentType': contentType,
      'hash': hash,
    };
  }
}
