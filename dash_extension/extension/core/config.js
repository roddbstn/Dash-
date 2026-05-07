// =============================================
// core/config.js — 비즈니스 설정 & 매핑 테이블
// 타겟 시스템의 코드 값이 변경되면 이 파일만 수정합니다.
// =============================================
window.DBAuto = window.DBAuto || {};

window.DBAuto.Config = Object.freeze({

    // 대상 시스템 URL 패턴 (탭 스캔 시 사용)
    TARGET_URLS: ["*://localhost:*/*", "*://localhost/*", "*://ncads.go.kr/*", "*://*.ncads.go.kr/*"],
    EXCLUDED_KEYWORDS: ['AnySignPlus'],

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

    // === 값 매핑 테이블 (content.js에서 사용) ===

    // 제공구분 (Radio)
    PROV_CD_MAP: { '제공': 'A', '부가업무': 'B', '거부': 'C' },

    // 서비스제공방법 (Select)
    MEANS_MAP: { '전화': 'A', '내방': 'B', '방문': 'C' },

    // 서비스제공유형 (Select)
    TYPE_MAP: { '아보전': 'A', '연계': 'B', '통합': 'C' },

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
        // 모바일 앱에서 사용하는 간소화된 서비스명도 매핑
        '의류지원': '010509',
        '성폭력(예방)교육': '060103',
        '아동권리교육': '060101',
        '안전교육': '060104',
        '학대예방교육': '060102',
        '아동 안전점검 및 상담': '060501',
        '식품지원': '010201',
        '복지서비스정보물제공': '010703',
        '아동 양육기술 상담/교육': '060501',
    },
});
