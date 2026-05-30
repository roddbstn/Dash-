#!/bin/bash
# ============================================================
# Dash QA - k6 Load Test Runner
# ============================================================
# 사용법:
#   chmod +x qa/load-tests/run.sh
#   ./qa/load-tests/run.sh [scenario] [options]
#
# 예시:
#   ./qa/load-tests/run.sh baseline
#   ./qa/load-tests/run.sh load
#   ./qa/load-tests/run.sh stress   --env BASE_URL=https://staging.dash.qpon
#   ./qa/load-tests/run.sh all
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIOS_DIR="$SCRIPT_DIR/scenarios"
RESULTS_DIR="$SCRIPT_DIR/results"

mkdir -p "$RESULTS_DIR"

# ── 환경변수 설정 (필수: .env.test 파일 생성 후 사용) ─────
if [ -f "$SCRIPT_DIR/.env.test" ]; then
  source "$SCRIPT_DIR/.env.test"
fi

BASE_URL="${BASE_URL:-https://dash.qpon}"
TEST_TOKEN="${TEST_TOKEN:-}"
TEST_USER_ID="${TEST_USER_ID:-}"
TEST_EMAIL="${TEST_EMAIL:-}"
TEST_SHARE_TOKEN="${TEST_SHARE_TOKEN:-}"

# k6 설치 확인
if ! command -v k6 &> /dev/null; then
  echo "❌  k6가 설치되어 있지 않습니다."
  echo "   설치 방법:"
  echo "   brew install k6              (macOS)"
  echo "   choco install k6             (Windows)"
  echo "   sudo apt-get install k6      (Ubuntu/Debian)"
  exit 1
fi

K6_COMMON_ARGS=(
  -e "BASE_URL=$BASE_URL"
  -e "TEST_TOKEN=$TEST_TOKEN"
  -e "TEST_USER_ID=$TEST_USER_ID"
  -e "TEST_EMAIL=$TEST_EMAIL"
  -e "TEST_SHARE_TOKEN=$TEST_SHARE_TOKEN"
)

run_scenario() {
  local name="$1"
  local file="$2"
  local extra_args=("${@:3}")

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ▶  Running: $name"
  echo "     Target:  $BASE_URL"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  k6 run \
    "${K6_COMMON_ARGS[@]}" \
    "${extra_args[@]}" \
    --out "json=$RESULTS_DIR/${name}_$(date +%Y%m%d_%H%M%S).json" \
    "$file"
}

SCENARIO="${1:-help}"

case "$SCENARIO" in
  baseline)
    run_scenario "baseline" "$SCENARIOS_DIR/01_baseline.js"
    ;;
  load)
    run_scenario "load" "$SCENARIOS_DIR/02_load.js"
    ;;
  stress)
    echo "⚠️  Stress Test는 스테이징 환경에서만 실행하세요!"
    read -p "계속하시겠습니까? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
    run_scenario "stress" "$SCENARIOS_DIR/03_stress.js"
    ;;
  spike)
    echo "⚠️  Spike Test는 스테이징 환경에서만 실행하세요!"
    read -p "계속하시겠습니까? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
    run_scenario "spike" "$SCENARIOS_DIR/04_spike.js"
    ;;
  soak)
    DURATION="${DURATION:-30m}"
    run_scenario "soak" "$SCENARIOS_DIR/05_soak.js" -e "DURATION=$DURATION"
    ;;
  ratelimit)
    run_scenario "rate_limit" "$SCENARIOS_DIR/06_rate_limit.js"
    ;;
  all)
    echo "⚠️  all 모드: baseline → load → rate_limit 순으로 실행 (stress/spike 제외)"
    run_scenario "baseline"   "$SCENARIOS_DIR/01_baseline.js"
    run_scenario "load"       "$SCENARIOS_DIR/02_load.js"
    run_scenario "rate_limit" "$SCENARIOS_DIR/06_rate_limit.js"
    echo ""
    echo "✅  전체 테스트 완료. 결과: $RESULTS_DIR/"
    ;;
  help|*)
    echo ""
    echo "Dash QA Load Test Runner"
    echo ""
    echo "사용법: ./run.sh [scenario]"
    echo ""
    echo "Scenarios:"
    echo "  baseline   - 기준선 측정 (VU 10명, 7분)"
    echo "  load       - 혼합 부하 테스트 (VU 200명, 12분)"
    echo "  stress     - 한계점 탐색 (VU 500명 ⚠️ 스테이징 전용)"
    echo "  spike      - 트래픽 폭증 테스트 (⚠️ 스테이징 전용)"
    echo "  soak       - 장기 안정성 테스트 (기본 30분, DURATION=2h 설정 가능)"
    echo "  ratelimit  - Rate Limit 동작 검증"
    echo "  all        - baseline + load + ratelimit 순차 실행"
    echo ""
    echo "환경변수 (qa/load-tests/.env.test 파일 생성):"
    echo "  BASE_URL=https://staging.dash.qpon"
    echo "  TEST_TOKEN=<firebase_id_token>"
    echo "  TEST_USER_ID=<firebase_uid>"
    echo "  TEST_EMAIL=<test_email>"
    echo "  TEST_SHARE_TOKEN=<share_token>"
    ;;
esac
