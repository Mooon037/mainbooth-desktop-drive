#pragma once

#include <windows.h>
#include <cfapi.h>
#include <string>
#include <vector>
#include <memory>
#include <functional>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <queue>

class CloudFilesProvider {
public:
    static CloudFilesProvider& GetInstance();
    
    // 초기화 및 정리
    HRESULT Initialize();
    void Shutdown();
    
    // 동기화 루트 관리
    HRESULT RegisterSyncRoot(const std::wstring& syncRootPath, const std::wstring& displayName);
    HRESULT UnregisterSyncRoot(const std::wstring& syncRootPath);
    
    // 파일 작업
    HRESULT CreatePlaceholder(const std::wstring& relativePath, const FILE_BASIC_INFO& basicInfo, LARGE_INTEGER fileSize);
    HRESULT HydrateFile(const std::wstring& relativePath, const std::vector<BYTE>& data, std::function<void(double)> progressCallback);
    HRESULT UpdateFileMetadata(const std::wstring& relativePath, const FILE_BASIC_INFO& basicInfo);
    HRESULT DeleteFile(const std::wstring& relativePath);
    
    // 동기화 상태 관리
    HRESULT SetInSyncState(const std::wstring& relativePath, CF_IN_SYNC_STATE state);
    HRESULT SetPinState(const std::wstring& relativePath, CF_PIN_STATE pinState);
    
    // 콜백 설정
    void SetFetchDataCallback(std::function<std::vector<BYTE>(const std::wstring&)> callback);
    void SetNotifyCallback(std::function<void(const std::wstring&, const std::wstring&)> callback);

private:
    CloudFilesProvider() = default;
    ~CloudFilesProvider() = default;
    CloudFilesProvider(const CloudFilesProvider&) = delete;
    CloudFilesProvider& operator=(const CloudFilesProvider&) = delete;
    
    // 내부 헬퍼 메서드
    HRESULT CreateSyncRegistration(const std::wstring& displayName, CF_SYNC_REGISTRATION& registration);
    HRESULT CreatePlaceholderInfo(const std::wstring& relativePath, const FILE_BASIC_INFO& basicInfo, 
                                  LARGE_INTEGER fileSize, CF_PLACEHOLDER_CREATE_INFO& placeholderInfo);
    std::wstring GetFullPath(const std::wstring& relativePath);
    HANDLE GetFileHandle(const std::wstring& relativePath);
    
    // 콜백 함수들
    static void CALLBACK OnFetchData(
        const CF_CALLBACK_INFO* CallbackInfo,
        const CF_CALLBACK_PARAMETERS* CallbackParameters
    );
    
    static void CALLBACK OnValidateData(
        const CF_CALLBACK_INFO* CallbackInfo,
        const CF_CALLBACK_PARAMETERS* CallbackParameters
    );
    
    static void CALLBACK OnCancelFetchData(
        const CF_CALLBACK_INFO* CallbackInfo,
        const CF_CALLBACK_PARAMETERS* CallbackParameters
    );
    
    static void CALLBACK OnNotifyFileOpenCompletion(
        const CF_CALLBACK_INFO* CallbackInfo,
        const CF_CALLBACK_PARAMETERS* CallbackParameters
    );
    
    static void CALLBACK OnNotifyFileCloseCompletion(
        const CF_CALLBACK_INFO* CallbackInfo,
        const CF_CALLBACK_PARAMETERS* CallbackParameters
    );
    
    static void CALLBACK OnNotifyDehydrate(
        const CF_CALLBACK_INFO* CallbackInfo,
        const CF_CALLBACK_PARAMETERS* CallbackParameters
    );
    
    static void CALLBACK OnNotifyDehydrateCompletion(
        const CF_CALLBACK_INFO* CallbackInfo,
        const CF_CALLBACK_PARAMETERS* CallbackParameters
    );
    
    static void CALLBACK OnNotifyDelete(
        const CF_CALLBACK_INFO* CallbackInfo,
        const CF_CALLBACK_PARAMETERS* CallbackParameters
    );
    
    static void CALLBACK OnNotifyDeleteCompletion(
        const CF_CALLBACK_INFO* CallbackInfo,
        const CF_CALLBACK_PARAMETERS* CallbackParameters
    );
    
    static void CALLBACK OnNotifyRename(
        const CF_CALLBACK_INFO* CallbackInfo,
        const CF_CALLBACK_PARAMETERS* CallbackParameters
    );
    
    static void CALLBACK OnNotifyRenameCompletion(
        const CF_CALLBACK_INFO* CallbackInfo,
        const CF_CALLBACK_PARAMETERS* CallbackParameters
    );

private:
    bool m_initialized = false;
    std::wstring m_syncRootPath;
    CF_CONNECTION_KEY m_connectionKey = CF_CONNECTION_KEY_INVALID;
    
    // 비동기 작업 관리
    std::thread m_workerThread;
    std::mutex m_queueMutex;
    std::condition_variable m_queueCondition;
    std::queue<std::function<void()>> m_workQueue;
    bool m_shouldStop = false;
    
    // 콜백 함수들
    std::function<std::vector<BYTE>(const std::wstring&)> m_fetchDataCallback;
    std::function<void(const std::wstring&, const std::wstring&)> m_notifyCallback;
    
    // 정적 인스턴스
    static std::unique_ptr<CloudFilesProvider> s_instance;
    static std::mutex s_instanceMutex;
};

// GUID 정의
extern const GUID MainBoothDriveProviderId;

// 헬퍼 함수들
std::wstring GetMainBoothDriveFolder();
std::string WStringToString(const std::wstring& wstr);
std::wstring StringToWString(const std::string& str);
FILETIME DateTimeToFileTime(const std::chrono::system_clock::time_point& timePoint);
std::chrono::system_clock::time_point FileTimeToDateTime(const FILETIME& fileTime);
