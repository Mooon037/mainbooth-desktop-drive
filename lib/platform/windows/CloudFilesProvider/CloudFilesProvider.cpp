#include "CloudFilesProvider.h"
#include <iostream>
#include <shlwapi.h>
#include <pathcch.h>
#include <chrono>
#include <locale>
#include <codecvt>

#pragma comment(lib, "cfapi.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "pathcch.lib")

// GUID 정의
const GUID MainBoothDriveProviderId = { 0x12345678, 0x1234, 0x1234, { 0x12, 0x34, 0x12, 0x34, 0x56, 0x78, 0x90, 0x12 } };

// 정적 멤버 초기화
std::unique_ptr<CloudFilesProvider> CloudFilesProvider::s_instance;
std::mutex CloudFilesProvider::s_instanceMutex;

CloudFilesProvider& CloudFilesProvider::GetInstance() {
    std::lock_guard<std::mutex> lock(s_instanceMutex);
    if (!s_instance) {
        s_instance = std::unique_ptr<CloudFilesProvider>(new CloudFilesProvider());
    }
    return *s_instance;
}

HRESULT CloudFilesProvider::Initialize() {
    if (m_initialized) {
        return S_OK;
    }
    
    std::wcout << L"Initializing Main Booth Drive Cloud Files Provider..." << std::endl;
    
    // 워커 스레드 시작
    m_shouldStop = false;
    m_workerThread = std::thread([this]() {
        while (!m_shouldStop) {
            std::unique_lock<std::mutex> lock(m_queueMutex);
            m_queueCondition.wait(lock, [this] { return !m_workQueue.empty() || m_shouldStop; });
            
            while (!m_workQueue.empty() && !m_shouldStop) {
                auto work = m_workQueue.front();
                m_workQueue.pop();
                lock.unlock();
                
                work();
                
                lock.lock();
            }
        }
    });
    
    m_initialized = true;
    std::wcout << L"Cloud Files Provider initialized successfully" << std::endl;
    
    return S_OK;
}

void CloudFilesProvider::Shutdown() {
    if (!m_initialized) {
        return;
    }
    
    std::wcout << L"Shutting down Cloud Files Provider..." << std::endl;
    
    // 워커 스레드 정지
    {
        std::lock_guard<std::mutex> lock(m_queueMutex);
        m_shouldStop = true;
    }
    m_queueCondition.notify_all();
    
    if (m_workerThread.joinable()) {
        m_workerThread.join();
    }
    
    // 연결 해제
    if (m_connectionKey != CF_CONNECTION_KEY_INVALID) {
        CfDisconnectSyncRoot(m_connectionKey);
        m_connectionKey = CF_CONNECTION_KEY_INVALID;
    }
    
    m_initialized = false;
    std::wcout << L"Cloud Files Provider shut down" << std::endl;
}

