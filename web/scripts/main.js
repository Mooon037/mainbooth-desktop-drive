// Main Booth Drive - Download Website JavaScript

document.addEventListener('DOMContentLoaded', function() {
    // Initialize all functionality
    initNavigation();
    initDownloads();
    initGuidesTabs();
    initScrollAnimations();
    initAnalytics();
});

// Navigation functionality
function initNavigation() {
    const navbar = document.querySelector('.navbar');
    const mobileToggle = document.querySelector('.nav-mobile-toggle');
    const navLinks = document.querySelector('.nav-links');

    // Navbar scroll effect
    window.addEventListener('scroll', () => {
        if (window.scrollY > 50) {
            navbar.classList.add('scrolled');
        } else {
            navbar.classList.remove('scrolled');
        }
    });

    // Mobile navigation toggle
    if (mobileToggle && navLinks) {
        mobileToggle.addEventListener('click', () => {
            navLinks.classList.toggle('active');
            mobileToggle.classList.toggle('active');
        });
    }

    // Smooth scroll for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                const offsetTop = target.offsetTop - 80; // Account for fixed navbar
                window.scrollTo({
                    top: offsetTop,
                    behavior: 'smooth'
                });
            }
        });
    });
}

// Download functionality
function initDownloads() {
    const downloadButtons = document.querySelectorAll('.btn-download');
    const modal = document.getElementById('download-modal');
    const modalClose = document.querySelector('.modal-close');
    const startDownloadBtn = document.getElementById('start-download');
    const cancelDownloadBtn = document.getElementById('cancel-download');

    // Download URLs configuration
    const downloadUrls = {
        mac: {
            url: 'https://github.com/mainbooth/desktop-drive/releases/latest/download/MainBoothDrive-mac.dmg',
            filename: 'MainBoothDrive-1.0.0-mac.dmg',
            size: '45.2 MB'
        },
        windows: {
            url: 'https://github.com/mainbooth/desktop-drive/releases/latest/download/MainBoothDrive-windows.exe',
            filename: 'MainBoothDrive-1.0.0-windows.exe',
            size: '52.8 MB'
        },
        linux: {
            url: 'https://github.com/mainbooth/desktop-drive/releases/latest/download/MainBoothDrive-linux.AppImage',
            filename: 'MainBoothDrive-1.0.0-linux.AppImage',
            size: '48.6 MB'
        }
    };

    let currentDownload = null;

    // Handle download button clicks
    downloadButtons.forEach(button => {
        button.addEventListener('click', (e) => {
            e.preventDefault();
            const platform = button.getAttribute('data-platform');
            
            // Track download initiation
            trackEvent('download_initiated', { platform });
            
            // Detect user's platform automatically
            const detectedPlatform = detectPlatform();
            const downloadPlatform = platform || detectedPlatform;
            
            if (downloadUrls[downloadPlatform]) {
                currentDownload = downloadUrls[downloadPlatform];
                showDownloadModal(downloadPlatform);
            } else {
                // Fallback to direct download
                window.open(downloadUrls.mac.url, '_blank');
            }
        });
    });

    // Modal event listeners
    if (modalClose) {
        modalClose.addEventListener('click', closeDownloadModal);
    }

    if (cancelDownloadBtn) {
        cancelDownloadBtn.addEventListener('click', closeDownloadModal);
    }

    if (startDownloadBtn) {
        startDownloadBtn.addEventListener('click', startDownload);
    }

    // Close modal on outside click
    if (modal) {
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                closeDownloadModal();
            }
        });
    }

    function showDownloadModal(platform) {
        const platformNames = {
            mac: 'macOS',
            windows: 'Windows',
            linux: 'Linux'
        };

        document.getElementById('modal-platform-name').textContent = platformNames[platform];
        document.getElementById('modal-file-info').textContent = 
            `${currentDownload.filename} (${currentDownload.size})`;
        
        modal.classList.add('active');
        document.body.style.overflow = 'hidden';
    }

    function closeDownloadModal() {
        modal.classList.remove('active');
        document.body.style.overflow = '';
        resetProgressBar();
    }

    function startDownload() {
        if (!currentDownload) return;

        startDownloadBtn.style.display = 'none';
        simulateDownload();
        
        // Track download start
        trackEvent('download_started', { 
            filename: currentDownload.filename,
            size: currentDownload.size 
        });

        // Create download link and trigger
        const link = document.createElement('a');
        link.href = currentDownload.url;
        link.download = currentDownload.filename;
        link.style.display = 'none';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    function simulateDownload() {
        const progressFill = document.querySelector('.progress-fill');
        const progressPercentage = document.getElementById('progress-percentage');
        const downloadSpeed = document.getElementById('download-speed');
        
        let progress = 0;
        const interval = setInterval(() => {
            progress += Math.random() * 15;
            if (progress > 100) progress = 100;
            
            progressFill.style.width = `${progress}%`;
            progressPercentage.textContent = `${Math.round(progress)}%`;
            downloadSpeed.textContent = `${(Math.random() * 10 + 5).toFixed(1)} MB/s`;
            
            if (progress >= 100) {
                clearInterval(interval);
                setTimeout(() => {
                    closeDownloadModal();
                    showDownloadComplete();
                }, 1000);
            }
        }, 200);
    }

    function resetProgressBar() {
        const progressFill = document.querySelector('.progress-fill');
        const progressPercentage = document.getElementById('progress-percentage');
        const downloadSpeed = document.getElementById('download-speed');
        
        progressFill.style.width = '0%';
        progressPercentage.textContent = '0%';
        downloadSpeed.textContent = '0 MB/s';
        startDownloadBtn.style.display = 'block';
    }

    function showDownloadComplete() {
        // Create a simple notification
        const notification = document.createElement('div');
        notification.className = 'download-notification';
        notification.innerHTML = `
            <div style="
                position: fixed;
                top: 20px;
                right: 20px;
                background: #10b981;
                color: white;
                padding: 1rem 1.5rem;
                border-radius: 0.5rem;
                box-shadow: 0 10px 40px rgba(0,0,0,0.1);
                z-index: 3000;
                animation: slideInRight 0.3s ease;
            ">
                <div style="display: flex; align-items: center; gap: 0.5rem;">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M9 12l2 2 4-4"></path>
                        <path d="M21 12c-1 0-3-1-3-3s2-3 3-3 3 1 3 3-2 3-3 3"></path>
                        <path d="M3 12c1 0 3-1 3-3s-2-3-3-3-3 1-3 3 2 3 3 3"></path>
                        <path d="M13 12h3"></path>
                        <path d="M8 12H5"></path>
                    </svg>
                    <span>다운로드가 완료되었습니다!</span>
                </div>
            </div>
        `;
        
        document.body.appendChild(notification);
        setTimeout(() => {
            notification.remove();
        }, 5000);
        
        trackEvent('download_completed', { filename: currentDownload.filename });
    }
}

