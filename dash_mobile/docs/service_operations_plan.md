# Dash 서비스 운영 준비 기획서

> 작성일: 2026-05-18  
> 현황 기준: Railway 서버, MySQL, Flutter(iOS/Android), Chrome Extension 3.3, Firebase

---

## 현황 스냅샷

| 영역 | 현재 상태 | 위험도 |
|------|----------|--------|
| 서버 모니터링/알럿 | ❌ 없음 | 🔴 높음 |
| DB 자동 백업 | ❌ 없음 | 🔴 높음 |
| 보안 헤더/글로벌 Rate Limit | ⚠️ 부분적 | 🔴 높음 |
| 에러 트래킹 (Crashlytics) | ✅ 있음 | — |
| Firebase Analytics | ✅ 있음 | — |
| 개인정보처리방침/이용약관 | ✅ 있음 | — |
| 법정 데이터 파기 스케줄러 | ✅ 있음 | — |
| 사용자 가이드/온보딩 | ✅ 있음 | — |
| 문의/피드백 채널 | ❌ 없음 | 🟡 중간 |
| CI/CD (서버·앱) | ⚠️ 웹만 | 🟡 중간 |
| 기관 단위 관리 | ⚠️ 구조만 | 🟡 중간 |
| 앱스토어 메타데이터 | ❌ 없음 | 🟡 중간 |

---

## 운영 준비 로드맵

```
즉시 (지금~2주)     단기 (1~3개월)     중기 (3~6개월)     장기 (6개월+)
━━━━━━━━━━━━━━━━━   ━━━━━━━━━━━━━━━━   ━━━━━━━━━━━━━━━━   ━━━━━━━━━━━━━━━━
서버 모니터링        문의 채널 오픈      기관 관리자 기능    SLA 계약 체계
DB 백업 설정         서버 CI/CD          사용자 대시보드     다기관 확장
보안 헤더 추가       앱 배포 자동화      결제/구독 준비      B2B 영업 도구
Vault 장애 대응      피드백 루프 구축    SLA 내부 목표 수립  감사(Audit) 로그
```

---

## PART 1. 즉시 해야 할 것 🔴

### 1-1. 서버 모니터링 & 알럿

**왜 지금 해야 하나**: 서버가 죽어도 아무도 모른다. 상담원이 현장에서 앱을 켰을 때 서버가 다운되면 기록이 유실될 수 있다.

**구체적 액션**:

```
① UptimeRobot (무료) 설정
   - 모니터링 URL: https://dash.qpon/health
   - 체크 주기: 5분
   - 알럿 채널: 이메일 + 카카오톡 (또는 문자)

② Railway 자체 알럿 설정
   - Railway 대시보드 → Notifications → Deployment failures 활성화
   - 메모리/CPU 임계값 알럿 (Railway Pro 기능)

③ 서버 /health 엔드포인트 강화 (현재 기본만 있음)
```

```javascript
// server/index.js 추가
app.get('/health', async (req, res) => {
  try {
    await queryWithTimeout('SELECT 1', [], 3000);
    res.json({
      status: 'ok',
      timestamp: new Date().toISOString(),
      db: 'connected',
      uptime: process.uptime()
    });
  } catch (err) {
    res.status(503).json({ status: 'error', db: 'disconnected' });
  }
});
```

---

### 1-2. DB 자동 백업

**왜 지금 해야 하나**: MySQL 데이터가 날아가면 상담원의 아동 기록이 전부 소실된다. 법적 보존 의무(5년)도 있다.

**구체적 액션**:

```
① Railway MySQL Plugin 백업 확인
   - Railway 대시보드 → Database → Backups 탭 확인
   - Point-in-time recovery 활성화 여부 확인

② 수동 백업 스크립트 (주 1회 cron)
```

```javascript
// server/index.js 기존 cron에 추가
cron.schedule('0 3 * * 0', async () => { // 매주 일요일 새벽 3시
  // mysqldump → Railway Volume 또는 외부 스토리지(S3) 저장
  console.log('[BACKUP] Weekly DB backup triggered');
});
```

