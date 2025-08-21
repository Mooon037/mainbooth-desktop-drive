#!/bin/bash
# Main Booth Drive - 자동 빌드 및 배포 스크립트

set -e  # Exit on error

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 설정 변수
PROJECT_NAME="Main Booth Drive"
VERSION="1.0.0"
BUILD_DIR="build"
DIST_DIR="dist"
RELEASE_DIR="releases"

# 플랫폼별 설정
declare -A PLATFORMS=(
    ["macos"]="macos"
    ["windows"]="windows"
    ["linux"]="linux"
)

# 사전 요구사항 확인
check_requirements() {
    log_info "사전 요구사항 확인 중..."
    
    # Flutter 설치 확인
    if ! command -v flutter &> /dev/null; then
        log_error "Flutter가 설치되지 않았습니다."
        exit 1
    fi
    
    # Flutter 상태 확인
    flutter doctor --android-licenses > /dev/null 2>&1 || true
    
    # 필요한 디렉토리 생성
    mkdir -p "$BUILD_DIR" "$DIST_DIR" "$RELEASE_DIR"
    
    log_success "사전 요구사항 확인 완료"
}

# 의존성 설치
install_dependencies() {
    log_info "의존성 설치 중..."
    flutter pub get
    log_success "의존성 설치 완료"
}

# 코드 품질 검사
run_quality_checks() {
    log_info "코드 품질 검사 실행 중..."
    
    # Dart 분석
    flutter analyze || {
        log_error "Dart 분석에서 오류가 발견되었습니다."
        exit 1
    }
    
    # 테스트 실행
    flutter test || {
        log_warning "일부 테스트가 실패했습니다."
    }
    
    log_success "코드 품질 검사 완료"
}

# macOS 빌드
build_macos() {
    log_info "macOS 앱 빌드 중..."
    
    # Release 빌드
    flutter build macos --release
    
    # 앱 번들 복사
    cp -r build/macos/Build/Products/Release/mainbooth_drive.app "$BUILD_DIR/"
    
    # DMG 생성 (macOS에서만 실행)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        create_macos_dmg
    else
        log_warning "macOS가 아니므로 DMG 생성을 건너뜁니다."
    fi
    
    log_success "macOS 빌드 완료"
}

# macOS DMG 생성
create_macos_dmg() {
    log_info "macOS DMG 생성 중..."
    
    local dmg_name="MainBoothDrive-${VERSION}-mac.dmg"
    local dmg_path="$DIST_DIR/$dmg_name"
    local temp_dmg="temp.dmg"
    local app_path="$BUILD_DIR/mainbooth_drive.app"
    
    # 임시 DMG 생성
    hdiutil create -size 200m -fs HFS+ -volname "Main Booth Drive" "$temp_dmg"
    
    # DMG 마운트
    local mount_point=$(hdiutil attach "$temp_dmg" | grep "/Volumes" | awk '{print $3}')
    
    # 앱 복사
    cp -R "$app_path" "$mount_point/"
    
    # Applications 링크 생성
    ln -s /Applications "$mount_point/Applications"
    
    # 배경 이미지 및 뷰 설정 (선택사항)
    if [ -f "assets/dmg-background.png" ]; then
        cp "assets/dmg-background.png" "$mount_point/.background.png"
    fi
    
    # DMG 언마운트
    hdiutil detach "$mount_point"
    
    # 최종 DMG 생성 (압축)
    hdiutil convert "$temp_dmg" -format UDZO -o "$dmg_path"
    
    # 임시 파일 정리
    rm "$temp_dmg"
    
    log_success "DMG 생성 완료: $dmg_path"
}