HRESULT CloudFilesProvider::RegisterSyncRoot(const std::wstring& syncRootPath, const std::wstring& displayName) {
    std::wcout << L"Registering sync root: " << syncRootPath << std::endl;
    
    m_syncRootPath = syncRootPath;
    
    // 디렉토리 생성
    if (!CreateDirectoryW(syncRootPath.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) {
        DWORD error = GetLastError();
        std::wcout << L"Failed to create sync root directory: " << error << std::endl;
        return HRESULT_FROM_WIN32(error);
    }
    
    // 동기화 등록 구조체 생성
    CF_SYNC_REGISTRATION registration = {};
    HRESULT hr = CreateSyncRegistration(displayName, registration);
    if (FAILED(hr)) {
        return hr;
    }
    
    // 동기화 루트 등록
    hr = CfRegisterSyncRoot(syncRootPath.c_str(), &registration, nullptr, CF_REGISTER_FLAG_NONE);
    if (FAILED(hr)) {
        std::wcout << L"Failed to register sync root: 0x" << std::hex << hr << std::endl;
        return hr;
    }
    
    // 콜백 등록
    CF_CALLBACK_REGISTRATION callbackTable[] = {
        { CF_CALLBACK_TYPE_FETCH_DATA, OnFetchData },
        { CF_CALLBACK_TYPE_VALIDATE_DATA, OnValidateData },
        { CF_CALLBACK_TYPE_CANCEL_FETCH_DATA, OnCancelFetchData },
        { CF_CALLBACK_TYPE_NOTIFY_FILE_OPEN_COMPLETION, OnNotifyFileOpenCompletion },
        { CF_CALLBACK_TYPE_NOTIFY_FILE_CLOSE_COMPLETION, OnNotifyFileCloseCompletion },
        { CF_CALLBACK_TYPE_NOTIFY_DEHYDRATE, OnNotifyDehydrate },
        { CF_CALLBACK_TYPE_NOTIFY_DEHYDRATE_COMPLETION, OnNotifyDehydrateCompletion },
        { CF_CALLBACK_TYPE_NOTIFY_DELETE, OnNotifyDelete },
        { CF_CALLBACK_TYPE_NOTIFY_DELETE_COMPLETION, OnNotifyDeleteCompletion },
        { CF_CALLBACK_TYPE_NOTIFY_RENAME, OnNotifyRename },
        { CF_CALLBACK_TYPE_NOTIFY_RENAME_COMPLETION, OnNotifyRenameCompletion },
        CF_CALLBACK_REGISTRATION_END
    };
    
    hr = CfConnectSyncRoot(syncRootPath.c_str(), callbackTable, this, CF_CONNECT_FLAG_REQUIRE_PROCESS_INFO | CF_CONNECT_FLAG_REQUIRE_FULL_FILE_PATH, &m_connectionKey);
    if (FAILED(hr)) {
        std::wcout << L"Failed to connect sync root: 0x" << std::hex << hr << std::endl;
        CfUnregisterSyncRoot(syncRootPath.c_str());
        return hr;
    }
    
    std::wcout << L"Sync root registered successfully" << std::endl;
    return S_OK;
}

HRESULT CloudFilesProvider::UnregisterSyncRoot(const std::wstring& syncRootPath) {
    std::wcout << L"Unregistering sync root: " << syncRootPath << std::endl;
    
    if (m_connectionKey != CF_CONNECTION_KEY_INVALID) {
        CfDisconnectSyncRoot(m_connectionKey);
        m_connectionKey = CF_CONNECTION_KEY_INVALID;
    }
    
    HRESULT hr = CfUnregisterSyncRoot(syncRootPath.c_str());
    if (FAILED(hr)) {
        std::wcout << L"Failed to unregister sync root: 0x" << std::hex << hr << std::endl;
    }
    
    return hr;
}

HRESULT CloudFilesProvider::CreatePlaceholder(const std::wstring& relativePath, const FILE_BASIC_INFO& basicInfo, LARGE_INTEGER fileSize) {
    std::wcout << L"Creating placeholder: " << relativePath << std::endl;
    
    CF_PLACEHOLDER_CREATE_INFO placeholderInfo = {};
    HRESULT hr = CreatePlaceholderInfo(relativePath, basicInfo, fileSize, placeholderInfo);
    if (FAILED(hr)) {
        return hr;
    }
    
    hr = CfCreatePlaceholders(m_syncRootPath.c_str(), &placeholderInfo, 1, CF_CREATE_FLAG_NONE, nullptr);
    if (FAILED(hr)) {
        std::wcout << L"Failed to create placeholder: 0x" << std::hex << hr << std::endl;
    }
    
    // 메모리 정리
    if (placeholderInfo.RelativeFileName) {
        HeapFree(GetProcessHeap(), 0, (LPVOID)placeholderInfo.RelativeFileName);
    }
    if (placeholderInfo.FileIdentity) {
        HeapFree(GetProcessHeap(), 0, placeholderInfo.FileIdentity);
    }
    
    return hr;
}

HRESULT CloudFilesProvider::HydrateFile(const std::wstring& relativePath, const std::vector<BYTE>& data, std::function<void(double)> progressCallback) {
    std::wcout << L"Hydrating file: " << relativePath << std::endl;
    
    std::wstring fullPath = GetFullPath(relativePath);
    HANDLE fileHandle = GetFileHandle(relativePath);
    
    if (fileHandle == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        std::wcout << L"Failed to get file handle: " << error << std::endl;
        return HRESULT_FROM_WIN32(error);
    }
    
    CF_OPERATION_INFO opInfo = {};
    CF_OPERATION_PARAMETERS opParams = {};
    
    opInfo.StructSize = sizeof(CF_OPERATION_INFO);
    opInfo.Type = CF_OPERATION_TYPE_TRANSFER_DATA;
    opInfo.ConnectionKey = m_connectionKey;
    opInfo.TransferKey = CF_TRANSFER_KEY_INVALID; // 실제 구현에서는 적절한 키 사용
    
    opParams.ParamSize = sizeof(CF_OPERATION_PARAMETERS);
    opParams.TransferData.CompletionStatus = STATUS_SUCCESS;
    opParams.TransferData.Buffer = const_cast<BYTE*>(data.data());
    opParams.TransferData.Length = static_cast<DWORD>(data.size());
    opParams.TransferData.Offset.QuadPart = 0;
    
    HRESULT hr = CfExecute(&opInfo, &opParams);
    if (FAILED(hr)) {
        std::wcout << L"Failed to transfer data: 0x" << std::hex << hr << std::endl;
    }
    
    CloseHandle(fileHandle);
    
    if (progressCallback) {
        progressCallback(1.0); // 완료
    }
    
    return hr;
}

HRESULT CloudFilesProvider::SetInSyncState(const std::wstring& relativePath, CF_IN_SYNC_STATE state) {
    HANDLE fileHandle = GetFileHandle(relativePath);
    if (fileHandle == INVALID_HANDLE_VALUE) {
        return HRESULT_FROM_WIN32(GetLastError());
    }
    
    HRESULT hr = CfSetInSyncState(fileHandle, state, CF_SET_IN_SYNC_FLAG_NONE, nullptr);
    CloseHandle(fileHandle);
    
    return hr;
}

HRESULT CloudFilesProvider::SetPinState(const std::wstring& relativePath, CF_PIN_STATE pinState) {
    HANDLE fileHandle = GetFileHandle(relativePath);
    if (fileHandle == INVALID_HANDLE_VALUE) {
        return HRESULT_FROM_WIN32(GetLastError());
    }
    
    HRESULT hr = CfSetPinState(fileHandle, pinState, CF_SET_PIN_FLAG_NONE, nullptr);
    CloseHandle(fileHandle);
    
    return hr;
}

void CloudFilesProvider::SetFetchDataCallback(std::function<std::vector<BYTE>(const std::wstring&)> callback) {
    m_fetchDataCallback = callback;
}

void CloudFilesProvider::SetNotifyCallback(std::function<void(const std::wstring&, const std::wstring&)> callback) {
    m_notifyCallback = callback;
}

// 콜백 함수 구현
void CALLBACK CloudFilesProvider::OnFetchData(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters) {
    CloudFilesProvider* provider = static_cast<CloudFilesProvider*>(CallbackInfo->CallbackContext);
    
    std::wstring relativePath = CallbackInfo->NormalizedPath;
    std::wcout << L"Fetch data requested for: " << relativePath << std::endl;
    
    if (provider->m_fetchDataCallback) {
        // 비동기 작업으로 큐에 추가
        {
            std::lock_guard<std::mutex> lock(provider->m_queueMutex);
            provider->m_workQueue.push([provider, relativePath, transferKey = CallbackParameters->FetchData.RequiredFileOffset]() {
                std::vector<BYTE> data = provider->m_fetchDataCallback(relativePath);
                
                // 데이터 전송
                CF_OPERATION_INFO opInfo = {};
                CF_OPERATION_PARAMETERS opParams = {};
                
                opInfo.StructSize = sizeof(CF_OPERATION_INFO);
                opInfo.Type = CF_OPERATION_TYPE_TRANSFER_DATA;
                opInfo.ConnectionKey = provider->m_connectionKey;
                opInfo.TransferKey = transferKey;
                
                opParams.ParamSize = sizeof(CF_OPERATION_PARAMETERS);
                opParams.TransferData.CompletionStatus = STATUS_SUCCESS;
                opParams.TransferData.Buffer = data.data();
                opParams.TransferData.Length = static_cast<DWORD>(data.size());
                opParams.TransferData.Offset.QuadPart = 0;
                
                HRESULT hr = CfExecute(&opInfo, &opParams);
                if (FAILED(hr)) {
                    std::wcout << L"Failed to transfer data in callback: 0x" << std::hex << hr << std::endl;
                }
            });
        }
        provider->m_queueCondition.notify_one();
    }
}

void CALLBACK CloudFilesProvider::OnValidateData(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters) {
    std::wcout << L"Validate data for: " << CallbackInfo->NormalizedPath << std::endl;
    
    CF_OPERATION_INFO opInfo = {};
    CF_OPERATION_PARAMETERS opParams = {};
    
    opInfo.StructSize = sizeof(CF_OPERATION_INFO);
    opInfo.Type = CF_OPERATION_TYPE_ACK_DATA;
    opInfo.ConnectionKey = CallbackInfo->ConnectionKey;
    opInfo.TransferKey = CallbackParameters->ValidateData.RequiredFileOffset;
    
    opParams.ParamSize = sizeof(CF_OPERATION_PARAMETERS);
    opParams.AckData.CompletionStatus = STATUS_SUCCESS;
    opParams.AckData.Offset = CallbackParameters->ValidateData.RequiredFileOffset;
    opParams.AckData.Length = CallbackParameters->ValidateData.RequiredLength;
    
    CfExecute(&opInfo, &opParams);
}

void CALLBACK CloudFilesProvider::OnCancelFetchData(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters) {
    std::wcout << L"Cancel fetch data for: " << CallbackInfo->NormalizedPath << std::endl;
    // 진행 중인 다운로드 취소 로직 구현
}

void CALLBACK CloudFilesProvider::OnNotifyFileOpenCompletion(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters) {
    CloudFilesProvider* provider = static_cast<CloudFilesProvider*>(CallbackInfo->CallbackContext);
    if (provider->m_notifyCallback) {
        provider->m_notifyCallback(CallbackInfo->NormalizedPath, L"file_opened");
    }
}

void CALLBACK CloudFilesProvider::OnNotifyFileCloseCompletion(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters) {
    CloudFilesProvider* provider = static_cast<CloudFilesProvider*>(CallbackInfo->CallbackContext);
    if (provider->m_notifyCallback) {
        provider->m_notifyCallback(CallbackInfo->NormalizedPath, L"file_closed");
    }
}

void CALLBACK CloudFilesProvider::OnNotifyDehydrate(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters) {
    std::wcout << L"Dehydrate notification for: " << CallbackInfo->NormalizedPath << std::endl;
}

void CALLBACK CloudFilesProvider::OnNotifyDehydrateCompletion(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters) {
    std::wcout << L"Dehydrate completion for: " << CallbackInfo->NormalizedPath << std::endl;
}

void CALLBACK CloudFilesProvider::OnNotifyDelete(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters) {
    CloudFilesProvider* provider = static_cast<CloudFilesProvider*>(CallbackInfo->CallbackContext);
    if (provider->m_notifyCallback) {
        provider->m_notifyCallback(CallbackInfo->NormalizedPath, L"file_deleted");
    }
}

void CALLBACK CloudFilesProvider::OnNotifyDeleteCompletion(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters) {
    std::wcout << L"Delete completion for: " << CallbackInfo->NormalizedPath << std::endl;
}

void CALLBACK CloudFilesProvider::OnNotifyRename(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters) {
    CloudFilesProvider* provider = static_cast<CloudFilesProvider*>(CallbackInfo->CallbackContext);
    if (provider->m_notifyCallback) {
        provider->m_notifyCallback(CallbackInfo->NormalizedPath, L"file_renamed");
    }
}

void CALLBACK CloudFilesProvider::OnNotifyRenameCompletion(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters) {
    std::wcout << L"Rename completion for: " << CallbackInfo->NormalizedPath << std::endl;
}

// 헬퍼 메서드 구현
HRESULT CloudFilesProvider::CreateSyncRegistration(const std::wstring& displayName, CF_SYNC_REGISTRATION& registration) {
    ZeroMemory(&registration, sizeof(registration));
    
    registration.StructSize = sizeof(CF_SYNC_REGISTRATION);
    registration.ProviderId = &MainBoothDriveProviderId;
    registration.ProviderName = displayName.c_str();
    registration.ProviderVersion = L"1.0.0";
    
    // 동기화 정책 설정
    CF_SYNC_POLICIES policies = {};
    policies.StructSize = sizeof(CF_SYNC_POLICIES);
    policies.Hydration.Primary = CF_HYDRATION_POLICY_FULL;
    policies.Population.Primary = CF_POPULATION_POLICY_ALWAYS_FULL;
    policies.InSync = CF_INSYNC_POLICY_TRACK_ALL;
    policies.HardLink = CF_HARDLINK_POLICY_NONE;
    policies.PlaceholderManagement = CF_PLACEHOLDER_MANAGEMENT_POLICY_DEFAULT;
    
    registration.SyncPolicies = &policies;
    
    return S_OK;
}

HRESULT CloudFilesProvider::CreatePlaceholderInfo(const std::wstring& relativePath, const FILE_BASIC_INFO& basicInfo, LARGE_INTEGER fileSize, CF_PLACEHOLDER_CREATE_INFO& placeholderInfo) {
    ZeroMemory(&placeholderInfo, sizeof(placeholderInfo));
    
    // 파일명 복사
    size_t pathLength = (relativePath.length() + 1) * sizeof(WCHAR);
    LPWSTR fileName = static_cast<LPWSTR>(HeapAlloc(GetProcessHeap(), 0, pathLength));
    if (!fileName) {
        return E_OUTOFMEMORY;
    }
    wcscpy_s(fileName, relativePath.length() + 1, relativePath.c_str());
    
    // 파일 ID 생성 (간단한 해시 사용)
    std::hash<std::wstring> hasher;
    size_t hashValue = hasher(relativePath);
    
    BYTE* fileIdentity = static_cast<BYTE*>(HeapAlloc(GetProcessHeap(), 0, sizeof(size_t)));
    if (!fileIdentity) {
        HeapFree(GetProcessHeap(), 0, fileName);
        return E_OUTOFMEMORY;
    }
    memcpy(fileIdentity, &hashValue, sizeof(size_t));
    
    // 플레이스홀더 정보 설정
    placeholderInfo.RelativeFileName = fileName;
    placeholderInfo.FileIdentity = fileIdentity;
    placeholderInfo.FileIdentityLength = sizeof(size_t);
    
    // 파일 시스템 메타데이터 설정
    CF_FS_METADATA fsMetadata = {};
    fsMetadata.FileSize = fileSize;
    fsMetadata.BasicInfo = basicInfo;
    
    placeholderInfo.FsMetadata = &fsMetadata;
    
    return S_OK;
}

std::wstring CloudFilesProvider::GetFullPath(const std::wstring& relativePath) {
    return m_syncRootPath + L"\\" + relativePath;
}

HANDLE CloudFilesProvider::GetFileHandle(const std::wstring& relativePath) {
    std::wstring fullPath = GetFullPath(relativePath);
    return CreateFileW(
        fullPath.c_str(),
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr
    );
}

// 헬퍼 함수 구현
std::wstring GetMainBoothDriveFolder() {
    WCHAR userProfile[MAX_PATH];
    if (GetEnvironmentVariableW(L"USERPROFILE", userProfile, MAX_PATH) == 0) {
        return L"";
    }
    
    return std::wstring(userProfile) + L"\\Main Booth Drive";
}

std::string WStringToString(const std::wstring& wstr) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
    return converter.to_bytes(wstr);
}