```
③ 복구 훈련 (분기 1회)
   - 백업 파일로 실제 복구 테스트
   - 예상 복구 시간(RTO) 측정
```

---

### 1-3. 보안 헤더 & 글로벌 Rate Limit

**왜 지금 해야 하나**: 아동 정보를 다루는 서비스가 기본 보안 헤더조차 없으면 감사 시 문제가 된다.

**구체적 액션**:

```javascript
// server/index.js 최상단에 추가
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

// 보안 헤더
app.use(helmet({
  contentSecurityPolicy: false, // SSE 호환을 위해
  crossOriginEmbedderPolicy: false,
}));

// 글로벌 Rate Limit (모든 엔드포인트)
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15분
  max: 200,
  message: { error: '요청이 너무 많습니다. 잠시 후 다시 시도해주세요.' },
  standardHeaders: true,
  legacyHeaders: false,
});
app.use('/api', globalLimiter);

// 인증 엔드포인트 강화 Rate Limit
const authLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  max: 20,
});
app.use('/api/users/login', authLimiter);
app.use('/api/vault', authLimiter);
```

```
npm install helmet express-rate-limit
```

---

### 1-4. Vault 장애 대응 절차 문서화

**왜 지금 해야 하나**: Vault에 문제가 생기면 상담원 전체가 암호화 키를 잃는다. 대응 절차가 없으면 패닉 상태가 된다.

**장애 시나리오별 대응**:

| 시나리오 | 감지 방법 | 대응 |
|---------|----------|------|
| Vault 복호화 실패 (PIN 오류) | 앱 내 에러 | 재입력 안내 → 3회 실패 시 초기화 옵션 |
| SecureStorage 소실 (앱 재설치) | keyMap 비어있음 | Vault 복구 다이얼로그 (이미 구현됨) |
| 서버 Vault API 다운 | health 체크 | 로컬 SecureStorage 캐시로 임시 운영 |
| PIN 분실 | 사용자 문의 | Vault 초기화 + 모든 키 재생성 안내 |

---

## PART 2. 단기 준비 (1~3개월) 🟡

### 2-1. 사용자 문의/피드백 채널

**구성 옵션**:

```
A안 (최소): 앱 내 이메일 문의 버튼
   profile_tab.dart에 "문의하기" → mailto:support@dash.qpon

B안 (권장): 채널톡 무료 플랜
   - 실시간 채팅 지원
   - 앱에 WebView로 연동 또는 링크 연결
   - 문의 이력 관리 가능

C안 (성장기): 전용 헬프센터 (Notion 기반)
   - FAQ 자체 운영
   - 채널톡과 연동
```

**앱 내 구현 위치**: `profile_tab.dart` → 설정 섹션 하단

**필수 FAQ 항목** (지금 작성 필요):
- [ ] PIN을 잊어버렸을 때
- [ ] 앱 재설치 후 기록이 안 보일 때
- [ ] 확장프로그램이 자동 입력이 안 될 때
- [ ] 공유 링크가 만료됐을 때
- [ ] 계정 탈퇴 방법

---

### 2-2. 서버 배포 CI/CD

**현재**: 수동 git push → Railway 자동 재시작 (단순)  
**문제**: 잘못된 코드가 바로 프로덕션 반영, 롤백 절차 없음

**목표 구성**:

```
GitHub main 푸시
    ↓
GitHub Actions
    ├── 린트/기본 테스트
    ├── .env 체크 (필수 환경변수 누락 감지)
    └── Railway 배포 트리거
         ↓
    배포 후 /health 엔드포인트 자동 확인
         ↓
    실패 시 Slack/이메일 알럿
```

