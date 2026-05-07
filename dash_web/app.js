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
        
        // Simulating data sync
        console.log('✅ Auto-save simulation successful');
        status.textContent = `✓ ${timeStr} 저장됨`;
        
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
        label.textContent = '간략히 ▴';
    } else {
        content.style.display = 'none';
        label.textContent = '서비스 상세 정보 ▾';
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
    alert('사례 담당자에게 수정 완료 알림을 보냈습니다.');
    closeModal();
}

// Initialize
window.onload = () => {
    const textarea = document.getElementById('main-editor');
    
    // Auto-resize textarea logic could go here if needed
    textarea.style.height = 'auto';
    textarea.style.height = (textarea.scrollHeight) + 'px';
    
    textarea.addEventListener('input', function() {
        this.style.height = 'auto';
        this.style.height = (this.scrollHeight) + 'px';
    });

    // Check for ID in URL (Standard Spec)
    const urlParams = new URLSearchParams(window.location.search);
    const draftId = urlParams.get('id');
    if (draftId) {
        console.log(`Fetching draft content for ID: ${draftId}...`);
        // In a real app, this would be:
        // fetch(`/api/drafts/${draftId}`).then(res => res.json()).then(data => updateUI(data));
    }
};
