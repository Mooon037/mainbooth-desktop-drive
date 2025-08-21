/// 성능 최적화 관리자
/// 대용량 파일 처리, 동시 사용자 처리, 성능 최적화를 담당

import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import '../utils/logger.dart';

class PerformanceOptimizer {
  static PerformanceOptimizer? _instance;
  static PerformanceOptimizer get instance => _instance ??= PerformanceOptimizer._();
  
  final Logger _logger = Logger('PerformanceOptimizer');
  
  // 성능 설정
  int maxConcurrentUploads = 3;
  int maxConcurrentDownloads = 5;
  int chunkSize = 4 * 1024 * 1024; // 4MB
  int maxMemoryCache = 100 * 1024 * 1024; // 100MB
  int compressionThreshold = 1024 * 1024; // 1MB 이상 파일 압축
  
  // 성능 추적
  final Map<String, PerformanceMetrics> _metrics = {};
  final List<TransferTask> _activeTasks = [];
  
  PerformanceOptimizer._();
  
  /// 대용량 파일 청크 업로드
  Future<void> uploadLargeFile({
    required String filePath,
    required String destinationUrl,
    required Function(double) onProgress,
    int? customChunkSize,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }
    
    final fileSize = await file.length();
    final effectiveChunkSize = customChunkSize ?? _getOptimalChunkSize(fileSize);
    
    _logger.info('시작: 대용량 파일 업로드 ($fileSize bytes, chunk: $effectiveChunkSize)');
    
    final task = TransferTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: TransferType.upload,
      filePath: filePath,
      totalSize: fileSize,
      chunkSize: effectiveChunkSize,
    );
    
    _activeTasks.add(task);
    