```yaml
# .github/workflows/deploy-server.yml (예시 구조)
name: Deploy Server
on:
  push:
    branches: [main]
    paths: ['dash_mobile/server/**']
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Check required env vars
        run: |
          # DB_HOST, FIREBASE_SERVICE_ACCOUNT 등 필수 변수 확인
      - name: Deploy to Railway
        uses: bervProject/railway-deploy@v1
        with:
          railway_token: ${{ secrets.RAILWAY_TOKEN }}
      - name: Health check
        run: |
          sleep 15
          curl -f https://dash.qpon/health || exit 1
```

---

### 2-3. 앱 배포 자동화 (Flutter)

**현재**: Xcode 수동 아카이브 → 앱스토어 수동 업로드  
**목표**: Fastlane으로 반자동화

```
# Fastfile 기본 구성
lane :beta do
  increment_build_number
  build_app(scheme: "Runner")
  upload_to_testflight
end

lane :release do
  build_app(scheme: "Runner")
  upload_to_app_store(
    submit_for_review: false,  # 수동 검수 제출 유지
    force: true
  )
end
```

---

### 2-4. 운영 지표 대시보드

**Firebase Analytics에서 주 1회 확인할 KPI**:

| 지표 | 의미 | 목표값 |
|------|------|--------|
| `dbrecord_sync_success` 건수 | 실제 사용량 | 주 상승 추세 |
| `dbrecord_sync_failure` / `success` 비율 | 서버 안정성 | < 5% |
| `pin_set` 건수 | Vault 보안 활성화율 | 신규 유저의 > 80% |
| `offline_banner_shown` 횟수 | 서버 불안정 감지 | 주 < 3회 |
| `onboarding_complete` / `login_success` 비율 | 온보딩 완료율 | > 70% |

**서버 사이드 주 1회 확인**:

```sql
-- 주간 사용 현황 리포트
SELECT 
  DATE(created_at) AS date,
  COUNT(*) AS new_records,
  SUM(CASE WHEN status = 'Injected' THEN 1 ELSE 0 END) AS injected,
  SUM(CASE WHEN reviewer_user_id IS NOT NULL THEN 1 ELSE 0 END) AS shared
FROM service_drafts
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

---

### 2-5. 피드백 루프 구축

**정기 사이클**:

```
매주: Analytics 지표 확인 → 이상 감지
매월: 사용자 1명 이상 인터뷰 (15분)
분기: 전체 기능 회고 + 다음 분기 우선순위 설정
```

**인터뷰 핵심 질문 3가지**:
1. "지난 한 달 동안 Dash를 쓰면서 가장 불편했던 순간은 언제였나요?"
2. "동료에게 Dash를 추천한다면, 어떤 이유로 하시겠어요?"
3. "지금 당장 하나만 고쳐준다면 무엇을 고쳐주면 될까요?"

---

## PART 3. 중기 준비 (3~6개월) 🟢

### 3-1. 기관 관리자 기능

**현재**: `organization_id = 'DEFAULT_ORG'` — 껍데기만 있음  
**목표**: 기관별로 관리자가 소속 상담원을 관리할 수 있는 구조

**필요한 것**:
```
DB 스키마 추가:
  organizations 테이블 (id, name, domain, plan, created_at)
  admin_users 테이블 (user_id, org_id, role: 'admin'|'member')

API 추가:
  GET  /api/org/:orgId/members    → 소속 상담원 목록
  POST /api/org/:orgId/invite     → 초대 이메일 발송
  DEL  /api/org/:orgId/members/:userId → 멤버 제거

앱 기능:
  관리자용 대시보드 화면 (기관 사용 현황)
  초대 링크로 조직 합류
```

---

### 3-2. 내부 SLA 목표 설정

서비스를 진지하게 운영하려면 스스로 목표치를 먼저 설정해야 한다.

| 항목 | 목표 | 현재 측정 방법 |
|------|------|---------------|
| 서버 업타임 | 99.5% (월 3.6시간 이하 다운) | UptimeRobot |
| API 응답 시간 | P95 < 1초 | Railway 로그 |
| 앱 크래시율 | < 0.5% (세션 기준) | Firebase Crashlytics |
| Vault 복구 성공률 | > 99% | 서버 로그 |
| 데이터 파기 스케줄러 성공 | 100% (월별 확인) | retention_policy_log 테이블 |

---

### 3-3. 감사(Audit) 로그

**왜 필요한가**: 아동 정보를 다루므로 "누가 언제 어떤 기록을 열람했는가"를 추적해야 할 수 있다. 기관 계약이나 감사 시 필수.

```javascript
// 공유 링크 열람 로그 (server/index.js에 추가)
// GET /api/records/share/:token 에 접근 시 기록
pool.query(`
  CREATE TABLE IF NOT EXISTS access_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    record_token VARCHAR(100),
    accessor_ip VARCHAR(50),
    accessor_name VARCHAR(100),
    accessed_at DATETIME DEFAULT NOW(),
    action VARCHAR(50)
  )
`);
```

---

### 3-4. 결제/구독 모델 준비 (B2B)

기관 단위 도입을 위한 기본 구조:

```
무료 플랜: 1인 사용, 기록 100건/월
기관 플랜 (유료): 다수 상담원, 기록 무제한, 관리자 대시보드, 우선 지원
```

**지금 해야 할 것**:
- [ ] 기관 도입 문의 랜딩페이지 (1페이지) 제작
- [ ] 도입 의향 파악용 폼 (Google Form) 준비
- [ ] 기관 계약서 템플릿 초안 (NDA + 서비스 이용 계약)

---

## PART 4. 장기 준비 (6개월+) 🔵

### 4-1. 다기관 확장을 위한 멀티테넌시

- DB 레벨에서 `organization_id` 기반 데이터 격리 완성
- 기관별 독립 Vault 키 체계
- 기관별 사용량/청구 추적

### 4-2. 외부 보안 감사

- 아동 정보 처리 서비스로서 연 1회 외부 취약점 점검 권고
- OWASP Top 10 기준 자체 체크리스트 정기 검토
- Firebase 보안 규칙 감사

### 4-3. 재해 복구 계획 (DRP)

| 시나리오 | RTO (목표 복구 시간) | RPO (최대 데이터 손실 허용) |
|---------|--------------------|-----------------------------|
| 서버 재시작 | < 5분 | 0 (Railway 자동) |
| DB 단일 장애 | < 30분 | < 24시간 (일일 백업 기준) |
| Railway 리전 장애 | < 4시간 | < 24시간 |
| 전체 서비스 재구축 | < 1일 | < 1주 |

---

## 운영 체크리스트 (월별 루틴)

```
□ UptimeRobot 업타임 리포트 확인
□ Firebase Crashlytics 크래시 리포트 검토
□ Firebase Analytics KPI 지표 확인
□ DB 백업 파일 생성 여부 확인
□ retention_policy_log 정상 실행 여부 확인
□ 사용자 문의/피드백 응답 여부 확인
□ 보안 취약점 공지 (Firebase, Railway, npm) 확인
□ 앱스토어/플레이스토어 리뷰 확인
□ 서버 로그에서 비정상 패턴 확인 (과도한 요청, 인증 실패 등)
```

---

## 우선순위 요약

### 지금 당장 (이번 주)
1. **UptimeRobot 설정** — 30분, 무료, 가장 높은 위험 제거
2. **Railway 백업 확인 및 활성화** — DB 소실 위험 제거
3. **helmet + express-rate-limit 추가** — 보안 기본기

### 이번 달
4. 문의 채널 (최소: 이메일 버튼 1개)
5. 서버 배포 GitHub Actions 구성
6. 주간 KPI 확인 루틴 시작

### 다음 분기
7. 기관 관리자 기능 설계 시작
8. SLA 내부 목표 수립
9. Fastlane 앱 빌드 자동화

---

*작성: 2026-05-18*  
*다음 검토: 2026-08-18 (분기 후)*
