// =============================================
// core/config.js — 비즈니스 설정 & 매핑 테이블
// 타겟 시스템의 코드 값이 변경되면 이 파일만 수정합니다.
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.Config = Object.freeze({

    // 대상 시스템 URL 패턴 (탭 스캔 시 사용)
    TARGET_URLS: ["*://localhost/*", "*://ncads.go.kr/*", "*://*.ncads.go.kr/*"],
    EXCLUDED_KEYWORDS: ['AnySignPlus'],

    // UI 매칭 색상
    MATCH_COLORS: ['#42a5f5', '#66bb6a', '#ffa726', '#ec407a', '#26a69a', '#ab47bc', '#8d6e63'],

    // 타겟 시스템 DOM 필드 ID
    FIELD_IDS: {
        SERVICE_DETAIL: 'svcClassDetailCd',
        RECIPIENT_TYPE: 'svcExecRecipientTyCd',
        RECIPIENT_ID: 'svcExecRecipientId',
        LOCATION: 'svcProvLocCd',
        LOCATION_ETC: 'svcProvLocEtc',
        PIC: 'picId',
        MEANS: 'provMeansCd',
        TYPE: 'provTyCd',
        PROV_COUNT: 'svcProvCnt',
        START_DATE: 'svcProvStartDate',
        END_DATE: 'svcProvEndDate',
        START_HH: 'svcProvStartHH',
        START_MI: 'svcProvStartMI',
        END_HH: 'svcProvEndHH',
        END_MI: 'svcProvEndMI',
        MOVE_TIME: 'mvmnReqreHr',
        DESC: 'svcProvDesc',
        OPINION: 'consOpn',
    },

    // 수동 폼 필드 목록 (복사 기능에서 사용)
    MANUAL_FORM_FIELDS: [
        'provCd', 'provTyCd', 'svcClassDetailCd', 'svcExecRecipientTyCd',
        'svcExecRecipientId', 'provMeansCd', 'svcProvLocCd', 'svcProvLocEtc',
        'startDate', 'startHH', 'startMI', 'endDate', 'endHH', 'endMI',
        'cnt_val', 'mvmnReqreHr_val', 'desc_val', 'opn_val'
    ],

    // === 값 매핑 테이블 (content.js에서 사용) ===

    // 제공구분 (Radio)
    PROV_CD_MAP: { '제공': 'A', '부가업무': 'B', '거부': 'C' },

    // 서비스제공방법 (Select)
    MEANS_MAP: { '전화': 'A', '내방': 'B', '방문': 'C' },

    // 제공장소 (Select)
    LOCATION_MAP: { '기관내': 'A', '아동가정': 'B', '유관기관': 'C', '기타': 'X' },

    // 제공서비스 (Select) — 시스템 코드 매핑
    SERVICE_MAP: {
        '사례회의': '060524',
        '식사(식품)지원_식품지원': '010201',
        '생활용품지원_기타생활용품지원': '010501',
        '생활용품지원_의류지원': '010509',
        '복합지원_복지서비스물제공': '010703',
        '안전 및 인권교육_성폭력(예방)교육': '060103',
        '안전 및 인권교육_아동권리교육': '060101',
        '안전 및 인권교육_안전교육': '060104',
        '안전 및 인권교육_학대예방교육': '060102',
        '아동학대대상자 및 가족 지원_아동 안전점검 및 상담': '060501',
    },

    // === Value Fingerprint — 엑셀 스마트 파싱용 ===
    // 각 필드가 가질 수 있는 유효 값 집합(지문)을 정의합니다.
    // 엑셀 파서가 데이터 값을 이 지문과 대조하여 행↔필드를 자율 판단합니다.
    FIELD_FINGERPRINTS: [
        // 1순위: 유효 값 목록이 명확한 필드 (exact match)
        { field: 'provCd_val', type: 'exact', values: ['제공', '부가업무', '거부'] },
        { field: 'provMeansCd_val', type: 'exact', values: ['전화', '내방', '방문'] },
        { field: 'loc_val', type: 'exact', values: ['기관내', '아동가정', '유관기관', '기타'] },
        { field: 'svcClassDetailCd_val', type: 'service' },  // SERVICE_MAP의 키와 부분 매칭

        // 2순위: 정규식 패턴으로 식별 가능한 필드
        { field: 'dateTime_val', type: 'regex', pattern: '\\d{4}[-/.]\\d{1,2}[-/.]\\d{1,2}' },

        // 3순위: 자유 텍스트 (어떤 지문에도 매칭 안 되는 행)
        // desc_val(서비스내용)이 opn_val(소견)보다 먼저 나온다고 가정
        { field: 'desc_val', type: 'freetext', priority: 1 },
        { field: 'opn_val', type: 'freetext', priority: 2 },
    ],

    // A열 헤더 텍스트 보조 매핑 (Fingerprint 매칭 실패 시 fallback)
    HEADER_HINTS: {
        '제공구분': 'provCd_val',
        '제공유형': 'provTyCd_val',
        '유형': 'provTyCd_val',
        '제공방법': 'provMeansCd_val',
        '제공서비스': 'svcClassDetailCd_val',
        '서비스명': 'svcClassDetailCd_val',
        '대상자': 'recipient_val',
        '일시': 'dateTime_val',
        '날짜': 'dateTime_val',
        '장소': 'loc_val',
        '기타': 'locEtc_val_raw',
        '담당자': 'pic_val',
        '횟수': 'cnt_val',
        '내용': 'desc_val',
        '소견': 'opn_val',
        '이동': 'mvmnReqreHr_val',
    },
});