// Platform detection
function detectPlatform() {
    const userAgent = navigator.userAgent.toLowerCase();
    
    if (userAgent.includes('mac')) {
        return 'mac';
    } else if (userAgent.includes('win')) {
        return 'windows';
    } else if (userAgent.includes('linux')) {
        return 'linux';
    }
    
    return 'mac'; // Default fallback
}

// Installation guide tabs
function initGuidesTabs() {
    const tabs = document.querySelectorAll('.guide-tab');
    const panels = document.querySelectorAll('.guide-panel');

    tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            const targetTab = tab.getAttribute('data-tab');
            
            // Remove active class from all tabs and panels
            tabs.forEach(t => t.classList.remove('active'));
            panels.forEach(p => p.classList.remove('active'));
            
            // Add active class to clicked tab and corresponding panel
            tab.classList.add('active');
            document.getElementById(`guide-${targetTab}`).classList.add('active');
        });
    });

    // Auto-select tab based on detected platform
    const detectedPlatform = detectPlatform();
    const platformTab = document.querySelector(`[data-tab="${detectedPlatform}"]`);
    if (platformTab) {
        platformTab.click();
    }
}

// Scroll animations
function initScrollAnimations() {
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('animate-on-scroll');
            }
        });
    }, observerOptions);

    // Observe elements for animation
    const animatedElements = document.querySelectorAll(
        '.feature-card, .download-card, .support-card, .guide-step'
    );
    
    animatedElements.forEach(el => observer.observe(el));
}

// Analytics and tracking
function initAnalytics() {
    // Track page view
    trackEvent('page_view', { page: 'download' });
    
    // Track scroll depth
    let maxScrollDepth = 0;
    window.addEventListener('scroll', () => {
        const scrollDepth = Math.round(
            (window.scrollY / (document.documentElement.scrollHeight - window.innerHeight)) * 100
        );
        
        if (scrollDepth > maxScrollDepth) {
            maxScrollDepth = scrollDepth;
            
            // Track milestone scroll depths
            if ([25, 50, 75, 90].includes(scrollDepth)) {
                trackEvent('scroll_depth', { depth: scrollDepth });
            }
        }
    });
    
    // Track feature card interactions
    document.querySelectorAll('.feature-card').forEach((card, index) => {
        card.addEventListener('mouseenter', () => {
            trackEvent('feature_hover', { feature_index: index });
        });
    });
    
    // Track external link clicks
    document.querySelectorAll('a[href^="http"], a[href^="mailto:"]').forEach(link => {
        link.addEventListener('click', () => {
            trackEvent('external_link_click', { 
                url: link.href,
                text: link.textContent.trim()
            });
        });
    });
}

// Generic event tracking function
function trackEvent(eventName, properties = {}) {
    // Google Analytics 4
    if (typeof gtag !== 'undefined') {
        gtag('event', eventName, properties);
    }
    
    // Console log for development
    if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
        console.log('Track Event:', eventName, properties);
    }
    
    // Custom analytics can be added here
    // Example: sendToCustomAnalytics(eventName, properties);
}

