import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import os.log

class FirebaseManager {
    static let shared = FirebaseManager()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let logger = Logger(subsystem: "com.mainbooth.drive.fileprovider", category: "FirebaseManager")
    
    private init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }
    
    // MARK: - Projects
    
    func getProjects(completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }
        
        db.collection("projects")
            .whereField("collaborators", arrayContains: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let projects = snapshot?.documents.compactMap { doc -> [String: Any]? in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return data
                } ?? []
                
                completion(.success(projects))
            }
    }
    
    // MARK: - Tracks
    
    func getTracks(for projectId: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        db.collection("projects").document(projectId).collection("tracks")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let tracks = snapshot?.documents.compactMap { doc -> [String: Any]? in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return data
                } ?? []
                
                completion(.success(tracks))
            }
    }
    
    // MARK: - References
    
    func getReferences(for projectId: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        db.collection("projects").document(projectId).collection("references")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let references = snapshot?.documents.compactMap { doc -> [String: Any]? in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return data
                } ?? []
                
                completion(.success(references))
            }
    }
    
    // MARK: - Work Requests
    
    func getWorkRequests(for projectId: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        db.collection("projects").document(projectId).collection("workRequests")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let workRequests = snapshot?.documents.compactMap { doc -> [String: Any]? in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return data
                } ?? []
                
                completion(.success(workRequests))
            }
    }
    
    // MARK: - Item Management
    
    func getItem(for identifier: NSFileProviderItemIdentifier) -> FileProviderItem? {
        // 캐시에서 아이템 조회 (실제 구현에서는 로컬 캐시 사용)
        // 여기서는 임시로 nil 반환
        return nil
    }
    
    func downloadFile(for identifier: NSFileProviderItemIdentifier, completion: @escaping (Result<URL, Error>) -> Void) {
        let pathComponents = identifier.rawValue.split(separator: "/")
        guard pathComponents.count >= 3 else {
            completion(.failure(NSError(domain: "FirebaseManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid identifier"])))
            return
        }
        
        let projectId = String(pathComponents[0])
        let folderType = String(pathComponents[1])
        let itemId = String(pathComponents[2])
        
        // Firebase Storage에서 파일 다운로드
        let storagePath = "\(folderType.lowercased())/\(projectId)/\(itemId)"
        let storageRef = storage.reference().child(storagePath)
        
        // 로컬 임시 파일 경로
        let tempDir = FileManager.default.temporaryDirectory
        let localURL = tempDir.appendingPathComponent(itemId)
        
        logger.info("Downloading file from: \(storagePath)")
        
        let downloadTask = storageRef.write(toFile: localURL) { url, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let url = url {
                completion(.success(url))
            } else {
                completion(.failure(NSError(domain: "FirebaseManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Download failed"])))
            }
        }
        
        // 진행률 모니터링
        downloadTask.observe(.progress) { snapshot in
            let percentComplete = 100.0 * Double(snapshot.progress!.completedUnitCount) / Double(snapshot.progress!.totalUnitCount)
            self.logger.debug("Download progress: \(percentComplete)%")
        }
    }
    
    func uploadFile(at url: URL, for identifier: NSFileProviderItemIdentifier, completion: @escaping (Result<Void, Error>) -> Void) {
        let pathComponents = identifier.rawValue.split(separator: "/")
        guard pathComponents.count >= 3 else {
            completion(.failure(NSError(domain: "FirebaseManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid identifier"])))
            return
        }
        
        let projectId = String(pathComponents[0])
        let folderType = String(pathComponents[1])
        let itemId = String(pathComponents[2])
        
        // Firebase Storage에 파일 업로드
        let storagePath = "\(folderType.lowercased())/\(projectId)/\(itemId)"
        let storageRef = storage.reference().child(storagePath)
        
        logger.info("Uploading file to: \(storagePath)")
        
        let uploadTask = storageRef.putFile(from: url, metadata: nil) { metadata, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Firestore 메타데이터 업데이트
            self.updateFirestoreMetadata(projectId: projectId, folderType: folderType, itemId: itemId, url: url) { result in
                completion(result)
            }
        }
        
        // 진행률 모니터링
        uploadTask.observe(.progress) { snapshot in
            let percentComplete = 100.0 * Double(snapshot.progress!.completedUnitCount) / Double(snapshot.progress!.totalUnitCount)
            self.logger.debug("Upload progress: \(percentComplete)%")
        }
    }
    
    private func updateFirestoreMetadata(projectId: String, folderType: String, itemId: String, url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let collection = folderType.lowercased()
        let docRef = db.collection("projects").document(projectId).collection(collection).document(itemId)
        
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = fileAttributes?[.size] as? Int64 ?? 0
        
        let metadata: [String: Any] = [
            "name": url.lastPathComponent,
            "size": fileSize,
            "updatedAt": FieldValue.serverTimestamp(),
            "uploaderName": "Desktop User" // TODO: 실제 사용자 이름
        ]
        
        docRef.updateData(metadata) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    func createFolder(item: FileProviderItem, completion: @escaping (Result<Void, Error>) -> Void) {
        // 폴더는 Firestore에만 메타데이터 생성
        let pathComponents = item.itemIdentifier.rawValue.split(separator: "/")
        guard pathComponents.count >= 2 else {
            completion(.failure(NSError(domain: "FirebaseManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid identifier"])))
            return
        }
        
        let projectId = String(pathComponents[0])
        let folderName = item.filename
        
        let metadata: [String: Any] = [
            "name": folderName,
            "isFolder": true,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("projects").document(projectId).collection("folders").addDocument(data: metadata) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    func deleteItem(for identifier: NSFileProviderItemIdentifier, completion: @escaping (Result<Void, Error>) -> Void) {
        let pathComponents = identifier.rawValue.split(separator: "/")
        guard pathComponents.count >= 3 else {
            completion(.failure(NSError(domain: "FirebaseManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid identifier"])))
            return
        }
        
        let projectId = String(pathComponents[0])
        let folderType = String(pathComponents[1])
        let itemId = String(pathComponents[2])
        
        // Firestore에서 삭제
        let collection = folderType.lowercased()
        let docRef = db.collection("projects").document(projectId).collection(collection).document(itemId)
        
        docRef.delete { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Storage에서 파일 삭제
            let storagePath = "\(folderType.lowercased())/\(projectId)/\(itemId)"
            let storageRef = self.storage.reference().child(storagePath)
            
            storageRef.delete { error in
                if let error = error {
                    self.logger.warning("Failed to delete file from storage: \(error.localizedDescription)")
                }
                completion(.success(()))
            }
        }
    }
    
    func updateMetadata(for identifier: NSFileProviderItemIdentifier, item: NSFileProviderItem, completion: @escaping (Result<Void, Error>) -> Void) {
        let pathComponents = identifier.rawValue.split(separator: "/")
        guard pathComponents.count >= 3 else {
            completion(.failure(NSError(domain: "FirebaseManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid identifier"])))
            return
        }
        
        let projectId = String(pathComponents[0])
        let folderType = String(pathComponents[1])
        let itemId = String(pathComponents[2])
        
        let collection = folderType.lowercased()
        let docRef = db.collection("projects").document(projectId).collection(collection).document(itemId)
        
        let metadata: [String: Any] = [
            "name": item.filename,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        docRef.updateData(metadata) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Change Tracking
    
    func getChanges(from anchor: NSFileProviderSyncAnchor, for identifier: NSFileProviderItemIdentifier, completion: @escaping (Result<ChangeSet, Error>) -> Void) {
        // 실제 구현에서는 Firebase의 변경 감지 및 로컬 캐시와 비교
        let changeSet = ChangeSet(updatedItems: [], deletedItemIdentifiers: [], nextAnchor: anchor)
        completion(.success(changeSet))
    }
    
    func getCurrentSyncAnchor(for identifier: NSFileProviderItemIdentifier, completion: @escaping (Result<NSFileProviderSyncAnchor, Error>) -> Void) {
        let anchor = NSFileProviderSyncAnchor(String(Date().timeIntervalSince1970).data(using: .utf8)!)
        completion(.success(anchor))
    }
}

// MARK: - Helper Types

struct ChangeSet {
    let updatedItems: [NSFileProviderItem]
    let deletedItemIdentifiers: [NSFileProviderItemIdentifier]
    let nextAnchor: NSFileProviderSyncAnchor
}
