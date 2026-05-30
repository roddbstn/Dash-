# Dash QA — 부하 테스트 (k6)

## 시나리오 구성

| # | 시나리오 | 목적 | VU | 소요시간 |
|---|---------|------|----|---------|
| 01 | Baseline | 기준선 응답시간 측정 | 10 | 7분 |
| 02 | Load | 실사용 혼합 트래픽 (모바일/리뷰어/SSE) | 200 | 12분 |
| 03 | Stress | 한계점 탐색 · DB 풀 포화 | 500 | 17분 |
| 04 | Spike | 갑작스러운 폭증 대응 확인 | 500 | 8분 |
| 05 | Soak | 메모리 누수 · 장기 안정성 | 50 | 30분~4h |
| 06 | Rate Limit | 429 동작 · Retry-After 헤더 검증 | 10 | 10분 |

## 설치 및 실행

```bash
# k6 설치 (macOS)
brew install k6

# 환경변수 설정
cp qa/load-tests/.env.test.example qa/load-tests/.env.test
# .env.test 파일에 실제 토큰/UID/이메일 입력

# 권한 부여
chmod +x qa/load-tests/run.sh

# 실행
./qa/load-tests/run.sh baseline    # 기준선 측정
./qa/load-tests/run.sh load        # 부하 테스트
./qa/load-tests/run.sh ratelimit   # Rate Limit 검증
./qa/load-tests/run.sh all         # 3가지 순차 실행
```

## 병목 구간 예상 분석

### DB 커넥션 풀 (max: 5)
- 동시 요청 5개 초과 시 쿼리 대기 → 응답시간 급증
- `03_stress.js`의 300~400 VU 구간에서 `ETIMEDOUT` / `ER_CON_COUNT` 에러 발생 예상
- **해결 방향**: `connectionLimit: 5` → `20~50`으로 상향, 또는 읽기 쿼리에 캐시 레이어 추가

### Rate Limit (300 req / 15분)
- 단일 IP 기준이므로 VU 수 증가 → 429 도달 속도 빠름
- `06_rate_limit.js`로 정확한 임계 요청 수 확인
- **해결 방향**: 인증된 유저 기반 rate limit (`keyGenerator: req.user.uid`) 로 전환 검토

### SSE 롱커넥션
- Node.js 단일 스레드 특성상 SSE 연결 수 증가 시 이벤트 루프 블로킹 위험
- `02_load.js`의 `sseJourney`에서 concurrent connection 수 모니터링
- **해결 방향**: SSE 전용 worker thread 또는 Redis Pub/Sub 기반 이벤트 분산

### Firebase 토큰 검증
- 매 요청마다 Firebase Admin SDK가 토큰 검증 (네트워크 I/O)
- **해결 방향**: 검증된 토큰을 단기 캐싱 (TTL 5분) 하여 외부 호출 감소

## SLA 기준

| 지표 | 목표값 |
|------|--------|
| p95 응답시간 | < 2,000ms |
| p99 응답시간 | < 5,000ms |
| 에러율 | < 1% |
| Rate Limit 후 Retry-After | 헤더 필수 포함 |