    try {
      await _performChunkedUpload(task, destinationUrl, onProgress);
      _logger.info('완료: 대용량 파일 업로드');
    } finally {
      _activeTasks.remove(task);
    }
  }
  
  /// 대용량 파일 청크 다운로드
  Future<void> downloadLargeFile({
    required String sourceUrl,
    required String destinationPath,
    required Function(double) onProgress,
    int? customChunkSize,
  }) async {
    // 파일 크기 미리 확인
    final fileSize = await _getRemoteFileSize(sourceUrl);
    final effectiveChunkSize = customChunkSize ?? _getOptimalChunkSize(fileSize);
    
    _logger.info('시작: 대용량 파일 다운로드 ($fileSize bytes, chunk: $effectiveChunkSize)');
    
    final task = TransferTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: TransferType.download,
      filePath: destinationPath,
      totalSize: fileSize,
      chunkSize: effectiveChunkSize,
    );
    
    _activeTasks.add(task);
    
    try {
      await _performChunkedDownload(task, sourceUrl, onProgress);
      _logger.info('완료: 대용량 파일 다운로드');
    } finally {
      _activeTasks.remove(task);
    }
  }
  
  /// 멀티스레드 파일 처리
  Future<void> processFileInIsolate({
    required String filePath,
    required String operation,
    Map<String, dynamic>? parameters,
  }) async {
    final receivePort = ReceivePort();
    
    final isolate = await Isolate.spawn(
      _isolateFileProcessor,
      IsolateMessage(
        sendPort: receivePort.sendPort,
        filePath: filePath,
        operation: operation,
        parameters: parameters ?? {},
      ),
    );
    
    final completer = Completer<void>();
    
    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        if (message['error'] != null) {
          completer.completeError(Exception(message['error']));
        } else {
          completer.complete();
        }
      }
      receivePort.close();
      isolate.kill();
    });
    
    return completer.future;
  }
  
  /// 메모리 효율적 파일 비교
  Future<bool> compareFilesEfficiently(String file1Path, String file2Path) async {
    final file1 = File(file1Path);
    final file2 = File(file2Path);
    
    // 크기 먼저 비교
    final size1 = await file1.length();
    final size2 = await file2.length();
    
    if (size1 != size2) {
      return false;
    }
    
    // 작은 파일은 전체 비교
    if (size1 < 1024 * 1024) { // 1MB 미만
      final bytes1 = await file1.readAsBytes();
      final bytes2 = await file2.readAsBytes();
      return _compareBytes(bytes1, bytes2);
    }
    
    // 큰 파일은 청크 단위로 비교
    return await _compareFilesInChunks(file1, file2);
  }
  
  /// 적응적 압축
  Future<Uint8List?> compressIfBeneficial(Uint8List data) async {
    if (data.length < compressionThreshold) {
      return null; // 작은 파일은 압축하지 않음
    }
    
    // 파일 타입 감지
    final fileType = _detectFileType(data);
    if (_isAlreadyCompressed(fileType)) {
      return null; // 이미 압축된 형식
    }
    
    final startTime = DateTime.now();
    
    // 압축 수행 (실제 구현에서는 dart:io의 GZipCodec 등 사용)
    final compressedData = await _performCompression(data);
    
    final compressionTime = DateTime.now().difference(startTime);
    final compressionRatio = compressedData.length / data.length;
    
    _logger.debug('압축 완료: 비율=${compressionRatio.toStringAsFixed(2)}, 시간=${compressionTime.inMilliseconds}ms');
    
    // 압축 효과가 미미하면 원본 반환
    if (compressionRatio > 0.9) {
      return null;
    }
    
    return compressedData;
  }
  
  /// 동시 사용자 처리 최적화
  void optimizeForConcurrentUsers(int userCount) {
    if (userCount > 10) {
      // 많은 사용자: 청크 크기 증가, 동시 전송 제한
      chunkSize = 8 * 1024 * 1024; // 8MB
      maxConcurrentUploads = 2;
      maxConcurrentDownloads = 3;
    } else if (userCount > 5) {
      // 중간 사용자: 균형 잡힌 설정
      chunkSize = 4 * 1024 * 1024; // 4MB
      maxConcurrentUploads = 3;
      maxConcurrentDownloads = 4;
    } else {
      // 적은 사용자: 최대 성능
      chunkSize = 2 * 1024 * 1024; // 2MB
      maxConcurrentUploads = 5;
      maxConcurrentDownloads = 8;
    }
    
    _logger.info('동시 사용자 최적화 적용: users=$userCount, chunk=${chunkSize / 1024 / 1024}MB');
  }
  
  /// 네트워크 대역폭 적응
  void adaptToBandwidth(double bandwidthMbps) {
    if (bandwidthMbps < 1.0) {
      // 저속 연결: 작은 청크, 적은 동시 전송
      chunkSize = 512 * 1024; // 512KB
      maxConcurrentUploads = 1;
      maxConcurrentDownloads = 2;
    } else if (bandwidthMbps < 10.0) {
      // 중속 연결: 중간 설정
      chunkSize = 2 * 1024 * 1024; // 2MB
      maxConcurrentUploads = 2;
      maxConcurrentDownloads = 3;
    } else {
      // 고속 연결: 큰 청크, 많은 동시 전송
      chunkSize = 8 * 1024 * 1024; // 8MB
      maxConcurrentUploads = 5;
      maxConcurrentDownloads = 8;
    }
    
    _logger.info('대역폭 적응 완료: ${bandwidthMbps}Mbps, chunk=${chunkSize / 1024 / 1024}MB');
  }
  
  /// 성능 메트릭 수집
  void recordMetrics(String operation, Duration duration, int dataSize) {
    final key = operation;
    
    if (!_metrics.containsKey(key)) {
      _metrics[key] = PerformanceMetrics(operation);
    }
    
    _metrics[key]!.addSample(duration, dataSize);
  }
  
  /// 성능 통계 조회
  Map<String, dynamic> getPerformanceStats() {
    final stats = <String, dynamic>{};
    
    for (var entry in _metrics.entries) {
      stats[entry.key] = entry.value.toJson();
    }
    
    stats['activeTasks'] = _activeTasks.length;
    stats['memoryUsage'] = _getMemoryUsage();
    
    return stats;
  }
  
  // 내부 메서드들
  
  int _getOptimalChunkSize(int fileSize) {
    if (fileSize < 10 * 1024 * 1024) { // 10MB 미만
      return 1 * 1024 * 1024; // 1MB
    } else if (fileSize < 100 * 1024 * 1024) { // 100MB 미만
      return 4 * 1024 * 1024; // 4MB
    } else {
      return 8 * 1024 * 1024; // 8MB
    }
  }
  
  Future<void> _performChunkedUpload(
    TransferTask task,
    String destinationUrl,
    Function(double) onProgress,
  ) async {
    final file = File(task.filePath);
    final totalChunks = (task.totalSize / task.chunkSize).ceil();
    
    for (int i = 0; i < totalChunks; i++) {
      final offset = i * task.chunkSize;
      final length = (offset + task.chunkSize > task.totalSize) 
          ? task.totalSize - offset 
          : task.chunkSize;
      
      final chunk = await _readFileChunk(file, offset, length);
      await _uploadChunk(chunk, destinationUrl, i);
      
      task.transferredSize += length;
      onProgress(task.transferredSize / task.totalSize);
    }
  }
  
  Future<void> _performChunkedDownload(
    TransferTask task,
    String sourceUrl,
    Function(double) onProgress,
  ) async {
    final file = File(task.filePath);
    await file.create(recursive: true);
    
    final totalChunks = (task.totalSize / task.chunkSize).ceil();
    
    for (int i = 0; i < totalChunks; i++) {
      final offset = i * task.chunkSize;
      final length = (offset + task.chunkSize > task.totalSize) 
          ? task.totalSize - offset 
          : task.chunkSize;
      
      final chunk = await _downloadChunk(sourceUrl, offset, length);
      await _writeFileChunk(file, chunk, offset);
      
      task.transferredSize += length;
      onProgress(task.transferredSize / task.totalSize);
    }
  }
  
  Future<Uint8List> _readFileChunk(File file, int offset, int length) async {
    final randomAccessFile = await file.open();
    await randomAccessFile.setPosition(offset);
    final chunk = await randomAccessFile.read(length);
    await randomAccessFile.close();
    return Uint8List.fromList(chunk);
  }
  
  Future<void> _writeFileChunk(File file, Uint8List chunk, int offset) async {
    final randomAccessFile = await file.open(mode: FileMode.writeOnlyAppend);
    await randomAccessFile.setPosition(offset);
    await randomAccessFile.writeFrom(chunk);
    await randomAccessFile.close();
  }
  
  Future<Uint8List> _uploadChunk(Uint8List chunk, String url, int chunkIndex) async {
    // 실제 구현에서는 HTTP 멀티파트 업로드 사용
    await Future.delayed(Duration(milliseconds: 100)); // 시뮬레이션
    return chunk;
  }
  
  Future<Uint8List> _downloadChunk(String url, int offset, int length) async {
    // 실제 구현에서는 HTTP Range 요청 사용
    await Future.delayed(Duration(milliseconds: 100)); // 시뮬레이션
    return Uint8List(length);
  }
  
  Future<int> _getRemoteFileSize(String url) async {
    // 실제 구현에서는 HTTP HEAD 요청으로 Content-Length 확인
    return 10 * 1024 * 1024; // 시뮬레이션
  }
  
  bool _compareBytes(Uint8List bytes1, Uint8List bytes2) {
    if (bytes1.length != bytes2.length) return false;
    
    for (int i = 0; i < bytes1.length; i++) {
      if (bytes1[i] != bytes2[i]) return false;
    }
    return true;
  }
  
  Future<bool> _compareFilesInChunks(File file1, File file2) async {
    const chunkSize = 64 * 1024; // 64KB 청크
    
    final raf1 = await file1.open();
    final raf2 = await file2.open();
    
    try {
      int position = 0;
      
      while (position < await file1.length()) {
        final chunk1 = await raf1.read(chunkSize);
        final chunk2 = await raf2.read(chunkSize);
        
        if (!_compareBytes(Uint8List.fromList(chunk1), Uint8List.fromList(chunk2))) {
          return false;
        }
        
        position += chunkSize;
      }
      
      return true;
    } finally {
      await raf1.close();
      await raf2.close();
    }
  }
  
  String _detectFileType(Uint8List data) {
    if (data.length < 4) return 'unknown';
    
    // 매직 넘버로 파일 타입 감지
    final header = data.take(4).toList();
    
    if (header[0] == 0xFF && header[1] == 0xD8) return 'jpeg';
    if (header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47) return 'png';
    if (header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46) return 'wav';
    if (header[0] == 0x1F && header[1] == 0x8B) return 'gzip';
    
    return 'unknown';
  }
  
  bool _isAlreadyCompressed(String fileType) {
    const compressedTypes = ['jpeg', 'png', 'mp3', 'mp4', 'zip', 'gzip'];
    return compressedTypes.contains(fileType);
  }
  
  Future<Uint8List> _performCompression(Uint8List data) async {
    // 실제 구현에서는 적절한 압축 라이브러리 사용
    await Future.delayed(Duration(milliseconds: data.length ~/ 10000)); // 시뮬레이션
    return data; // 임시로 원본 반환
  }
  
  int _getMemoryUsage() {
    // 실제 구현에서는 메모리 사용량 측정
    return 0;
  }
  
  static void _isolateFileProcessor(IsolateMessage message) {
    try {
      // 파일 처리 로직 (격리된 환경에서 실행)
      switch (message.operation) {
        case 'hash':
          _calculateFileHash(message.filePath);
          break;
        case 'compress':
          _compressFile(message.filePath, message.parameters);
          break;
        case 'convert':
          _convertFile(message.filePath, message.parameters);
          break;
      }
      
      message.sendPort.send({'success': true});
    } catch (e) {
      message.sendPort.send({'error': e.toString()});
    }
  }
  
  static void _calculateFileHash(String filePath) {
    // 파일 해시 계산
  }
  
  static void _compressFile(String filePath, Map<String, dynamic> parameters) {
    // 파일 압축
  }
  
  static void _convertFile(String filePath, Map<String, dynamic> parameters) {
    // 파일 변환
  }
}

