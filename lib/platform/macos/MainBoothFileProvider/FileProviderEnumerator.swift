import FileProvider
import os.log

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    
    private let enumeratedItemIdentifier: NSFileProviderItemIdentifier
    private let firebaseManager: FirebaseManager
    private let logger = Logger(subsystem: "com.mainbooth.drive.fileprovider", category: "FileProviderEnumerator")
    
    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier, firebaseManager: FirebaseManager) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        self.firebaseManager = firebaseManager
        super.init()
    }
    
    func invalidate() {
        logger.debug("Enumerator invalidated for: \(enumeratedItemIdentifier.rawValue)")
    }
    
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        logger.debug("Enumerating items for: \(enumeratedItemIdentifier.rawValue)")
        
        if enumeratedItemIdentifier == .rootContainer {
            enumerateRootItems(for: observer, startingAt: page)
        } else {
            enumerateContainerItems(for: observer, startingAt: page)
        }
    }
    
    private func enumerateRootItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        logger.info("Enumerating root items")
        
        firebaseManager.getProjects { [weak self] result in
            switch result {
            case .success(let projects):
                let items = projects.map { projectData in
                    FileProviderItem(
                        identifier: NSFileProviderItemIdentifier(projectData["id"] as! String),
                        filename: projectData["name"] as! String,
                        contentType: .folder,
                        parentIdentifier: .rootContainer
                    )
                }
                
                self?.logger.info("Found \(items.count) projects")
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
                
            case .failure(let error):
                self?.logger.error("Failed to enumerate projects: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }
    
    private func enumerateContainerItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        logger.info("Enumerating container items for: \(enumeratedItemIdentifier.rawValue)")
        
        let projectId = enumeratedItemIdentifier.rawValue
        
        // 프로젝트 내 폴더 구조 생성
        if isProjectRoot(projectId) {
            enumerateProjectFolders(for: observer, projectId: projectId)
        } else {
            enumerateProjectContent(for: observer, projectId: projectId)
        }
    }
    
    private func isProjectRoot(_ projectId: String) -> Bool {
        // 프로젝트 루트인지 확인 (UUID 형태인지 체크)
        return UUID(uuidString: projectId) != nil
    }
    
    private func enumerateProjectFolders(for observer: NSFileProviderEnumerationObserver, projectId: String) {
        logger.info("Enumerating project folders for: \(projectId)")
        
        let folders = ["Tracks", "References", "WorkRequests"]
        let items = folders.map { folderName in
            FileProviderItem(
                identifier: NSFileProviderItemIdentifier("\(projectId)/\(folderName)"),
                filename: folderName,
                contentType: .folder,
                parentIdentifier: NSFileProviderItemIdentifier(projectId)
            )
        }
        
        observer.didEnumerate(items)
        observer.finishEnumerating(upTo: nil)
    }
    
    private func enumerateProjectContent(for observer: NSFileProviderEnumerationObserver, projectId: String) {
        let pathComponents = enumeratedItemIdentifier.rawValue.split(separator: "/")
        guard pathComponents.count >= 2 else {
            observer.finishEnumeratingWithError(NSFileProviderError(.noSuchItem))
            return
        }
        
        let actualProjectId = String(pathComponents[0])
        let folderType = String(pathComponents[1])
        
        logger.info("Enumerating \(folderType) for project: \(actualProjectId)")
        
        switch folderType {
        case "Tracks":
            enumerateTracks(for: observer, projectId: actualProjectId)
        case "References":
            enumerateReferences(for: observer, projectId: actualProjectId)
        case "WorkRequests":
            enumerateWorkRequests(for: observer, projectId: actualProjectId)
        default:
            observer.finishEnumeratingWithError(NSFileProviderError(.noSuchItem))
        }
    }
    
    private func enumerateTracks(for observer: NSFileProviderEnumerationObserver, projectId: String) {
        firebaseManager.getTracks(for: projectId) { [weak self] result in
            switch result {
            case .success(let tracks):
                let items = tracks.map { trackData -> FileProviderItem in
                    let identifier = NSFileProviderItemIdentifier("\(projectId)/Tracks/\(trackData["id"] as! String)")
                    let item = FileProviderItem(from: trackData, identifier: identifier)
                    item.projectId = projectId
                    return item
                }
                
                self?.logger.info("Found \(items.count) tracks")
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
                
            case .failure(let error):
                self?.logger.error("Failed to enumerate tracks: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }
    
    private func enumerateReferences(for observer: NSFileProviderEnumerationObserver, projectId: String) {
        firebaseManager.getReferences(for: projectId) { [weak self] result in
            switch result {
            case .success(let references):
                let items = references.map { refData -> FileProviderItem in
                    let identifier = NSFileProviderItemIdentifier("\(projectId)/References/\(refData["id"] as! String)")
                    let item = FileProviderItem(from: refData, identifier: identifier)
                    item.projectId = projectId
                    return item
                }
                
                self?.logger.info("Found \(items.count) references")
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
                
            case .failure(let error):
                self?.logger.error("Failed to enumerate references: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }
    
    private func enumerateWorkRequests(for observer: NSFileProviderEnumerationObserver, projectId: String) {
        firebaseManager.getWorkRequests(for: projectId) { [weak self] result in
            switch result {
            case .success(let workRequests):
                let items = workRequests.map { requestData -> FileProviderItem in
                    let identifier = NSFileProviderItemIdentifier("\(projectId)/WorkRequests/\(requestData["id"] as! String)")
                    let item = FileProviderItem(from: requestData, identifier: identifier)
                    item.projectId = projectId
                    return item
                }
                
                self?.logger.info("Found \(items.count) work requests")
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
                
            case .failure(let error):
                self?.logger.error("Failed to enumerate work requests: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        logger.debug("Enumerating changes from anchor: \(anchor.rawValue)")
        
        // Firebase에서 변경사항 가져오기
        firebaseManager.getChanges(from: anchor, for: enumeratedItemIdentifier) { [weak self] result in
            switch result {
            case .success(let changes):
                self?.logger.info("Found \(changes.updatedItems.count) updated items and \(changes.deletedItemIdentifiers.count) deleted items")
                
                observer.didUpdate(changes.updatedItems)
                observer.didDeleteItems(withIdentifiers: changes.deletedItemIdentifiers)
                observer.finishEnumeratingChanges(upTo: changes.nextAnchor, moreComing: false)
                
            case .failure(let error):
                self?.logger.error("Failed to enumerate changes: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
            }
        }
    }
    
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        logger.debug("Getting current sync anchor for: \(enumeratedItemIdentifier.rawValue)")
        
        firebaseManager.getCurrentSyncAnchor(for: enumeratedItemIdentifier) { result in
            switch result {
            case .success(let anchor):
                completionHandler(anchor)
            case .failure:
                completionHandler(nil)
            }
        }
    }
}
