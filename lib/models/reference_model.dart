/// Main Booth Drive 레퍼런스 모델
/// 프로젝트의 레퍼런스 파일을 관리하는 모델

class DriveReference {
  final String id;
  final String projectId;
  final String name;
  final String fileUrl;
  final String uploaderId;
  final String uploaderName;
  final FileType fileType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String localPath;
  final SyncStatus syncStatus;
  final int? fileSize;
  final String? description;

  DriveReference({
    required this.id,
    required this.projectId,
    required this.name,
    required this.fileUrl,
    required this.uploaderId,
    required this.uploaderName,
    required this.fileType,
    required this.createdAt,
    required this.updatedAt,
    required this.localPath,
    this.syncStatus = SyncStatus.pending,
    this.fileSize,
    this.description,
  });

  /// Firestore 데이터로부터 생성
  factory DriveReference.fromFirestore(
    Map<String, dynamic> data,
    String id,
    String projectId,
    String projectLocalPath,
  ) {
    final fileType = _detectFileType(data['name'] ?? '');
    return DriveReference(
      id: id,
      projectId: projectId,
      name: data['name'] ?? '',
      fileUrl: data['fileUrl'] ?? '',
      uploaderId: data['uploaderId'] ?? '',
      uploaderName: data['uploaderName'] ?? '',
      fileType: fileType,
      createdAt: (data['createdAt'] as dynamic).toDate(),
      updatedAt: (data['updatedAt'] as dynamic).toDate(),
      localPath: '$projectLocalPath/References/${data['name']}',
      fileSize: data['fileSize'],
      description: data['description'],
    );
  }

  static FileType _detectFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'm4a':
      case 'aac':
        return FileType.audio;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return FileType.image;
      case 'pdf':
      case 'doc':
      case 'docx':
      case 'txt':
        return FileType.document;
      case 'mp4':
      case 'mov':
      case 'avi':
        return FileType.video;
      default:
        return FileType.other;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'name': name,
        'fileUrl': fileUrl,
        'uploaderId': uploaderId,
        'uploaderName': uploaderName,
        'fileType': fileType.toString(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'localPath': localPath,
        'syncStatus': syncStatus.toString(),
        'fileSize': fileSize,
        'description': description,
      };
}

/// 레퍼런스 파일 타입
enum FileType {
  audio,
  image,
  document,
  video,
  other,
}

/// 파일 동기화 상태 (track_model에서 import해서 사용)
enum SyncStatus {
  pending,
  synced,
  syncing,
  error,
  conflict,
  uploading,
  downloading,
}
