/// 로컬 데이터베이스 헬퍼
/// SQLite를 사용한 로컬 캐시 및 동기화 상태 관리

import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../config/drive_config.dart';
import 'logger.dart';

class DatabaseHelper {
  static DatabaseHelper? _instance;
  static DatabaseHelper get instance => _instance ??= DatabaseHelper._();

  Database? _database;
  final Logger _logger = Logger('DatabaseHelper');

  DatabaseHelper._();

  /// 데이터베이스 초기화
  Future<void> initialize() async {
    try {
      // FFI 초기화 (데스크탑용)
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      _database = await _initDatabase();
      _logger.info('데이터베이스 초기화 완료');
    } catch (e) {
      _logger.error('데이터베이스 초기화 실패', e);
      rethrow;
    }
  }

  /// 데이터베이스 초기화
  Future<Database> _initDatabase() async {
    final dbPath = DriveConfig.databasePath;

    // 디렉토리 생성
    final dbFile = File(dbPath);
    final dbDir = dbFile.parent;
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 테이블 생성
  Future<void> _onCreate(Database db, int version) async {
    // 프로젝트 테이블
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        owner_id TEXT NOT NULL,
        local_path TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_sync_at INTEGER,
        metadata TEXT
      )
    ''');

    // 파일 동기화 상태 테이블
    await db.execute('''
      CREATE TABLE sync_states (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT UNIQUE NOT NULL,
        project_id TEXT NOT NULL,
        file_type TEXT NOT NULL,
        local_hash TEXT,
        remote_hash TEXT,
        local_modified INTEGER,
        remote_modified INTEGER,
        sync_status TEXT NOT NULL,
        last_sync_at INTEGER,
        error_message TEXT,
        FOREIGN KEY (project_id) REFERENCES projects (id)
      )
    ''');

    // 동기화 이력 테이블
    await db.execute('''
      CREATE TABLE sync_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL,
        action TEXT NOT NULL,
        status TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        completed_at INTEGER,
        error_message TEXT,
        metadata TEXT
      )
    ''');

    // 캐시 메타데이터 테이블
    await db.execute('''
      CREATE TABLE cache_metadata (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT UNIQUE NOT NULL,
        file_size INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        last_accessed_at INTEGER NOT NULL,
        access_count INTEGER DEFAULT 0
      )
    ''');

    // 인덱스 생성
    await db.execute(
        'CREATE INDEX idx_sync_states_project ON sync_states(project_id)');
    await db.execute(
        'CREATE INDEX idx_sync_states_status ON sync_states(sync_status)');
    await db.execute(
        'CREATE INDEX idx_sync_history_file ON sync_history(file_path)');
    await db.execute(
        'CREATE INDEX idx_cache_metadata_accessed ON cache_metadata(last_accessed_at)');

    _logger.info('데이터베이스 테이블 생성 완료');
  }

  /// 데이터베이스 업그레이드
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _logger.info('데이터베이스 업그레이드: v$oldVersion -> v$newVersion');
    // 향후 스키마 변경 시 처리
  }

  /// 프로젝트 저장/업데이트
  Future<void> saveProject(Map<String, dynamic> project) async {
    if (_database == null) return;

    try {
      await _database!.insert(
        'projects',
        {
          ...project,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      _logger.error('프로젝트 저장 실패', e);
      rethrow;
    }
  }

  /// 프로젝트 조회
  Future<List<Map<String, dynamic>>> getProjects() async {
    if (_database == null) return [];

    try {
      return await _database!.query(
        'projects',
        orderBy: 'updated_at DESC',
      );
    } catch (e) {
      _logger.error('프로젝트 조회 실패', e);
      return [];
    }
  }

  /// 동기화 상태 저장/업데이트
  Future<void> saveSyncState(Map<String, dynamic> syncState) async {
    if (_database == null) return;

    try {
      await _database!.insert(
        'sync_states',
        {
          ...syncState,
          'last_sync_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      _logger.error('동기화 상태 저장 실패', e);
      rethrow;
    }
  }

  /// 동기화 상태 조회
  Future<Map<String, dynamic>?> getSyncState(String filePath) async {
    if (_database == null) return null;

    try {
      final results = await _database!.query(
        'sync_states',
        where: 'file_path = ?',
        whereArgs: [filePath],
        limit: 1,
      );

      return results.isNotEmpty ? results.first : null;
    } catch (e) {
      _logger.error('동기화 상태 조회 실패', e);
      return null;
    }
  }

  /// 프로젝트별 동기화 상태 조회
  Future<List<Map<String, dynamic>>> getProjectSyncStates(
      String projectId) async {
    if (_database == null) return [];

    try {
      return await _database!.query(
        'sync_states',
        where: 'project_id = ?',
        whereArgs: [projectId],
        orderBy: 'file_path ASC',
      );
    } catch (e) {
      _logger.error('프로젝트 동기화 상태 조회 실패', e);
      return [];
    }
  }

  /// 동기화 이력 추가
  Future<void> addSyncHistory(Map<String, dynamic> history) async {
    if (_database == null) return;

    try {
      await _database!.insert('sync_history', history);
    } catch (e) {
      _logger.error('동기화 이력 추가 실패', e);
    }
  }

  /// 동기화 이력 조회
  Future<List<Map<String, dynamic>>> getSyncHistory({
    String? filePath,
    int limit = 100,
  }) async {
    if (_database == null) return [];

    try {
      String? where;
      List<dynamic>? whereArgs;

      if (filePath != null) {
        where = 'file_path = ?';
        whereArgs = [filePath];
      }

      return await _database!.query(
        'sync_history',
        where: where,
        whereArgs: whereArgs,
        orderBy: 'started_at DESC',
        limit: limit,
      );
    } catch (e) {
      _logger.error('동기화 이력 조회 실패', e);
      return [];
    }
  }

  /// 캐시 메타데이터 저장
  Future<void> saveCacheMetadata(String filePath, int fileSize) async {
    if (_database == null) return;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      await _database!.insert(
        'cache_metadata',
        {
          'file_path': filePath,
          'file_size': fileSize,
          'created_at': now,
          'last_accessed_at': now,
          'access_count': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      _logger.error('캐시 메타데이터 저장 실패', e);
    }
  }

  /// 캐시 접근 기록
  Future<void> recordCacheAccess(String filePath) async {
    if (_database == null) return;

    try {
      await _database!.rawUpdate('''
        UPDATE cache_metadata 
        SET last_accessed_at = ?, access_count = access_count + 1
        WHERE file_path = ?
      ''', [DateTime.now().millisecondsSinceEpoch, filePath]);
    } catch (e) {
      _logger.error('캐시 접근 기록 실패', e);
    }
  }

  /// 오래된 캐시 항목 조회
  Future<List<Map<String, dynamic>>> getOldCacheItems(Duration age) async {
    if (_database == null) return [];

    try {
      final cutoff = DateTime.now().subtract(age).millisecondsSinceEpoch;

      return await _database!.query(
        'cache_metadata',
        where: 'last_accessed_at < ?',
        whereArgs: [cutoff],
        orderBy: 'last_accessed_at ASC',
      );
    } catch (e) {
      _logger.error('오래된 캐시 항목 조회 실패', e);
      return [];
    }
  }

  /// 캐시 항목 삭제
  Future<void> deleteCacheItem(String filePath) async {
    if (_database == null) return;

    try {
      await _database!.delete(
        'cache_metadata',
        where: 'file_path = ?',
        whereArgs: [filePath],
      );
    } catch (e) {
      _logger.error('캐시 항목 삭제 실패', e);
    }
  }

  /// 통계 조회
  Future<Map<String, dynamic>> getStatistics() async {
    if (_database == null) return {};

    try {
      // 전체 프로젝트 수
      final projectCountResult =
          await _database!.rawQuery('SELECT COUNT(*) FROM projects');
      final projectCount = projectCountResult.first.values.first as int? ?? 0;

      // 동기화 상태별 파일 수
      final syncStatusCounts = await _database!.rawQuery('''
        SELECT sync_status, COUNT(*) as count 
        FROM sync_states 
        GROUP BY sync_status
      ''');

      // 캐시 크기
      final cacheSizeResult = await _database!
          .rawQuery('SELECT SUM(file_size) FROM cache_metadata');
      final cacheSize = cacheSizeResult.first.values.first as int? ?? 0;

      // 최근 동기화 활동
      final recentSyncs = await _database!.query(
        'sync_history',
        orderBy: 'started_at DESC',
        limit: 10,
      );

      return {
        'projectCount': projectCount,
        'syncStatusCounts': syncStatusCounts,
        'cacheSize': cacheSize,
        'recentSyncs': recentSyncs,
      };
    } catch (e) {
      _logger.error('통계 조회 실패', e);
      return {};
    }
  }

  /// 데이터베이스 정리
  Future<void> cleanup() async {
    if (_database == null) return;

    try {
      // 오래된 동기화 이력 삭제 (30일 이상)
      final cutoff =
          DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch;

      await _database!.delete(
        'sync_history',
        where: 'completed_at < ?',
        whereArgs: [cutoff],
      );

      // VACUUM 실행 (DB 파일 최적화)
      await _database!.execute('VACUUM');

      _logger.info('데이터베이스 정리 완료');
    } catch (e) {
      _logger.error('데이터베이스 정리 실패', e);
    }
  }

  /// 데이터베이스 닫기
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _logger.info('데이터베이스 연결 종료');
    }
  }
}