std::wstring StringToWString(const std::string& str) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
    return converter.from_bytes(str);
}

FILETIME DateTimeToFileTime(const std::chrono::system_clock::time_point& timePoint) {
    auto duration = timePoint.time_since_epoch();
    auto nanoseconds = std::chrono::duration_cast<std::chrono::nanoseconds>(duration).count();
    
    // Windows FILETIME은 1601년 1월 1일부터의 100나노초 단위
    const int64_t EPOCH_DIFFERENCE = 11644473600000000000LL; // 100나노초 단위
    int64_t fileTime = (nanoseconds / 100) + EPOCH_DIFFERENCE;
    
    FILETIME ft;
    ft.dwLowDateTime = static_cast<DWORD>(fileTime & 0xFFFFFFFF);
    ft.dwHighDateTime = static_cast<DWORD>(fileTime >> 32);
    
    return ft;
}

std::chrono::system_clock::time_point FileTimeToDateTime(const FILETIME& fileTime) {
    int64_t ft = (static_cast<int64_t>(fileTime.dwHighDateTime) << 32) | fileTime.dwLowDateTime;
    
    const int64_t EPOCH_DIFFERENCE = 11644473600000000000LL;
    int64_t nanoseconds = (ft - EPOCH_DIFFERENCE) * 100;
    
    return std::chrono::system_clock::time_point(std::chrono::nanoseconds(nanoseconds));
}
