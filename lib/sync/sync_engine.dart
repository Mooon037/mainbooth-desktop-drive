/// Main Booth Drive 동기화 엔진
/// 로컬 파일 시스템과 Firebase 간의 동기화를 담당

import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/project_model.dart';
import '../models/track_model.dart';
import '../models/reference_model.dart';
import '../models/work_request_model.dart';
import '../config/drive_config.dart';
import '../config/firebase_config.dart';
import '../utils/file_utils.dart';
import '../utils/logger.dart';
import 'file_watcher.dart';
import 'sync_queue.dart';
import 'conflict_resolver.dart';

class SyncEngine {
  static SyncEngine? _instance;
  static SyncEngine get instance => _instance ??= SyncEngine._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FileWatcher _fileWatcher = FileWatcher();
  final SyncQueue _syncQueue = SyncQueue();
  final ConflictResolver _conflictResolver = ConflictResolver();
  final Logger _logger = Logger('SyncEngine');

  final Map<String, DriveProject> _projects = {};
  final Map<String, StreamSubscription> _projectSubscriptions = {};
  final Map<String, StreamSubscription> _trackSubscriptions = {};

  Timer? _syncTimer;
  bool _isRunning = false;
  String? _currentUserId;

  SyncEngine._();

  /// 동기화 큐 접근자
  SyncQueue get syncQueue => _syncQueue;

  /// 동기화 엔진 시작
  Future<void> start() async {
    if (_isRunning) return;

    _logger.info('동기화 엔진 시작');
    _isRunning = true;

    try {
      // 사용자 인증 확인
      _currentUserId = _auth.currentUser?.uid;
      if (_currentUserId == null) {
        throw Exception('사용자 인증이 필요합니다');
      }

      // 드라이브 디렉토리 생성
      await _createDriveStructure();

      // 기존 프로젝트 로드
      await _loadProjects();

      // 파일 감시자 시작
      _fileWatcher.start(DriveConfig.driveRootPath, _onFileChanged);

      // 동기화 큐 시작
      _syncQueue.start();

      // 주기적 동기화 시작
      _startPeriodicSync();

      // Firebase 실시간 리스너 설정
      _setupFirebaseListeners();
    } catch (e) {
      _logger.error('동기화 엔진 시작 실패: $e');
      _isRunning = false;
      rethrow;
    }
  }

  /// 동기화 엔진 정지
  Future<void> stop() async {
    if (!_isRunning) return;

    _logger.info('동기화 엔진 정지');
    _isRunning = false;

    _syncTimer?.cancel();
    _fileWatcher.stop();
    _syncQueue.stop();

    // 모든 구독 취소
    for (var sub in _projectSubscriptions.values) {
      await sub.cancel();
    }
    for (var sub in _trackSubscriptions.values) {
      await sub.cancel();
    }

    _projectSubscriptions.clear();
    _trackSubscriptions.clear();
    _projects.clear();
  }

  /// 드라이브 구조 생성
  Future<void> _createDriveStructure() async {
    final rootDir = Directory(DriveConfig.driveRootPath);
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }

    final projectsDir = Directory('${DriveConfig.driveRootPath}/Projects');
    if (!await projectsDir.exists()) {
      await projectsDir.create();
    }
  }

  /// 기존 프로젝트 로드
  Future<void> _loadProjects() async {
    try {
      final snapshot = await _firestore
          .collection(FirebaseConfig.projectsCollection)
          .where('collaborators', arrayContains: _currentUserId)
          .get();

      for (var doc in snapshot.docs) {
        final project = DriveProject.fromFirestore(
          doc.data(),
          doc.id,
          DriveConfig.driveRootPath,
        );

        _projects[project.id] = project;
        await _createProjectStructure(project);
        await _syncProjectContent(project);
      }

      _logger.info('${_projects.length}개 프로젝트 로드 완료');
    } catch (e) {
      _logger.error('프로젝트 로드 실패: $e');
    }
  }

  /// 프로젝트 폴더 구조 생성
  Future<void> _createProjectStructure(DriveProject project) async {
    final projectDir = Directory(project.localPath);
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }

    // 하위 폴더 생성
    for (var folder in DriveConfig.projectFolders) {
      final subDir = Directory('${project.localPath}/$folder');
      if (!await subDir.exists()) {
        await subDir.create();
      }
    }

    // 메타데이터 파일 생성
    final metadataFile =
        File('${project.localPath}/${DriveConfig.metadataFileName}');
    await metadataFile.writeAsString(project.toJson().toString());
  }

  /// 프로젝트 콘텐츠 동기화
  Future<void> _syncProjectContent(DriveProject project) async {
    // 트랙 동기화
    await _syncTracks(project);

    // 레퍼런스 동기화
    await _syncReferences(project);

    // 작업 요청 동기화
    await _syncWorkRequests(project);
  }

  /// 트랙 동기화
  Future<void> _syncTracks(DriveProject project) async {
    try {
      final snapshot = await _firestore
          .collection(FirebaseConfig.projectsCollection)
          .doc(project.id)
          .collection(FirebaseConfig.tracksCollection)
          .get();

      for (var doc in snapshot.docs) {
        final track = DriveTrack.fromFirestore(
          doc.data(),
          doc.id,
          project.id,
          project.localPath,
        );

        // 로컬에 파일이 없으면 placeholder 생성
        final trackFile = File(track.localPath);
        if (!await trackFile.exists()) {
          await _createPlaceholder(trackFile, track);
        }
      }
    } catch (e) {
      _logger.error('트랙 동기화 실패: $e');
    }
  }

  /// 레퍼런스 동기화
  Future<void> _syncReferences(DriveProject project) async {
    try {
      final snapshot = await _firestore
          .collection(FirebaseConfig.projectsCollection)
          .doc(project.id)
          .collection(FirebaseConfig.referencesCollection)
          .get();

      for (var doc in snapshot.docs) {
        final reference = DriveReference.fromFirestore(
          doc.data(),
          doc.id,
          project.id,
          project.localPath,
        );

        final refFile = File(reference.localPath);
        if (!await refFile.exists()) {
          await _createPlaceholder(refFile, reference);
        }
      }
    } catch (e) {
      _logger.error('레퍼런스 동기화 실패: $e');
    }
  }

  /// 작업 요청 동기화
  Future<void> _syncWorkRequests(DriveProject project) async {
    try {
      final snapshot = await _firestore
          .collection(FirebaseConfig.projectsCollection)
          .doc(project.id)
          .collection(FirebaseConfig.workRequestsCollection)
          .get();

      for (var doc in snapshot.docs) {
        final workRequest = DriveWorkRequest.fromFirestore(
          doc.data(),
          doc.id,
          project.id,
          project.localPath,
        );

        // 마크다운 파일로 저장
        final mdFile = File(workRequest.localPath);
        await mdFile.writeAsString(workRequest.toMarkdown());
      }
    } catch (e) {
      _logger.error('작업 요청 동기화 실패: $e');
    }
  }

  /// Placeholder 파일 생성
  Future<void> _createPlaceholder(File file, dynamic model) async {
    await file.create(recursive: true);

    // 메타데이터 파일 생성
    final metadataPath = '${file.path}.metadata';
    final metadataFile = File(metadataPath);
    await metadataFile.writeAsString(model.toJson().toString());
  }

  /// 파일 변경 이벤트 처리
  void _onFileChanged(FileSystemEvent event) {
    if (_shouldIgnoreFile(event.path)) return;

    if (event is FileSystemCreateEvent) {
      _handleFileCreated(event.path);
    } else if (event is FileSystemModifyEvent) {
      _handleFileModified(event.path);
    } else if (event is FileSystemDeleteEvent) {
      _handleFileDeleted(event.path);
    }
  }

  /// 파일 생성 처리
  Future<void> _handleFileCreated(String path) async {
    _logger.info('파일 생성 감지: $path');

    final projectId = _extractProjectId(path);
    if (projectId == null) return;

    final folderType = _extractFolderType(path);
    if (folderType == null) return;

    // 동기화 큐에 추가
    _syncQueue.addUploadTask(path, projectId, folderType);
  }

  /// 파일 수정 처리
  Future<void> _handleFileModified(String path) async {
    _logger.info('파일 수정 감지: $path');

    final projectId = _extractProjectId(path);
    if (projectId == null) return;

    final folderType = _extractFolderType(path);
    if (folderType == null) return;

    // 동기화 큐에 추가
    _syncQueue.addUploadTask(path, projectId, folderType);
  }

  /// 파일 삭제 처리
  Future<void> _handleFileDeleted(String path) async {
    _logger.info('파일 삭제 감지: $path');

    final projectId = _extractProjectId(path);
    if (projectId == null) return;

    final folderType = _extractFolderType(path);
    if (folderType == null) return;

    // 권한 확인 (관리자만 삭제 가능)
    final project = _projects[projectId];
    if (project != null && !project.isOwner) {
      _logger.warning('삭제 권한 없음: $path');
      // 파일 복원
      await _syncProjectContent(project);
      return;
    }

    // 동기화 큐에 추가
    _syncQueue.addDeleteTask(path, projectId, folderType);
  }

  /// Firebase 실시간 리스너 설정
  void _setupFirebaseListeners() {
    // 프로젝트 변경 감지
    final projectsStream = _firestore
        .collection(FirebaseConfig.projectsCollection)
        .where('collaborators', arrayContains: _currentUserId)
        .snapshots();

    _projectSubscriptions['main'] = projectsStream.listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _handleProjectAdded(change.doc);
        } else if (change.type == DocumentChangeType.modified) {
          _handleProjectModified(change.doc);
        } else if (change.type == DocumentChangeType.removed) {
          _handleProjectRemoved(change.doc);
        }
      }
    });
  }

  /// 새 프로젝트 추가 처리
  Future<void> _handleProjectAdded(DocumentSnapshot doc) async {
    final project = DriveProject.fromFirestore(
      doc.data() as Map<String, dynamic>,
      doc.id,
      DriveConfig.driveRootPath,
    );

    _projects[project.id] = project;
    await _createProjectStructure(project);
    await _syncProjectContent(project);

    // 트랙 실시간 리스너 설정
    _setupTrackListener(project.id);
  }

  /// 프로젝트 수정 처리
  Future<void> _handleProjectModified(DocumentSnapshot doc) async {
    final project = DriveProject.fromFirestore(
      doc.data() as Map<String, dynamic>,
      doc.id,
      DriveConfig.driveRootPath,
    );

    _projects[project.id] = project;

    // 프로젝트 이름 변경 시 폴더명 변경
    final oldPath = '${DriveConfig.driveRootPath}/Projects/${doc.id}';
    final newPath = project.localPath;

    if (oldPath != newPath) {
      final oldDir = Directory(oldPath);
      if (await oldDir.exists()) {
        await oldDir.rename(newPath);
      }
    }
  }

  /// 프로젝트 삭제 처리
  Future<void> _handleProjectRemoved(DocumentSnapshot doc) async {
    final projectId = doc.id;
    final project = _projects[projectId];

    if (project != null) {
      // 로컬 폴더 삭제
      final projectDir = Directory(project.localPath);
      if (await projectDir.exists()) {
        await projectDir.delete(recursive: true);
      }

      _projects.remove(projectId);

      // 리스너 정리
      _trackSubscriptions[projectId]?.cancel();
      _trackSubscriptions.remove(projectId);
    }
  }

  /// 트랙 실시간 리스너 설정
  void _setupTrackListener(String projectId) {
    final tracksStream = _firestore
        .collection(FirebaseConfig.projectsCollection)
        .doc(projectId)
        .collection(FirebaseConfig.tracksCollection)
        .snapshots();

    _trackSubscriptions[projectId] = tracksStream.listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _handleTrackAdded(projectId, change.doc);
        } else if (change.type == DocumentChangeType.modified) {
          _handleTrackModified(projectId, change.doc);
        } else if (change.type == DocumentChangeType.removed) {
          _handleTrackRemoved(projectId, change.doc);
        }
      }
    });
  }

  /// 새 트랙 추가 처리
  Future<void> _handleTrackAdded(String projectId, DocumentSnapshot doc) async {
    final project = _projects[projectId];
    if (project == null) return;

    final track = DriveTrack.fromFirestore(
      doc.data() as Map<String, dynamic>,
      doc.id,
      projectId,
      project.localPath,
    );

    final trackFile = File(track.localPath);
    if (!await trackFile.exists()) {
      await _createPlaceholder(trackFile, track);
    }
  }

  /// 트랙 수정 처리
  Future<void> _handleTrackModified(
      String projectId, DocumentSnapshot doc) async {
    // 트랙 정보 업데이트
    final project = _projects[projectId];
    if (project == null) return;

    final track = DriveTrack.fromFirestore(
      doc.data() as Map<String, dynamic>,
      doc.id,
      projectId,
      project.localPath,
    );

    // 메타데이터 업데이트
    final metadataFile = File('${track.localPath}.metadata');
    await metadataFile.writeAsString(track.toJson().toString());
  }

  /// 트랙 삭제 처리
  Future<void> _handleTrackRemoved(
      String projectId, DocumentSnapshot doc) async {
    final project = _projects[projectId];
    if (project == null) return;

    final trackName = (doc.data() as Map<String, dynamic>)['name'] ?? '';
    final trackPath = '${project.localPath}/Tracks/$trackName.wav';
    final trackFile = File(trackPath);

    if (await trackFile.exists()) {
      await trackFile.delete();
    }

    // 메타데이터 파일도 삭제
    final metadataFile = File('$trackPath.metadata');
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }
  }

  /// 주기적 동기화 시작
  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(FirebaseConfig.syncInterval, (_) {
      _performPeriodicSync();
    });
  }

  /// 주기적 동기화 수행
  Future<void> _performPeriodicSync() async {
    _logger.debug('주기적 동기화 시작');

    for (var project in _projects.values) {
      await _syncProjectContent(project);
    }
  }

  /// 파일 무시 여부 확인
  bool _shouldIgnoreFile(String path) {
    final fileName = path.split(Platform.pathSeparator).last;

    for (var pattern in DriveConfig.ignoredPatterns) {
      if (pattern.contains('*')) {
        final regex = pattern.replaceAll('*', '.*');
        if (RegExp(regex).hasMatch(fileName)) {
          return true;
        }
      } else if (fileName == pattern) {
        return true;
      }
    }

    return false;
  }

  /// 프로젝트 ID 추출
  String? _extractProjectId(String path) {
    final parts = path.split(Platform.pathSeparator);
    final projectsIndex = parts.indexOf('Projects');

    if (projectsIndex >= 0 && projectsIndex + 1 < parts.length) {
      return parts[projectsIndex + 1];
    }

    return null;
  }

  /// 폴더 타입 추출
  String? _extractFolderType(String path) {
    for (var folder in DriveConfig.projectFolders) {
      if (path.contains(folder)) {
        return folder;
      }
    }
    return null;
  }

  /// 파일 다운로드
  Future<void> downloadFile(String cloudPath, String localPath) async {
    try {
      final ref = _storage.ref(cloudPath);
      final file = File(localPath);

      await file.create(recursive: true);
      await ref.writeToFile(file);

      _logger.info('파일 다운로드 완료: $localPath');
    } catch (e) {
      _logger.error('파일 다운로드 실패: $e');
      rethrow;
    }
  }

  /// 파일 업로드
  Future<void> uploadFile(String localPath, String cloudPath) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        throw Exception('파일이 존재하지 않습니다: $localPath');
      }

      final ref = _storage.ref(cloudPath);
      await ref.putFile(file);

      _logger.info('파일 업로드 완료: $localPath');
    } catch (e) {
      _logger.error('파일 업로드 실패: $e');
      rethrow;
    }
  }
}
