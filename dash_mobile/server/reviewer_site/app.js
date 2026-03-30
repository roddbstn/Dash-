// Reviewer Application Logic

let isInfoExpanded = false;
let saveTimeout = null;

// Handle typing with auto-save simulation
function handleTyping() {
    const status = document.getElementById('save-status');
    status.textContent = '저장 중...';
    status.style.opacity = '1';

    if (saveTimeout) clearTimeout(saveTimeout);

    saveTimeout = setTimeout(() => {
        const now = new Date();
        const timeStr = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`;
        
        // Actual save to server
        const urlParams = new URLSearchParams(window.location.search);
        const token = urlParams.get('token');
        if (token) {
            const serviceDescription = document.getElementById('main-editor').value;
            const agentOpinion = document.getElementById('opinion-editor').value || '';
            
            fetch(`/api/records/share/${token}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    service_description: serviceDescription,
                    agent_opinion: agentOpinion
                })
            })
            .then(res => res.json())
            .then(data => {
                console.log('✅ Auto-save successful');
                status.textContent = `✓ ${timeStr} 저장됨`;
            })
            .catch(err => {
                console.error('❌ Auto-save failed:', err);
                status.textContent = '저장 실패';
            });
        } else {
            status.textContent = `✓ ${timeStr} 저장됨 (Local)`;
        }
        
        // ✓ timeStr 저장됨 status update logic remains
        setTimeout(() => {
            status.style.opacity = '0.6';
        }, 2000);
    }, 1500);
}



// Mobile Info Toggle
function toggleMobileInfo() {
    const content = document.getElementById('mobile-info-content');
    const label = document.querySelector('.info-label');
    
    isInfoExpanded = !isInfoExpanded;
    
    if (isInfoExpanded) {
        content.style.display = 'block';
        label.innerHTML = '간략히 <span style="font-size: 1.4em;">▴</span>';
    } else {
        content.style.display = 'none';
        label.innerHTML = '서비스 상세 정보 <span style="font-size: 1.4em;">▾</span>';
    }
}

// Modal Logic
function openNotifyModal() {
    document.getElementById('modal-container').style.display = 'flex';
}

function closeModal() {
    document.getElementById('modal-container').style.display = 'none';
}

function confirmNotify() {
    const urlParams = new URLSearchParams(window.location.search);
    const token = urlParams.get('token');
    const encKey = window.location.hash.substring(1); // Get key from fragment

    if (!token) {
        alert('토큰 정보가 없어 완료할 수 없습니다.');
        return closeModal();
    }
    
    const serviceDescription = document.getElementById('main-editor').value;
    const agentOpinion = document.getElementById('opinion-editor').value;
    
    let body = { service_description: serviceDescription, agent_opinion: agentOpinion };

    // E2EE: If we have the encryption key, re-encrypt the entire record
    if (encKey && window.currentRecord) {
        try {
            const updatedData = { ...window.currentRecord, serviceDescription, agentOpinion };
            const key = CryptoJS.enc.Utf8.parse(encKey.padEnd(32).substring(0, 32));
            const iv = CryptoJS.lib.WordArray.random(16);
            const encrypted = CryptoJS.AES.encrypt(JSON.stringify(updatedData), key, { iv: iv });
            
            body.encrypted_blob = iv.toString(CryptoJS.enc.Base64) + ":" + encrypted.toString();
            // Still send raw fields for legacy/transition support or specific meta needs, 
            // but the server should ideally ignore them.
            body.service_description = ''; 
            body.agent_opinion = '';
        } catch (e) {
            console.error("Encryption failed:", e);
        }
    }

    fetch(`/api/records/reviewed/${token}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
    })
    .then(res => res.json())
    .then(data => {
        if (data.error) throw new Error(data.error);
        alert('사례 담당자에게 검토 완료 알림을 보냈습니다.');
        closeModal();
    })
    .catch(err => {
        alert('처리 중 오류가 발생했습니다.');
        console.error(err);
    });
}

function formatDayOfWeek(dateString) {
    if(!dateString) return '';
    const date = new Date(dateString);
    if(isNaN(date)) return dateString;
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    const m = date.getMonth() + 1;
    const d = date.getDate();
    const day = days[date.getDay()];
    // format to "M.d (day)"
    return `${m}.${d} (${day})`;
}

// Format start and end time string "3월 12일 (목) 17:45 ~ 18:45"
function formatDateTimeRange(startStr, endStr) {
    if(!startStr || !endStr) return '';
    const startDate = new Date(startStr);
    const endDate = new Date(endStr);
    if(isNaN(startDate) || isNaN(endDate)) return `${startStr} ~ ${endStr}`;
    
    const startDayFormatted = formatDayOfWeek(startStr);
    const startHour = startDate.getHours().toString().padStart(2, '0');
    const startMin = startDate.getMinutes().toString().padStart(2, '0');
    
    const endHour = endDate.getHours().toString().padStart(2, '0');
    const endMin = endDate.getMinutes().toString().padStart(2, '0');

    // Check if dates are same
    const isSameDay = startDate.getFullYear() === endDate.getFullYear() &&
                      startDate.getMonth() === endDate.getMonth() &&
                      startDate.getDate() === endDate.getDate();

    if (isSameDay) {
        return `${startDayFormatted} ${startHour}:${startMin} ~ ${endHour}:${endMin}`;
    } else {
        const endDayFormatted = formatDayOfWeek(endStr);
        return `${startDayFormatted} ${startHour}:${startMin} ~ ${endDayFormatted} ${endHour}:${endMin}`;
    }
}

// Initialize
window.onload = () => {
    const mainTextarea = document.getElementById('main-editor');
    const opinionTextarea = document.getElementById('opinion-editor');
    
    function autoResize() {
        this.style.height = 'auto';
        this.style.height = (this.scrollHeight) + 'px';
    }
    
    mainTextarea.addEventListener('input', autoResize);
    opinionTextarea.addEventListener('input', autoResize);

    const urlParams = new URLSearchParams(window.location.search);
    const token = urlParams.get('token');
    
    if (token) {
        console.log(`Fetching record for token: ${token}...`);
        // 2. Encryption Key from Hash (#)
        let encKey = "";
        const hash = window.location.hash.substring(1);
        if (hash) {
            // Support both #key=VALUE and #VALUE
            const parts = hash.split('key=');
            encKey = parts.length > 1 ? parts[1] : parts[0];
        }

        fetch(`${window.location.origin}/api/records/share/${token}`)
            .then(res => {
                if (!res.ok) throw new Error(`HTTP error! status: ${res.status}`);
                return res.json();
            })
            .then(data => {
                // E2EE Decryption
                if (data.encrypted_blob && encKey) {
                    try {
                        console.log("🔒 End-to-End Encryption Detected. Decrypting...");
                        const parts = data.encrypted_blob.split(':');
                        const iv = CryptoJS.enc.Base64.parse(parts[0]);
                        const ciphertext = parts[1];
                        const key = CryptoJS.enc.Utf8.parse(encKey.padEnd(32).substring(0, 32));
                        
                        const decrypted = CryptoJS.AES.decrypt(
                            { ciphertext: CryptoJS.enc.Base64.parse(ciphertext) }, 
                            key, 
                            { iv: iv }
                        );
                        const decryptedText = decrypted.toString(CryptoJS.enc.Utf8);
                        if (!decryptedText) throw new Error("Empty decryption result");
                        
                        const decryptedData = JSON.parse(decryptedText);
                        console.log("Decrypted successful:", decryptedData);
                        
                        // Merge decrypted data into the row object
                        // Handle camelCase from Flutter vs snake_case from DB
                        data = { 
                            ...data, 
                            ...decryptedData,
                            case_name: decryptedData.caseName || data.case_name,
                            service_description: decryptedData.serviceDescription || decryptedData.service_description || data.service_description,
                            agent_opinion: decryptedData.agentOpinion || decryptedData.agent_opinion || data.agent_opinion,
                            target: decryptedData.target || data.target,
                            method: decryptedData.method || data.method,
                            provision_type: decryptedData.provision_type || data.provision_type,
                            service_type: decryptedData.service_type || data.service_type,
                            service_name: decryptedData.service_name || data.service_name,
                            location: decryptedData.location || data.location,
                            start_time: decryptedData.startTime || decryptedData.start_time || data.start_time,
                            end_time: decryptedData.endTime || decryptedData.end_time || data.end_time,
                            service_count: decryptedData.serviceCount || decryptedData.service_count || data.service_count,
                            travel_time: decryptedData.travelTime || decryptedData.travel_time || data.travel_time
                        };
                        window.currentRecord = data; // Store for re-encryption
                    } catch (e) {
                        console.error("Decryption failed:", e);
                        // If decryption failed, we still have the raw data in 'data'
                    }
                }
                updateUI(data);
            })
            .catch(err => {
                console.log("Error fetching data (likely deleted):", err);
                document.getElementById('page-title').textContent = "삭제된 DB입니다.";
                const mainArea = document.querySelector('.main-editor-area');
                if (mainArea) mainArea.innerHTML = '<div style="text-align:center; padding: 40px; color: #ADB5BD; font-size: 16px;">해당 DB는 삭제되었으므로 열람할 수 없습니다.</div>';
            });
    }
};

function updateUI(data) {
    document.getElementById('page-title').textContent = `${data.case_name || '미지정'} 아동 사례`;
    
    // Update Author Name
    const authorEl = document.getElementById('author-name');
    if (authorEl) {
        authorEl.textContent = `${data.user_name || '관리자'} 상담원 작성`;
    }
    
    // Status badges update
    const isReviewed = data.status === 'Reviewed';
    const statusText = isReviewed ? '검토 완료' : '검토 대기';
    const statusColor = isReviewed ? '#4CAF50' : '#2196F3';
    const statusBg = isReviewed ? '#E8F5E9' : '#E3F2FD';
    
    const headerStatus = document.querySelector('.main-header .status-indicator');
    if (headerStatus) {
        headerStatus.style.background = statusBg;
        headerStatus.querySelector('.pulse-dot').style.background = statusColor;
        const textEl = headerStatus.querySelector('.status-text');
        textEl.textContent = statusText;
        textEl.style.color = statusColor;
    }

    const mobileTag = document.getElementById('mobile-child-tag');
    if (mobileTag) {
        mobileTag.innerHTML = `
            <div class="status-indicator" style="display: inline-flex; background: ${statusBg}; gap: 6px; align-items: center; padding: 6px 12px; border-radius: 100px; width: fit-content;">
                <span class="pulse-dot" style="background: ${statusColor}; width: 6px; height: 6px; border-radius: 50%;"></span>
                <span class="status-text" style="color: ${statusColor}; font-weight: 700; font-size: 13px; white-space: nowrap;">${statusText}</span>
            </div>
        `;
    }
    
    document.getElementById('main-editor').value = data.service_description || '';
    document.getElementById('opinion-editor').value = data.agent_opinion || '';
    
    // Auto resize after setting value
    document.getElementById('main-editor').dispatchEvent(new Event('input'));
    document.getElementById('opinion-editor').dispatchEvent(new Event('input'));
    
    const metaList = [
        { label: '대상자', value: data.target ? (Array.isArray(data.target) ? data.target.join(' · ') : data.target.replace(/,/g, ' · ')) : '-' },
        { label: '제공구분', value: data.provision_type || '-' },
        { label: '제공방법', value: data.method || '-' },
        { label: '서비스유형', value: data.service_type || '-' },
        { label: '제공서비스', value: data.service_name || '-' },
        { label: '제공장소', value: data.location || '-' },
        { label: '제공일시', value: formatDateTimeRange(data.start_time, data.end_time) },
        { label: '이동시간', value: data.travel_time ? `${data.travel_time}분` : '-' },
        { label: '제공횟수', value: data.service_count ? `${data.service_count}회` : '-' },
    ];
    
    const pcGrid = document.getElementById('pc-meta-grid');
    const mobileGrid = document.getElementById('mobile-meta-grid');
    
    const htmlObj = metaList.map(m => {
        const isDate = m.label === '제공일시';
        return `
        <div class="meta-item">
            <label>${m.label}</label>
            <span class="${isDate ? 'meta-date-val' : ''}">${m.value}</span>
        </div>
        `;
    }).join('');
    
    pcGrid.innerHTML = htmlObj;
    mobileGrid.innerHTML = htmlObj;
}
