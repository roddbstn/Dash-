// =============================================================================
// Jest 전역 mock 설정 — Chrome Extension API 환경 시뮬레이션
// =============================================================================

// chrome 전역 객체 모킹
global.chrome = {
  runtime: {
    onMessage: {
      addListener: jest.fn(),
    },
    sendMessage: jest.fn(),
    lastError: null,
  },
  storage: {
    local: {
      get: jest.fn(),
      set: jest.fn(),
    },
    session: {
      get: jest.fn(),
      set: jest.fn(),
      remove: jest.fn(),
    },
  },
  identity: {
    launchWebAuthFlow: jest.fn(),
    getAuthToken: jest.fn(),
  },
  tabs: {
    query: jest.fn(),
    sendMessage: jest.fn(),
  },
};
