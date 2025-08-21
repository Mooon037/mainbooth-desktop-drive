/// 동기화 큐
/// 파일 업로드/다운로드 작업을 관리하는 큐

import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/firebase_config.dart';
import '../utils/logger.dart';
import '../utils/file_utils.dart';

class SyncQueue {
  final Logger _logger = Logger('SyncQueue');
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Queue<SyncTask> _uploadQueue = Queue();
  final Queue<SyncTask> _downloadQueue = Queue();
  final Map<String, SyncTask> _activeTasks = {};

  int _activeUploads = 0;
  int _activeDownloads = 0;
  bool _isRunning = false;

  Timer? _processTimer;

  /// 큐 시작
  void start() {
    if (_isRunning) return;

    _logger.info('동기화 큐 시작');
    _isRunning = true;

    // 주기적으로 큐 처리
    _processTimer = Timer.periodic(Duration(seconds: 1), (_) {
      _processQueues();
    });
  }

  /// 큐 중지
  void stop() {
    if (!_isRunning) return;

    _logger.info('동기화 큐 중지');
    _isRunning = false;

    _processTimer?.cancel();
    _uploadQueue.clear();
    _downloadQueue.clear();
    _activeTasks.clear();
    _activeUploads = 0;
    _activeDownloads = 0;
  }

  /// 업로드 작업 추가
  void addUploadTask(String localPath, String projectId, String folderType) {
    final task = SyncTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_upload',
      type: SyncTaskType.upload,
      localPath: localPath,
      projectId: projectId,
      folderType: folderType,
      createdAt: DateTime.now(),
    );

    // 중복 체크
    if (_isTaskDuplicate(task)) {
      _logger.debug('중복 업로드 작업 무시: $localPath');
      return;
    }