# Windows 빌드
build_windows() {
    log_info "Windows 앱 빌드 중..."
    
    # Release 빌드
    flutter build windows --release
    
    # 빌드 파일 복사
    cp -r build/windows/runner/Release/* "$BUILD_DIR/windows/"
    
    # Windows 설치 프로그램 생성 (옵션)
    if command -v makensis &> /dev/null; then
        create_windows_installer
    else
        log_warning "NSIS가 설치되지 않아 설치 프로그램 생성을 건너뜁니다."
    fi
    
    log_success "Windows 빌드 완료"
}

# Windows 설치 프로그램 생성
create_windows_installer() {
    log_info "Windows 설치 프로그램 생성 중..."
    
    local nsis_script="scripts/windows_installer.nsi"
    local installer_name="MainBoothDrive-${VERSION}-windows.exe"
    
    # NSIS 스크립트가 존재하는지 확인
    if [ ! -f "$nsis_script" ]; then
        log_warning "NSIS 스크립트를 찾을 수 없습니다: $nsis_script"
        return
    fi
    
    # 설치 프로그램 생성
    makensis "$nsis_script"
    
    # 결과 파일 이동
    if [ -f "setup.exe" ]; then
        mv "setup.exe" "$DIST_DIR/$installer_name"
        log_success "Windows 설치 프로그램 생성 완료: $DIST_DIR/$installer_name"
    fi
}

# Linux 빌드
build_linux() {
    log_info "Linux 앱 빌드 중..."
    
    # Release 빌드
    flutter build linux --release
    
    # 빌드 파일 복사
    mkdir -p "$BUILD_DIR/linux"
    cp -r build/linux/x64/release/bundle/* "$BUILD_DIR/linux/"
    
    # AppImage 생성 (옵션)
    if command -v appimagetool &> /dev/null; then
        create_linux_appimage
    else
        log_warning "appimagetool이 설치되지 않아 AppImage 생성을 건너뜁니다."
    fi
    
    log_success "Linux 빌드 완료"
}

# Linux AppImage 생성
create_linux_appimage() {
    log_info "Linux AppImage 생성 중..."
    
    local appdir="MainBoothDrive.AppDir"
    local appimage_name="MainBoothDrive-${VERSION}-linux.AppImage"
    
    # AppDir 구조 생성
    mkdir -p "$appdir/usr/bin"
    mkdir -p "$appdir/usr/share/applications"
    mkdir -p "$appdir/usr/share/icons/hicolor/256x256/apps"
    
    # 바이너리 복사
    cp -r "$BUILD_DIR/linux/"* "$appdir/usr/bin/"
    
    # Desktop 파일 생성
    cat > "$appdir/usr/share/applications/mainbooth-drive.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Main Booth Drive
Exec=mainbooth_drive
Icon=mainbooth-drive
Comment=음악 협업을 위한 클라우드 드라이브
Categories=AudioVideo;Audio;
EOF
    
    # 아이콘 복사 (있는 경우)
    if [ -f "assets/app-icon.png" ]; then
        cp "assets/app-icon.png" "$appdir/usr/share/icons/hicolor/256x256/apps/mainbooth-drive.png"
    fi
    
    # AppRun 스크립트 생성
    cat > "$appdir/AppRun" << 'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin/:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib/:${LD_LIBRARY_PATH}"
cd "${HERE}/usr/bin"
exec "./mainbooth_drive" "$@"
EOF
    
    chmod +x "$appdir/AppRun"
    
    # AppImage 생성
    appimagetool "$appdir" "$DIST_DIR/$appimage_name"
    
    # 임시 디렉토리 정리
    rm -rf "$appdir"
    
    log_success "AppImage 생성 완료: $DIST_DIR/$appimage_name"
}

# 코드 서명 (macOS)
sign_macos_app() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        return
    fi
    
    if [ -z "$MACOS_DEVELOPER_ID" ]; then
        log_warning "MACOS_DEVELOPER_ID가 설정되지 않아 코드 서명을 건너뜁니다."
        return
    fi
    
    log_info "macOS 앱 코드 서명 중..."
    
    local app_path="$BUILD_DIR/mainbooth_drive.app"
    
    # 코드 서명
    codesign --force --deep --sign "$MACOS_DEVELOPER_ID" "$app_path"
    
    # 서명 확인
    codesign --verify --deep --strict "$app_path"
    
    log_success "macOS 앱 코드 서명 완료"
}

# 공증 (macOS)
notarize_macos_app() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        return
    fi
    
    if [ -z "$APPLE_ID" ] || [ -z "$APPLE_PASSWORD" ] || [ -z "$APPLE_TEAM_ID" ]; then
        log_warning "Apple 공증 정보가 설정되지 않아 공증을 건너뜁니다."
        return
    fi
    
    log_info "macOS 앱 공증 중..."
    
    local dmg_path="$DIST_DIR/MainBoothDrive-${VERSION}-mac.dmg"
    
    if [ ! -f "$dmg_path" ]; then
        log_warning "DMG 파일을 찾을 수 없어 공증을 건너뜁니다."
        return
    fi
    
    # 공증 제출
    local submission_id=$(xcrun notarytool submit "$dmg_path" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait | grep "id:" | awk '{print $2}')
    
    if [ -n "$submission_id" ]; then
        log_success "macOS 앱 공증 완료"
        
        # 공증 결과를 DMG에 스테이플링
        xcrun stapler staple "$dmg_path"
    else
        log_error "macOS 앱 공증 실패"
    fi
}

# 웹사이트 빌드
build_website() {
    log_info "다운로드 웹사이트 빌드 중..."
    
    local web_dist="$DIST_DIR/website"
    mkdir -p "$web_dist"
    
    # 웹 파일 복사
    cp -r web/* "$web_dist/"
    
    # 버전 정보 업데이트
    sed -i.bak "s/v1\.0\.0/v${VERSION}/g" "$web_dist/index.html"
    rm "$web_dist/index.html.bak" 2>/dev/null || true
    
    # 다운로드 링크 업데이트 (GitHub Releases URL)
    local github_repo="mainbooth/desktop-drive"
    sed -i.bak "s|https://github.com/mainbooth/desktop-drive/releases/latest/download/|https://github.com/${github_repo}/releases/download/v${VERSION}/|g" "$web_dist/scripts/main.js"
    rm "$web_dist/scripts/main.js.bak" 2>/dev/null || true
    
    log_success "웹사이트 빌드 완료"
}

# GitHub Release 생성
create_github_release() {
    if [ -z "$GITHUB_TOKEN" ]; then
        log_warning "GITHUB_TOKEN이 설정되지 않아 GitHub Release 생성을 건너뜁니다."
        return
    fi
    
    log_info "GitHub Release 생성 중..."
    
    local tag_name="v${VERSION}"
    local release_name="Main Booth Drive v${VERSION}"
    local release_body="## Main Booth Drive v${VERSION}

### 주요 기능
- macOS Finder 및 Windows Explorer 완벽 통합
- 실시간 파일 동기화
- 모바일 앱과의 완벽한 연동
- 권한 기반 협업 시스템

### 다운로드
- **macOS**: MainBoothDrive-${VERSION}-mac.dmg
- **Windows**: MainBoothDrive-${VERSION}-windows.exe  
- **Linux**: MainBoothDrive-${VERSION}-linux.AppImage

### 시스템 요구사항
- **macOS**: 10.15 (Catalina) 이상
- **Windows**: Windows 10 버전 1903 이상
- **Linux**: Ubuntu 18.04+ / CentOS 7+

### 설치 방법
자세한 설치 방법은 [다운로드 페이지](https://drive.mainbooth.com)를 참조하세요."
    
    # GitHub CLI를 사용하여 릴리스 생성
    if command -v gh &> /dev/null; then
        gh release create "$tag_name" \
            --title "$release_name" \
            --notes "$release_body" \
            "$DIST_DIR"/* || log_warning "GitHub Release 생성 실패"
    else
        log_warning "GitHub CLI가 설치되지 않아 수동으로 릴리스를 생성해야 합니다."
    fi
    
    log_success "GitHub Release 생성 완료"
}

# 배포 (웹사이트)
deploy_website() {
    if [ -z "$DEPLOY_TARGET" ]; then
        log_warning "DEPLOY_TARGET이 설정되지 않아 웹사이트 배포를 건너뜁니다."
        return
    fi
    
    log_info "웹사이트 배포 중..."
    
    local web_dist="$DIST_DIR/website"
    
    case "$DEPLOY_TARGET" in
        "vercel")
            if command -v vercel &> /dev/null; then
                cd "$web_dist"
                vercel --prod
                cd -
            else
                log_warning "Vercel CLI가 설치되지 않았습니다."
            fi
            ;;
        "netlify")
            if command -v netlify &> /dev/null; then
                netlify deploy --prod --dir "$web_dist"
            else
                log_warning "Netlify CLI가 설치되지 않았습니다."
            fi
            ;;
        "s3")
            if command -v aws &> /dev/null && [ -n "$S3_BUCKET" ]; then
                aws s3 sync "$web_dist" "s3://$S3_BUCKET" --delete
                
                # CloudFront 무효화 (설정된 경우)
                if [ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
                    aws cloudfront create-invalidation \
                        --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
                        --paths "/*"
                fi
            else
                log_warning "AWS CLI가 설치되지 않았거나 S3_BUCKET이 설정되지 않았습니다."
            fi
            ;;
        *)
            log_warning "알 수 없는 배포 대상: $DEPLOY_TARGET"
            ;;
    esac
    
    log_success "웹사이트 배포 완료"
}

# 정리
cleanup() {
    log_info "정리 작업 중..."
    
    # 임시 파일 정리
    rm -rf temp.dmg 2>/dev/null || true
    rm -rf *.AppDir 2>/dev/null || true
    
    log_success "정리 작업 완료"
}

# 메인 빌드 함수
main() {
    local platforms=("${@:-macos windows linux}")
    
    log_info "Main Booth Drive 빌드 및 배포 시작"
    log_info "버전: $VERSION"
    log_info "플랫폼: ${platforms[*]}"
    
    # 사전 작업
    check_requirements
    install_dependencies
    run_quality_checks
    
    # 플랫폼별 빌드
    for platform in "${platforms[@]}"; do
        case "$platform" in
            "macos")
                build_macos
                sign_macos_app
                ;;
            "windows")
                build_windows
                ;;
            "linux")
                build_linux
                ;;
            *)
                log_warning "알 수 없는 플랫폼: $platform"
                ;;
        esac
    done
    
    # 공증 (macOS, 마지막에 실행)
    if [[ " ${platforms[*]} " =~ " macos " ]]; then
        notarize_macos_app
    fi
    
    # 웹사이트 빌드
    build_website
    
    # 배포
    create_github_release
    deploy_website
    
    # 정리
    cleanup
    
    log_success "모든 빌드 및 배포 작업 완료!"
    log_info "빌드 결과물: $DIST_DIR/"
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi