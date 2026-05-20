# Dash 주간 KPI 루틴

> **소요 시간**: 10분  
> **주기**: 매주 월요일  
> **목적**: 서비스 이상 조기 감지 + 성장 추세 파악

---

## Step 1. 서버 KPI 스냅샷 (1분)

터미널 또는 브라우저에서:

```bash
curl -H "x-admin-secret: $ADMIN_SECRET" https://dash.qpon/api/admin/kpi | jq
```

**응답 예시**:
```json
{
  "snapshot_at": "2026-05-19T09:00:00.000Z",
  "users": {
    "total": 12,
    "vault_activated": 10
  },
  "records": {
    "total": 87,
    "new_this_week": 14,
    "synced": 23,
    "reviewed": 31,
    "injected": 33,
    "shared": 45,
    "e2ee": 82,
    "injection_rate": "37.9%"
  }
}
```

---

## Step 2. 헬스 확인 (30초)

```bash
curl https://dash.qpon/health
# 기대값: { "status": "ok", "db": "connected", ... }
```

이상 시 → UptimeRobot 알럿 이미 왔을 것. Railway 로그 확인.

---

## Step 3. Firebase Analytics 확인 (3분)

[Firebase 콘솔 → dash-7cdea → Analytics → Events](https://console.firebase.google.com)

**이번 주 확인할 이벤트**:

| 이벤트 | 의미 | 이상 기준 |
|--------|------|----------|
| `dbrecord_sync_success` | 실제 사용량 | 전주 대비 -30% 이하면 점검 |
| `dbrecord_sync_failure` | 서버 오류 | 5건 이상이면 원인 조사 |
| `offline_banner_shown` | 서버 불안정 | 3회 이상이면 Railway 로그 확인 |
| `pin_set` | Vault 보안 활성화 | 신규 유저 중 미설정자 파악 |
| `login_success` | 신규/재접속 | 전주 대비 추세 확인 |

---

## Step 4. Crashlytics 확인 (2분)

[Firebase 콘솔 → Crashlytics](https://console.firebase.google.com)

- **이번 주 새 크래시**: 0건이 목표. 있으면 스택트레이스 확인.
- **크래시율**: < 0.5% (세션 기준)

---

## Step 5. 주간 기록 작성 (3분)

아래 표 복사 후 채우기 → 별도 시트 또는 노션에 누적 기록.

---

## 주간 KPI 기록 시트

| 날짜 | 신규 기록 | 누적 기록 | Injection율 | 신규 유저 | Vault 활성 | 크래시 | 특이사항 |
|------|----------|----------|------------|----------|-----------|--------|---------|
| 2026-05-19 | — | — | —% | — | — | — | 루틴 시작 |
| 2026-05-26 | | | | | | | |
| 2026-06-02 | | | | | | | |
| 2026-06-09 | | | | | | | |
| 2026-06-16 | | | | | | | |
| 2026-06-23 | | | | | | | |
| 2026-06-30 | | | | | | | |

---

## 이상 감지 시 행동 기준

| 증상 | 1순위 확인 | 2순위 확인 |
|------|-----------|-----------|
| `/health` → `db: disconnected` | Railway MySQL 상태 탭 | Railway 로그 → DB 연결 에러 |
| `dbrecord_sync_failure` 급증 | 서버 로그 타임스탬프 | Railway 재시작 이력 |
| `offline_banner_shown` 다수 | UptimeRobot 다운타임 기록 | Railway 배포 이력 (재시작 중 다운) |
| 크래시율 상승 | Crashlytics 스택트레이스 | 최근 앱 배포 버전 확인 |
| `new_this_week` 0건 | 사용자 직접 연락 | 앱 접근 가능 여부 확인 |

---

## 환경 변수 체크 (월 1회)

Railway 대시보드 → Variables에서 다음 항목 존재 여부 확인:

```
ADMIN_SECRET          ← KPI 엔드포인트 인증 (이번에 추가됨)
DB_HOST / DB_NAME     ← MySQL 연결
FIREBASE_SERVICE_ACCOUNT ← FCM 발송
ALLOWED_EMAIL_DOMAINS ← 도메인 화이트리스트 (선택)
```

---

## UptimeRobot 설정 가이드 (최초 1회)

1. [uptimerobot.com](https://uptimerobot.com) 가입 (무료)
2. **Add New Monitor**
   - Monitor Type: `HTTP(s)`
   - Friendly Name: `Dash Server`
   - URL: `https://dash.qpon/health`
   - Monitoring Interval: `5 minutes`
3. **Alert Contacts** → 이메일 추가
4. **키워드 모니터링** 추가 (선택)
   - Keyword: `"ok"`
   - Alert when: keyword not found

→ 서버 다운 시 5분 내 이메일 알럿 수신.

---

*최초 작성: 2026-05-20*