    _uploadQueue.add(task);
    _logger.info('업로드 작업 추가: $localPath');
  }

  /// 다운로드 작업 추가
  void addDownloadTask(String cloudPath, String localPath, String projectId) {
    final task = SyncTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_download',
      type: SyncTaskType.download,
      localPath: localPath,
      cloudPath: cloudPath,
      projectId: projectId,
      createdAt: DateTime.now(),
    );

    if (_isTaskDuplicate(task)) {
      _logger.debug('중복 다운로드 작업 무시: $localPath');
      return;
    }

    _downloadQueue.add(task);
    _logger.info('다운로드 작업 추가: $cloudPath -> $localPath');
  }

  /// 삭제 작업 추가
  void addDeleteTask(String path, String projectId, String folderType) {
    final task = SyncTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_delete',
      type: SyncTaskType.delete,
      localPath: path,
      projectId: projectId,
      folderType: folderType,
      createdAt: DateTime.now(),
    );

    _uploadQueue.add(task);
    _logger.info('삭제 작업 추가: $path');
  }

  /// 큐 처리
  Future<void> _processQueues() async {
    if (!_isRunning) return;

    // 업로드 처리
    while (_activeUploads < FirebaseConfig.maxConcurrentUploads &&
        _uploadQueue.isNotEmpty) {
      final task = _uploadQueue.removeFirst();
      _processUploadTask(task);
    }

    // 다운로드 처리
    while (_activeDownloads < FirebaseConfig.maxConcurrentDownloads &&
        _downloadQueue.isNotEmpty) {
      final task = _downloadQueue.removeFirst();
      _processDownloadTask(task);
    }
  }

  /// 업로드 작업 처리
  Future<void> _processUploadTask(SyncTask task) async {
    _activeUploads++;
    _activeTasks[task.id] = task;

    try {
      _logger.info('업로드 시작: ${task.localPath}');

      if (task.type == SyncTaskType.delete) {
        await _processDeleteTask(task);
      } else {
        await _uploadFile(task);
      }

      task.status = SyncTaskStatus.completed;
      _logger.info('업로드 완료: ${task.localPath}');
    } catch (e) {
      _logger.error('업로드 실패: ${task.localPath} - $e');
      task.status = SyncTaskStatus.failed;
      task.error = e.toString();

      // 재시도 로직
      if (task.retryCount < FirebaseConfig.maxRetries) {
        task.retryCount++;
        task.status = SyncTaskStatus.pending;

        // 재시도 대기 후 큐에 다시 추가
        Future.delayed(FirebaseConfig.retryDelay, () {
          _uploadQueue.add(task);
        });
      }
    } finally {
      _activeUploads--;
      _activeTasks.remove(task.id);
    }
  }

  /// 다운로드 작업 처리
  Future<void> _processDownloadTask(SyncTask task) async {
    _activeDownloads++;
    _activeTasks[task.id] = task;

    try {
      _logger.info('다운로드 시작: ${task.cloudPath}');

      await _downloadFile(task);

      task.status = SyncTaskStatus.completed;
      _logger.info('다운로드 완료: ${task.localPath}');
    } catch (e) {
      _logger.error('다운로드 실패: ${task.cloudPath} - $e');
      task.status = SyncTaskStatus.failed;
      task.error = e.toString();

      // 재시도 로직
      if (task.retryCount < FirebaseConfig.maxRetries) {
        task.retryCount++;
        task.status = SyncTaskStatus.pending;

        Future.delayed(FirebaseConfig.retryDelay, () {
          _downloadQueue.add(task);
        });
      }
    } finally {
      _activeDownloads--;
      _activeTasks.remove(task.id);
    }
  }

  /// 파일 업로드
  Future<void> _uploadFile(SyncTask task) async {
    final file = File(task.localPath);
    if (!await file.exists()) {
      throw Exception('파일이 존재하지 않습니다: ${task.localPath}');
    }

    // 파일 정보 추출
    final fileName = file.path.split(Platform.pathSeparator).last;
    final fileSize = await file.length();
    final fileHash = await FileUtils.calculateFileHash(file);

    // Storage 경로 생성
    String storagePath = '';
    if (task.folderType == 'Tracks') {
      storagePath =
          '${FirebaseConfig.tracksStoragePath}/${task.projectId}/$fileName';
    } else if (task.folderType == 'References') {
      storagePath =
          '${FirebaseConfig.referencesStoragePath}/${task.projectId}/$fileName';
    }

    // 파일 업로드
    final ref = _storage.ref(storagePath);
    final uploadTask = ref.putFile(file);

    // 진행률 모니터링
    uploadTask.snapshotEvents.listen((snapshot) {
      final progress = snapshot.bytesTransferred / snapshot.totalBytes;
      task.progress = progress;
      _logger.debug(
          '업로드 진행률: ${(progress * 100).toStringAsFixed(1)}% - ${task.localPath}');
    });

    await uploadTask;

    // 다운로드 URL 가져오기
    final downloadUrl = await ref.getDownloadURL();

    // Firestore 업데이트
    await _updateFirestore(task, downloadUrl, fileSize, fileHash);
  }

  /// 파일 다운로드
  Future<void> _downloadFile(SyncTask task) async {
    final file = File(task.localPath);

    // 디렉토리 생성
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Storage에서 다운로드
    final ref = _storage.ref(task.cloudPath);

    // 파일 크기 확인
    final metadata = await ref.getMetadata();
    final totalSize = metadata.size ?? 0;

    // 청크 다운로드 구현 (대용량 파일 지원)
    if (totalSize > FirebaseConfig.chunkSize * 10) {
      await _downloadInChunks(ref, file, totalSize, task);
    } else {
      // 작은 파일은 한 번에 다운로드
      await ref.writeToFile(file);
    }
  }

  /// 청크 단위 다운로드
  Future<void> _downloadInChunks(
    Reference ref,
    File file,
    int totalSize,
    SyncTask task,
  ) async {
    final tempFile = File('${file.path}.tmp');
    final sink = tempFile.openWrite();

    try {
      int downloadedBytes = 0;

      // 청크 단위로 다운로드
      while (downloadedBytes < totalSize) {
        final chunkSize =
            (totalSize - downloadedBytes > FirebaseConfig.chunkSize)
                ? FirebaseConfig.chunkSize
                : totalSize - downloadedBytes;

        final data = await ref.getData(chunkSize);
        if (data != null) {
          sink.add(data);
          downloadedBytes += data.length;

          task.progress = downloadedBytes / totalSize;
          _logger.debug(
              '다운로드 진행률: ${(task.progress * 100).toStringAsFixed(1)}% - ${task.localPath}');
        }
      }

      await sink.close();

      // 임시 파일을 실제 파일로 이동
      await tempFile.rename(file.path);
    } catch (e) {
      await sink.close();
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  /// 삭제 작업 처리
  Future<void> _processDeleteTask(SyncTask task) async {
    // Firestore에서 삭제
    if (task.folderType == 'Tracks') {
      await _deleteTrackFromFirestore(task);
    } else if (task.folderType == 'References') {
      await _deleteReferenceFromFirestore(task);
    }

    // Storage에서 삭제
    final fileName = task.localPath.split(Platform.pathSeparator).last;
    String storagePath = '';

    if (task.folderType == 'Tracks') {
      storagePath =
          '${FirebaseConfig.tracksStoragePath}/${task.projectId}/$fileName';
    } else if (task.folderType == 'References') {
      storagePath =
          '${FirebaseConfig.referencesStoragePath}/${task.projectId}/$fileName';
    }

    if (storagePath.isNotEmpty) {
      try {
        final ref = _storage.ref(storagePath);
        await ref.delete();
      } catch (e) {
        _logger.error('Storage 삭제 실패: $storagePath - $e');
      }
    }
  }

  /// Firestore 업데이트
  Future<void> _updateFirestore(
    SyncTask task,
    String downloadUrl,
    int fileSize,
    String fileHash,
  ) async {
    final fileName = task.localPath.split(Platform.pathSeparator).last;
    final now = FieldValue.serverTimestamp();

    if (task.folderType == 'Tracks') {
      // 트랙 문서 생성/업데이트
      final trackData = {
        'name': fileName.replaceAll('.wav', '').replaceAll('.mp3', ''),
        'audioUrl': downloadUrl,
        'uploaderId': 'desktop_user', // TODO: 실제 사용자 ID
        'uploaderName': 'Desktop User', // TODO: 실제 사용자 이름
        'duration': 0, // TODO: 오디오 파일 길이 계산
        'fileSize': fileSize,
        'fileHash': fileHash,
        'createdAt': now,
        'updatedAt': now,
      };

      await _firestore
          .collection(FirebaseConfig.projectsCollection)
          .doc(task.projectId)
          .collection(FirebaseConfig.tracksCollection)
          .add(trackData);
    } else if (task.folderType == 'References') {
      // 레퍼런스 문서 생성/업데이트
      final refData = {
        'name': fileName,
        'fileUrl': downloadUrl,
        'uploaderId': 'desktop_user', // TODO: 실제 사용자 ID
        'uploaderName': 'Desktop User', // TODO: 실제 사용자 이름
        'fileSize': fileSize,
        'createdAt': now,
        'updatedAt': now,
      };

      await _firestore
          .collection(FirebaseConfig.projectsCollection)
          .doc(task.projectId)
          .collection(FirebaseConfig.referencesCollection)
          .add(refData);
    }
  }

  /// 트랙 삭제 (Firestore)
  Future<void> _deleteTrackFromFirestore(SyncTask task) async {
    final fileName = task.localPath.split(Platform.pathSeparator).last;
    final trackName = fileName.replaceAll('.wav', '').replaceAll('.mp3', '');

    final snapshot = await _firestore
        .collection(FirebaseConfig.projectsCollection)
        .doc(task.projectId)
        .collection(FirebaseConfig.tracksCollection)
        .where('name', isEqualTo: trackName)
        .get();

    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  /// 레퍼런스 삭제 (Firestore)
  Future<void> _deleteReferenceFromFirestore(SyncTask task) async {
    final fileName = task.localPath.split(Platform.pathSeparator).last;

    final snapshot = await _firestore
        .collection(FirebaseConfig.projectsCollection)
        .doc(task.projectId)
        .collection(FirebaseConfig.referencesCollection)
        .where('name', isEqualTo: fileName)
        .get();

    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  /// 작업 중복 체크
  bool _isTaskDuplicate(SyncTask task) {
    // 활성 작업 중 중복 체크
    for (var activeTask in _activeTasks.values) {
      if (activeTask.localPath == task.localPath &&
          activeTask.type == task.type) {
        return true;
      }
    }

    // 대기 중인 작업 중 중복 체크
    final allTasks = [..._uploadQueue, ..._downloadQueue];
    for (var queuedTask in allTasks) {
      if (queuedTask.localPath == task.localPath &&
          queuedTask.type == task.type) {
        return true;
      }
    }

    return false;
  }

  /// 큐 상태 정보
  Map<String, dynamic> getQueueStatus() {
    return {
      'uploadQueueSize': _uploadQueue.length,
      'downloadQueueSize': _downloadQueue.length,
      'activeUploads': _activeUploads,
      'activeDownloads': _activeDownloads,
      'activeTasks': _activeTasks.values
          .map((task) => {
                'id': task.id,
                'type': task.type.toString(),
                'path': task.localPath,
                'progress': task.progress,
                'status': task.status.toString(),
              })
          .toList(),
    };
  }
}

/// 동기화 작업
class SyncTask {
  final String id;
  final SyncTaskType type;
  final String localPath;
  final String? cloudPath;
  final String projectId;
  final String? folderType;
  final DateTime createdAt;

  SyncTaskStatus status = SyncTaskStatus.pending;
  double progress = 0.0;
  int retryCount = 0;
  String? error;

  SyncTask({
    required this.id,
    required this.type,
    required this.localPath,
    this.cloudPath,
    required this.projectId,
    this.folderType,
    required this.createdAt,
  });
}

/// 동기화 작업 타입
enum SyncTaskType {
  upload,
  download,
  delete,
}

/// 동기화 작업 상태
enum SyncTaskStatus {
  pending,
  processing,
  completed,
  failed,
}