// Version checking and update notifications
function checkForUpdates() {
    fetch('https://api.github.com/repos/Mooon037/mainbooth-desktop-drive/releases/latest')
        .then(response => response.json())
        .then(data => {
            const latestVersion = data.tag_name;
            const currentVersion = '1.0.0'; // This should be dynamically set
            
            if (latestVersion !== `v${currentVersion}`) {
                showUpdateNotification(latestVersion);
            }
        })
        .catch(error => {
            console.log('Update check failed:', error);
        });
}

function showUpdateNotification(version) {
    const notification = document.createElement('div');
    notification.innerHTML = `
        <div style="
            position: fixed;
            top: 80px;
            right: 20px;
            background: #6366f1;
            color: white;
            padding: 1rem 1.5rem;
            border-radius: 0.5rem;
            box-shadow: 0 10px 40px rgba(99, 102, 241, 0.3);
            z-index: 3000;
            max-width: 300px;
        ">
            <div style="font-weight: 600; margin-bottom: 0.5rem;">
                새 버전 출시!
            </div>
            <div style="font-size: 0.875rem; margin-bottom: 1rem;">
                Main Booth Drive ${version}이 출시되었습니다.
            </div>
            <button onclick="this.parentElement.parentElement.remove()" style="
                background: rgba(255,255,255,0.2);
                border: none;
                color: white;
                padding: 0.5rem 1rem;
                border-radius: 0.25rem;
                cursor: pointer;
                font-size: 0.875rem;
            ">
                확인
            </button>
        </div>
    `;
    
    document.body.appendChild(notification);
    setTimeout(() => {
        if (notification.parentElement) {
            notification.remove();
        }
    }, 10000);
}

// System requirements checker
function checkSystemRequirements() {
    const platform = detectPlatform();
    const userAgent = navigator.userAgent;
    
    let isSupported = true;
    let warnings = [];
    
    if (platform === 'mac') {
        // Check macOS version (simplified check)
        const macVersionMatch = userAgent.match(/Mac OS X (\d+)[._](\d+)/);
        if (macVersionMatch) {
            const majorVersion = parseInt(macVersionMatch[1]);
            const minorVersion = parseInt(macVersionMatch[2]);
            
            if (majorVersion < 10 || (majorVersion === 10 && minorVersion < 15)) {
                isSupported = false;
                warnings.push('macOS 10.15 (Catalina) 이상이 필요합니다.');
            }
        }
    } else if (platform === 'windows') {
        // Check Windows version (simplified check)
        if (userAgent.includes('Windows NT 6.1')) {
            isSupported = false;
            warnings.push('Windows 10 이상이 필요합니다.');
        }
    }
    
    return { isSupported, warnings, platform };
}

// Initialize system requirements check on page load
setTimeout(() => {
    const requirements = checkSystemRequirements();
    
    if (!requirements.isSupported && requirements.warnings.length > 0) {
        showSystemWarning(requirements.warnings);
    }
    
    // Highlight the user's platform in download section
    const userPlatformCard = document.querySelector(`[data-platform="${requirements.platform}"]`);
    if (userPlatformCard) {
        userPlatformCard.style.border = '2px solid #6366f1';
        userPlatformCard.style.transform = 'scale(1.02)';
    }
}, 1000);

function showSystemWarning(warnings) {
    const warningElement = document.createElement('div');
    warningElement.innerHTML = `
        <div style="
            background: #fef3c7;
            border: 1px solid #f59e0b;
            color: #92400e;
            padding: 1rem;
            border-radius: 0.5rem;
            margin: 1rem 0;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        ">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"></path>
                <line x1="12" y1="9" x2="12" y2="13"></line>
                <line x1="12" y1="17" x2="12.01" y2="17"></line>
            </svg>
            <div>
                <strong>시스템 호환성 경고:</strong><br>
                ${warnings.join('<br>')}
            </div>
        </div>
    `;
    
    const downloadSection = document.getElementById('download');
    if (downloadSection) {
        downloadSection.insertBefore(warningElement, downloadSection.firstChild.nextSibling);
    }
}

// Performance monitoring
function initPerformanceMonitoring() {
    // Monitor page load performance
    window.addEventListener('load', () => {
        setTimeout(() => {
            const perfData = performance.getEntriesByType('navigation')[0];
            const loadTime = perfData.loadEventEnd - perfData.fetchStart;
            
            trackEvent('page_performance', {
                load_time: Math.round(loadTime),
                dom_content_loaded: Math.round(perfData.domContentLoadedEventEnd - perfData.fetchStart),
                first_paint: Math.round(performance.getEntriesByType('paint')[0]?.startTime || 0)
            });
        }, 0);
    });
}

// Initialize performance monitoring
initPerformanceMonitoring();

// Auto-check for updates every hour
setInterval(checkForUpdates, 3600000);

// Initial update check after 5 seconds
setTimeout(checkForUpdates, 5000);
