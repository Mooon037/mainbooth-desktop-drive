import FileProvider
import UniformTypeIdentifiers

class FileProviderItem: NSObject, NSFileProviderItem {
    
    // MARK: - Required Properties
    
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let contentType: UTType
    
    // MARK: - Optional Properties
    
    var documentSize: NSNumber?
    var childItemCount: NSNumber?
    var creationDate: Date?
    var contentModificationDate: Date?
    var lastUsedDate: Date?
    var tagData: Data?
    var favoriteRank: NSNumber?
    var isDownloaded: Bool = false
    var isDownloading: Bool = false
    var downloadingError: Error?
    var isUploaded: Bool = true
    var isUploading: Bool = false
    var uploadingError: Error?
    var userInfo: [AnyHashable : Any]?
    
    // MARK: - Custom Properties
    
    var projectId: String?
    var trackMetadata: [String: Any]?
    var syncStatus: String = "synced"
    
    // MARK: - Initialization
    
    init(identifier: NSFileProviderItemIdentifier,
         filename: String,
         contentType: UTType,
         parentIdentifier: NSFileProviderItemIdentifier) {
        
        self.itemIdentifier = identifier
        self.filename = filename
        self.contentType = contentType
        self.parentItemIdentifier = parentIdentifier
        
        super.init()
    }
    
    convenience init(from firebaseData: [String: Any], identifier: NSFileProviderItemIdentifier) {
        let filename = firebaseData["name"] as? String ?? "Unknown"
        let isFolder = firebaseData["isFolder"] as? Bool ?? false
        let contentType: UTType = isFolder ? .folder : .data
        let parentId = firebaseData["parentId"] as? String ?? NSFileProviderItemIdentifier.rootContainer.rawValue
        
        self.init(
            identifier: identifier,
            filename: filename,
            contentType: contentType,
            parentIdentifier: NSFileProviderItemIdentifier(parentId)
        )
        
        // Firebase 데이터로부터 속성 설정
        if let size = firebaseData["size"] as? Int {
            self.documentSize = NSNumber(value: size)
        }
        
        if let createdAt = firebaseData["createdAt"] as? TimeInterval {
            self.creationDate = Date(timeIntervalSince1970: createdAt)
        }
        
        if let updatedAt = firebaseData["updatedAt"] as? TimeInterval {
            self.contentModificationDate = Date(timeIntervalSince1970: updatedAt)
        }
        
        self.projectId = firebaseData["projectId"] as? String
        self.trackMetadata = firebaseData["metadata"] as? [String: Any]
        self.syncStatus = firebaseData["syncStatus"] as? String ?? "synced"
        
        // 파일 타입에 따른 contentType 설정
        if let fileExtension = filename.split(separator: ".").last {
            switch String(fileExtension).lowercased() {
            case "wav", "mp3", "m4a", "aac", "flac":
                self.contentType = .audio
            case "jpg", "jpeg", "png", "gif", "webp":
                self.contentType = .image
            case "pdf":
                self.contentType = .pdf
            case "txt", "md":
                self.contentType = .plainText
            case "mov", "mp4", "avi":
                self.contentType = .movie
            default:
                self.contentType = .data
            }
        }
        
        // 다운로드 상태 설정
        self.isDownloaded = firebaseData["isDownloaded"] as? Bool ?? false
        self.isUploaded = firebaseData["isUploaded"] as? Bool ?? true
    }
    
    // MARK: - Capabilities
    
    var capabilities: NSFileProviderItemCapabilities {
        var caps: NSFileProviderItemCapabilities = []
        
        if contentType == .folder {
            caps.insert([.allowsAddingSubItems, .allowsContentEnumerating])
        } else {
            caps.insert([.allowsReading, .allowsWriting])
        }
        
        // 프로젝트 소유자나 관리자만 삭제 가능
        if canDelete {
            caps.insert(.allowsDeleting)
        }
        
        // 이름 변경 허용
        caps.insert(.allowsRenaming)
        
        return caps
    }
    
    private var canDelete: Bool {
        // TODO: Firebase에서 사용자 권한 확인
        return true
    }
    
    // MARK: - Version Information
    
    var itemVersion: NSFileProviderItemVersion {
        let lastModified = contentModificationDate ?? Date()
        let contentVersion = String(lastModified.timeIntervalSince1970)
        let metadataVersion = contentVersion
        
        return NSFileProviderItemVersion(
            contentVersion: contentVersion.data(using: .utf8)!,
            metadataVersion: metadataVersion.data(using: .utf8)!
        )
    }
    
    // MARK: - Sync Status
    
    var mostRecentEditorNameComponents: PersonNameComponents? {
        if let uploaderName = trackMetadata?["uploaderName"] as? String {
            var components = PersonNameComponents()
            components.givenName = uploaderName
            return components
        }
        return nil
    }
    
    var versionIdentifier: Data? {
        return itemVersion.contentVersion
    }
    
    // MARK: - Helper Methods
    
    func updateSyncStatus(_ status: String) {
        syncStatus = status
        
        switch status {
        case "downloading":
            isDownloading = true
            isDownloaded = false
            downloadingError = nil
            
        case "downloaded":
            isDownloading = false
            isDownloaded = true
            downloadingError = nil
            
        case "uploading":
            isUploading = true
            isUploaded = false
            uploadingError = nil
            
        case "uploaded":
            isUploading = false
            isUploaded = true
            uploadingError = nil
            
        case "error":
            isDownloading = false
            isUploading = false
            
        default:
            break
        }
    }
    
    func setError(_ error: Error, for operation: String) {
        switch operation {
        case "download":
            downloadingError = error
            isDownloading = false
            
        case "upload":
            uploadingError = error
            isUploading = false
            
        default:
            break
        }
    }
    
    // MARK: - Description
    
    override var description: String {
        return """
        FileProviderItem {
            identifier: \(itemIdentifier.rawValue)
            filename: \(filename)
            contentType: \(contentType.identifier)
            parent: \(parentItemIdentifier.rawValue)
            size: \(documentSize?.intValue ?? 0)
            downloaded: \(isDownloaded)
            uploaded: \(isUploaded)
            syncStatus: \(syncStatus)
        }
        """
    }
}
