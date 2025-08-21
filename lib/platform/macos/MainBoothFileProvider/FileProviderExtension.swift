import FileProvider
import UniformTypeIdentifiers
import os.log

@objc(FileProviderExtension)
class FileProviderExtension: NSFileProviderExtension {
    
    private let logger = Logger(subsystem: "com.mainbooth.drive.fileprovider", category: "FileProviderExtension")
    private let firebaseManager = FirebaseManager.shared
    
    override init() {
        super.init()
        logger.info("FileProviderExtension initialized")
    }
    
    override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
        logger.debug("Requesting item for identifier: \(identifier.rawValue)")
        
        if identifier == .rootContainer {
            return FileProviderItem(
                identifier: .rootContainer,
                filename: "Main Booth Drive",
                contentType: .folder,
                parentIdentifier: .rootContainer
            )
        }
        
        // Firebase에서 아이템 정보 가져오기
        guard let item = firebaseManager.getItem(for: identifier) else {
            logger.error("Item not found for identifier: \(identifier.rawValue)")
            throw NSFileProviderError(.noSuchItem)
        }
        
        return item
    }
    
    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        logger.debug("URL requested for identifier: \(identifier.rawValue)")
        
        guard let item = try? self.item(for: identifier) else {
            return nil
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let itemURL = documentsPath.appendingPathComponent("MainBoothDrive").appendingPathComponent(item.filename)
        
        return itemURL
    }
    
    override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
        logger.debug("Persistent identifier requested for URL: \(url.path)")
        
        let pathComponents = url.pathComponents
        if pathComponents.contains("MainBoothDrive") {
            let filename = url.lastPathComponent
            return NSFileProviderItemIdentifier(filename)
        }
        
        return nil
    }
    
    override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        logger.info("Providing placeholder at: \(url.path)")
        
        guard let identifier = persistentIdentifierForItem(at: url) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        
        do {
            let fileProviderItem = try item(for: identifier)
            let placeholderURL = NSFileProviderManager.placeholderURL(for: url)
            
            try NSFileProviderManager.writePlaceholder(
                at: placeholderURL,
                withMetadata: fileProviderItem
            )
            
            completionHandler(nil)
        } catch {
            logger.error("Failed to provide placeholder: \(error.localizedDescription)")
            completionHandler(error)
        }
    }
    
    override func startProvidingItem(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        logger.info("Start providing item at: \(url.path)")
        
        guard let identifier = persistentIdentifierForItem(at: url) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        
        // Firebase Storage에서 파일 다운로드
        firebaseManager.downloadFile(for: identifier) { [weak self] result in
            switch result {
            case .success(let localURL):
                do {
                    // 파일을 요청된 위치로 복사
                    try FileManager.default.copyItem(at: localURL, to: url)
                    self?.logger.info("Successfully provided item at: \(url.path)")
                    completionHandler(nil)
                } catch {
                    self?.logger.error("Failed to copy file: \(error.localizedDescription)")
                    completionHandler(error)
                }
                
            case .failure(let error):
                self?.logger.error("Failed to download file: \(error.localizedDescription)")
                completionHandler(error)
            }
        }
    }
    
    override func itemChanged(at url: URL) {
        logger.info("Item changed at: \(url.path)")
        
        guard let identifier = persistentIdentifierForItem(at: url) else {
            return
        }
        
        // Firebase에 파일 업로드
        firebaseManager.uploadFile(at: url, for: identifier) { [weak self] result in
            switch result {
            case .success:
                self?.logger.info("Successfully uploaded changed item")
                
            case .failure(let error):
                self?.logger.error("Failed to upload changed item: \(error.localizedDescription)")
            }
        }
    }
    
    override func stopProvidingItem(at url: URL) {
        logger.info("Stop providing item at: \(url.path)")
        
        // 로컬 캐시에서 파일 제거
        do {
            try FileManager.default.removeItem(at: url)
            
            // placeholder로 대체
            let placeholderURL = NSFileProviderManager.placeholderURL(for: url)
            if let identifier = persistentIdentifierForItem(at: url) {
                let fileProviderItem = try item(for: identifier)
                try NSFileProviderManager.writePlaceholder(
                    at: placeholderURL,
                    withMetadata: fileProviderItem
                )
            }
        } catch {
            logger.error("Failed to stop providing item: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Enumeration
    
    override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
        logger.debug("Creating enumerator for container: \(containerItemIdentifier.rawValue)")
        
        return FileProviderEnumerator(
            enumeratedItemIdentifier: containerItemIdentifier,
            firebaseManager: firebaseManager
        )
    }
}

// MARK: - Actions

extension FileProviderExtension {
    
    override func createItem(basedOn itemTemplate: NSFileProviderItem, 
                           fields: NSFileProviderItemFields, 
                           contents url: URL?, 
                           options: NSFileProviderCreateItemOptions = [], 
                           request: NSFileProviderRequest = NSFileProviderRequest(), 
                           completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) {
        
        logger.info("Creating item: \(itemTemplate.filename)")
        
        let newItem = FileProviderItem(
            identifier: NSFileProviderItemIdentifier(UUID().uuidString),
            filename: itemTemplate.filename,
            contentType: itemTemplate.contentType ?? .data,
            parentIdentifier: itemTemplate.parentItemIdentifier
        )
        
        // Firebase에 업로드
        if let fileURL = url {
            firebaseManager.uploadFile(at: fileURL, for: newItem.itemIdentifier) { [weak self] result in
                switch result {
                case .success:
                    self?.logger.info("Successfully created and uploaded item")
                    completionHandler(newItem, [], false, nil)
                    
                case .failure(let error):
                    self?.logger.error("Failed to upload new item: \(error.localizedDescription)")
                    completionHandler(nil, [], false, error)
                }
            }
        } else {
            // 폴더 생성
            firebaseManager.createFolder(item: newItem) { [weak self] result in
                switch result {
                case .success:
                    self?.logger.info("Successfully created folder")
                    completionHandler(newItem, [], false, nil)
                    
                case .failure(let error):
                    self?.logger.error("Failed to create folder: \(error.localizedDescription)")
                    completionHandler(nil, [], false, error)
                }
            }
        }
    }
    
    override func deleteItem(withIdentifier itemIdentifier: NSFileProviderItemIdentifier, 
                           completionHandler: @escaping (Error?) -> Void) {
        
        logger.info("Deleting item: \(itemIdentifier.rawValue)")
        
        firebaseManager.deleteItem(for: itemIdentifier) { [weak self] result in
            switch result {
            case .success:
                self?.logger.info("Successfully deleted item")
                completionHandler(nil)
                
            case .failure(let error):
                self?.logger.error("Failed to delete item: \(error.localizedDescription)")
                completionHandler(error)
            }
        }
    }
    
    override func modifyItem(_ item: NSFileProviderItem, 
                           baseVersion version: NSFileProviderItemVersion, 
                           changedFields: NSFileProviderItemFields, 
                           contents newContents: URL?, 
                           options: NSFileProviderModifyItemOptions = [], 
                           request: NSFileProviderRequest = NSFileProviderRequest(), 
                           completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) {
        
        logger.info("Modifying item: \(item.filename)")
        
        var updatedItem = item
        
        if let newContents = newContents {
            // 파일 내용 업데이트
            firebaseManager.uploadFile(at: newContents, for: item.itemIdentifier) { [weak self] result in
                switch result {
                case .success:
                    self?.logger.info("Successfully modified item contents")
                    completionHandler(updatedItem, [], false, nil)
                    
                case .failure(let error):
                    self?.logger.error("Failed to upload modified item: \(error.localizedDescription)")
                    completionHandler(nil, [], false, error)
                }
            }
        } else {
            // 메타데이터만 업데이트
            firebaseManager.updateMetadata(for: item.itemIdentifier, item: updatedItem) { [weak self] result in
                switch result {
                case .success:
                    self?.logger.info("Successfully modified item metadata")
                    completionHandler(updatedItem, [], false, nil)
                    
                case .failure(let error):
                    self?.logger.error("Failed to update metadata: \(error.localizedDescription)")
                    completionHandler(nil, [], false, error)
                }
            }
        }
    }
}
