-- Dash MySQL Schema v1.7 (Added notifications, name/fcm_token columns)
-- 이 스크립트는 기존 테이블을 삭제하고 새롭게 생성합니다. (데이터 유실 주의)

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS notifications;
DROP TABLE IF EXISTS service_drafts;
DROP TABLE IF EXISTS cases;
DROP TABLE IF EXISTS dash_users;
DROP TABLE IF EXISTS dash_field_mappings;
SET FOREIGN_KEY_CHECKS = 1;

-- 1. 사용자 테이블
CREATE TABLE dash_users (
    id VARCHAR(36) PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(100),
    fcm_token TEXT,
    organization_id VARCHAR(100),
    public_key TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. 사례 관리 테이블 (모바일 생성 ID 수용을 위해 BIGINT 및 AUTO_INCREMENT 제거)
CREATE TABLE cases (
    id BIGINT PRIMARY KEY, -- 앱에서 생성한 1773... 형태의 ID를 그대로 저장
    user_id VARCHAR(36),
    case_name VARCHAR(100) NOT NULL,
    dong VARCHAR(50),
    target_system_code VARCHAR(50) DEFAULT 'NCADS_v2',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES dash_users(id) ON DELETE SET NULL
);

-- 3. 상담 기록 및 서비스 초안 테이블
CREATE TABLE service_drafts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    case_id BIGINT, -- cases.id와 타입을 맞춰야 Foreign Key 설정 가능
    
    target TEXT, -- Deprecated in v1.5+ (Use encrypted_blob)
    provision_type VARCHAR(50),
    method VARCHAR(50),
    service_type VARCHAR(50),
    service_name VARCHAR(100),
    location VARCHAR(100),
    start_time DATETIME,
    end_time DATETIME,
    service_count INT,
    travel_time INT,
    service_description TEXT,
    agent_opinion TEXT,
    
    encrypted_blob LONGTEXT,
    
    -- Synced(모바일), Reviewed(웹), Injected(자동주입), Archived
    status ENUM('Synced', 'Reviewed', 'Injected', 'Archived') DEFAULT 'Synced',
    share_token VARCHAR(100) UNIQUE,
    
    reviewed_at DATETIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    FOREIGN KEY (case_id) REFERENCES cases(id) ON DELETE CASCADE
);

-- 4. 필드 매핑 템플릿
CREATE TABLE dash_field_mappings (
    system_id VARCHAR(50) PRIMARY KEY,
    mapping_json JSON NOT NULL,
    version VARCHAR(20),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 5. 알림 테이블
CREATE TABLE notifications (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(36),
    case_name VARCHAR(100),
    record_token VARCHAR(100),
    message TEXT,
    is_read TINYINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES dash_users(id) ON DELETE CASCADE
);

-- 6. 보안 PIN 기반 열쇠 보관소 (Zero-Knowledge Sync)
CREATE TABLE user_key_vault (
    user_id VARCHAR(36) PRIMARY KEY,
    encrypted_vault LONGTEXT NOT NULL, -- PIN으로 암호화된 마스터 열쇠/케이스 열쇠 묶음
    salt VARCHAR(64), -- 암호화 키 유도를 위한 솔트
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES dash_users(id) ON DELETE CASCADE
);