class TransferTask {
  final String id;
  final TransferType type;
  final String filePath;
  final int totalSize;
  final int chunkSize;
  int transferredSize = 0;
  
  TransferTask({
    required this.id,
    required this.type,
    required this.filePath,
    required this.totalSize,
    required this.chunkSize,
  });
  
  double get progress => transferredSize / totalSize;
}

enum TransferType {
  upload,
  download,
}

class PerformanceMetrics {
  final String operation;
  final List<Duration> _durations = [];
  final List<int> _dataSizes = [];
  
  PerformanceMetrics(this.operation);
  
  void addSample(Duration duration, int dataSize) {
    _durations.add(duration);
    _dataSizes.add(dataSize);
    
    // 최대 100개 샘플만 유지
    if (_durations.length > 100) {
      _durations.removeAt(0);
      _dataSizes.removeAt(0);
    }
  }
  
  Map<String, dynamic> toJson() {
    if (_durations.isEmpty) {
      return {'operation': operation, 'samples': 0};
    }
    
    final avgDuration = _durations.map((d) => d.inMilliseconds).reduce((a, b) => a + b) / _durations.length;
    final avgThroughput = _dataSizes.map((s) => s / 1024 / 1024).reduce((a, b) => a + b) / _dataSizes.length; // MB/s
    
    return {
      'operation': operation,
      'samples': _durations.length,
      'avgDurationMs': avgDuration,
      'avgThroughputMBps': avgThroughput,
    };
  }
}

class IsolateMessage {
  final SendPort sendPort;
  final String filePath;
  final String operation;
  final Map<String, dynamic> parameters;
  
  IsolateMessage({
    required this.sendPort,
    required this.filePath,
    required this.operation,
    required this.parameters,
  });
}
