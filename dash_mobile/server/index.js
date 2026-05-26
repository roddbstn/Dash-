require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const mysql = require('mysql2/promise');
const cron = require('node-cron');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

const app = express();
const port = process.env.PORT || 3000;

// Railway 등 리버스 프록시 환경에서 X-Forwarded-For 헤더 신뢰 (rate-limit IP 식별용)
app.set('trust proxy', 1);

// 치명적 에러 발생 시 로그를 남기고 안전하게 처리
process.on('uncaughtException', (err) => {
  console.error('💥 Uncaught Exception:', err);
});
process.on('unhandledRejection', (reason, promise) => {
  console.error('💥 Unhandled Rejection at:', promise, 'reason:', reason);
});

const path = require('path');
const admin = require('firebase-admin');

// --- Firebase Admin (FCM) Setup ---
let fcmInitialized = false;
try {
  // Try loading from environment variable (STRING JSON) or local file
  let serviceAccount;
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    // Railway/Env var newline fix for JWT signature
    if (serviceAccount.private_key) {
      serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, '\n');
    }
  } else {
    serviceAccount = require('./service-account-file.json');
  }

  if (serviceAccount) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    fcmInitialized = true;
    console.log('🔥 Firebase Admin (FCM) Initialized');
  }
} catch (err) {
  console.warn('⚠️  Firebase Service Account not found OR invalid. Push notifications will be disabled.');
  console.warn('Set FIREBASE_SERVICE_ACCOUNT environment variable with the JSON content to enable FCM in production.');
}
// Middleware
// CORS: 모바일 앱(Origin 없음), Chrome 확장프로그램(ID 화이트리스트), 리뷰어 사이트(동일 서버) 허용
const ALLOWED_ORIGINS = [
  'https://dash.qpon',
  'http://localhost:3000',
  process.env.ALLOWED_ORIGIN,
].filter(Boolean);

// 허용할 Chrome 확장 ID 목록 (환경변수로 추가 가능)
const ALLOWED_EXTENSION_IDS = [
  'dpncpmegjlgknkagcfjdaccbgmjncdef', // Dash 확장프로그램 (웹 스토어 프로덕션)
  'nmdfmegmehnkacdeekekchjfcijpbmcp', // Dash 확장프로그램 (개발자 모드 테스트)
  'iamgpaookjndjpcigifbfdmmbfijcane', // Dash 확장프로그램 (구 ID)
  ...(process.env.ALLOWED_EXTENSION_IDS || '').split(',').map(id => id.trim()).filter(Boolean),
];

// ── 보안 헤더 (helmet) ────────────────────────────────────────────────────────
app.use(helmet({
  contentSecurityPolicy: false,       // SSE / 리뷰어 사이트 인라인 스크립트 호환
  crossOriginEmbedderPolicy: false,   // Firebase SDK 로드 허용
}));

app.use(cors({
  origin: (origin, callback) => {
    if (!origin) return callback(null, true);                         // 모바일 앱 / Origin 없음
    if (origin.startsWith('chrome-extension://')) {
      const extId = origin.replace('chrome-extension://', '');
      if (ALLOWED_EXTENSION_IDS.includes(extId)) return callback(null, true);
      return callback(new Error('CORS: 허용되지 않은 확장프로그램입니다.'));
    }
    if (ALLOWED_ORIGINS.includes(origin)) return callback(null, true); // 리뷰어 사이트 (same-server)
    return callback(new Error('CORS: 허용되지 않은 출처입니다.'));
  },
}));
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '10mb' }));
app.use((req, res, next) => { res.setHeader('Referrer-Policy', 'no-referrer'); next(); });
app.use(express.static(path.join(__dirname, 'reviewer_site'))); // Serve static files

// ── API Rate Limiting ──────────────────────────────────────────────────────────
// 글로벌: 15분당 300회 (정상 사용 기준 넉넉히)
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: '요청이 너무 많습니다. 잠시 후 다시 시도해주세요.' },
  skip: (req) => req.path === '/health', // 헬스체크는 제외
});
app.use('/api', globalLimiter);

// 인증 엔드포인트: 15분당 30회 (브루트포스 방어)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: '인증 시도가 너무 많습니다. 잠시 후 다시 시도해주세요.' },
});
app.use('/api/users/login', authLimiter);
app.use('/api/users/fcm_token', authLimiter);
app.use('/api/records/user/all', authLimiter); // 전체 삭제: 브루트포스 방어

// 에러 메시지 — 프로덕션에서는 내부 상세 노출 차단
const safeError = (err) =>
  process.env.NODE_ENV === 'production' ? '서버 오류가 발생했습니다.' : err.message;

// ── 보안 설정 ────────────────────────────────────────────────────────────────
// 허용할 이메일 도메인 목록 (쉼표 구분, 비어있으면 제한 없음)
// 예: ALLOWED_EMAIL_DOMAINS=ncrc.or.kr,welfare.or.kr
const ALLOWED_EMAIL_DOMAINS = (process.env.ALLOWED_EMAIL_DOMAINS || '')
  .split(',').map(d => d.trim()).filter(Boolean);

// Firebase ID Token 검증 미들웨어 (모바일 전용 API 보호)
async function verifyFirebaseAuth(req, res, next) {
  // Firebase Admin 미초기화 시 (로컬 개발환경) — 인증 건너뜀
  if (!fcmInitialized) {
    console.warn('⚠️  [AUTH] Firebase Admin 미초기화 — 토큰 검증 건너뜀 (개발 모드)');
    return next();
  }

  // SSE 요청은 쿼리 파라미터로도 토큰을 받음 (EventSource는 헤더 불가)
  const authHeader = req.headers['authorization'];
  const queryToken = req.query.token;
  const rawToken = authHeader?.startsWith('Bearer ') ? authHeader.split(' ')[1] : queryToken;

  if (!rawToken) {
    console.warn(`⚠️  [AUTH] 토큰 없음 — ${req.method} ${req.path}`);
    return res.status(401).json({ error: '인증이 필요합니다.' });
  }

  // Firebase ID Token은 JWT 형식(eyJ...)이므로 tokeninfo 불필요 — 바로 Firebase 검증
  // Google OAuth Access Token(ya29....)은 Chrome 확장 프로그램에서만 사용
  const isFirebaseJwt = rawToken.startsWith('eyJ');

  if (!isFirebaseJwt) {
    // Google OAuth 토큰 검증 (Chrome 확장프로그램용)
    try {
      const googleRes = await fetch(`https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=${rawToken}`);
      if (googleRes.ok) {
        const info = await googleRes.json();
        if (info.email) {
          if (ALLOWED_EMAIL_DOMAINS.length > 0) {
            const domain = info.email.split('@')[1] || '';
            if (!ALLOWED_EMAIL_DOMAINS.includes(domain)) {
              console.warn(`🚫 [AUTH] 차단된 도메인: ${domain} (${info.email})`);
              return res.status(403).json({ error: '접근이 허용되지 않은 계정입니다.' });
            }
          }
          req.firebaseUser = { email: info.email, uid: info.user_id || info.email };
          return next();
        }
      }
    } catch (googleErr) {
      // Google OAuth 검증 실패 시 Firebase 토큰으로 재시도
    }
  }

  // Firebase ID 토큰 검증 (모바일 앱용)
  try {
    const decoded = await admin.auth().verifyIdToken(rawToken);

    if (ALLOWED_EMAIL_DOMAINS.length > 0) {
      const email = decoded.email || '';
      const domain = email.split('@')[1] || '';
      if (!ALLOWED_EMAIL_DOMAINS.includes(domain)) {
        console.warn(`🚫 [AUTH] 차단된 도메인: ${domain} (${email})`);
        return res.status(403).json({ error: '접근이 허용되지 않은 계정입니다.' });
      }
    }

    req.firebaseUser = decoded;
    next();
  } catch (err) {
    console.warn(`⚠️  [AUTH] 유효하지 않은 토큰: ${err.message}`);
    return res.status(401).json({ error: '유효하지 않은 인증 토큰입니다.' });
  }
}
// ─────────────────────────────────────────────────────────────────────────────

// --- SSE Clients ---
let sseClients = [];

function broadcastEvent(event, data) {
  const deadIds = [];
  sseClients.forEach(client => {
    if (!client.email || (data.user_email && client.email === data.user_email)) {
      try {
        client.res.write(`data: ${JSON.stringify({ event, ...data })}\n\n`);
      } catch (e) {
        // write 실패 = 끊어진 연결, 제거 대상 표시
        deadIds.push(client.id);
      }
    }
  });
  if (deadIds.length > 0) {
    sseClients = sseClients.filter(c => !deadIds.includes(c.id));
    console.log(`🧹 Dead SSE clients removed: ${deadIds.length} (Remaining: ${sseClients.length})`);
  }
}

// Database Connection
const pool = mysql.createPool({
  host: process.env.MYSQLHOST || process.env.DB_HOST || 'localhost',
  port: process.env.MYSQLPORT || process.env.DB_PORT || 3306,
  user: process.env.MYSQLUSER || process.env.DB_USER,
  password: process.env.MYSQLPASSWORD || process.env.DB_PASSWORD,
  database: process.env.MYSQLDATABASE || process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 5,
  queueLimit: 0,
  dateStrings: true
});

// ─── DB 헬퍼: 타임아웃 포함 쿼리 ──────────────────────────────────────────
const _dbQuery = pool.query.bind(pool);
function queryWithTimeout(sql, params, ms = 8000) {
  return Promise.race([
    _dbQuery(sql, params),
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`DB query timeout after ${ms}ms: ${sql.substring(0, 60)}`)), ms)
    ),
  ]);
}

// ─── User 헬퍼: UID로 사용자 조회, 없으면 이메일로 폴백 ──────────────────
async function resolveUserId(uid) {
  return uid;
}

// ─── User 헬퍼: 없으면 INSERT IGNORE로 생성, 이메일 충돌 시 기존 ID 반환 ──
async function ensureUserExists(uid, email, name) {
  const resolvedEmail = email || `user_${uid.substring(0, 8)}@gmail.com`;
  const [rows] = await queryWithTimeout('SELECT id FROM dash_users WHERE id = ?', [uid]);
  if (rows.length > 0) {
    if (name) {
      await queryWithTimeout(
        'UPDATE dash_users SET name = ? WHERE id = ? AND (name IS NULL OR name = email OR name = "")',
        [name, uid]
      );
    }
    return uid;
  }
  console.log(`👤 New user detected (${uid}), creating user record...`);
  const resolvedName = name || resolvedEmail.split('@')[0];
  await queryWithTimeout(
    'INSERT IGNORE INTO dash_users (id, email, name, organization_id) VALUES (?, ?, ?, ?)',
    [uid, resolvedEmail, resolvedName, 'DEFAULT_ORG']
  );
  // INSERT IGNORE가 무시된 경우(이메일 중복) — 이메일로 기존 사용자의 id를 찾아 사용
  const [check] = await queryWithTimeout('SELECT id FROM dash_users WHERE id = ?', [uid]);
  if (check.length > 0) return uid;
  const [byEmail] = await queryWithTimeout('SELECT id FROM dash_users WHERE email = ?', [resolvedEmail]);
  if (byEmail.length > 0) {
    console.log(`🔄 Email conflict — using existing user id: ${byEmail[0].id}`);
    return byEmail[0].id;
  }
  return uid;
}

// reviewer_user_id 컬럼이 없으면 자동 추가 (마이그레이션)
// MySQL 8.0은 IF NOT EXISTS 미지원 → ER_DUP_FIELDNAME(중복)만 무시
// record_edit_history 테이블 생성 (수정 히스토리)
pool.query(`
  CREATE TABLE IF NOT EXISTS record_edit_history (
    id INT AUTO_INCREMENT PRIMARY KEY,
    share_token VARCHAR(255) NOT NULL,
    editor_user_id VARCHAR(255),
    editor_name VARCHAR(100),
    action ENUM('reviewed','saved','synced') DEFAULT 'saved',
    service_description_before TEXT,
    agent_opinion_before TEXT,
    service_description_snapshot TEXT,
    agent_opinion_snapshot TEXT,
    encrypted_blob_snapshot TEXT,
    created_at DATETIME DEFAULT NOW(),
    INDEX idx_reh_token (share_token),
    INDEX idx_reh_created (created_at)
  )
`).catch(err => console.error('[migration] record_edit_history 테이블 생성 실패:', err.message));

// record_edit_history _before 컬럼 마이그레이션 (기존 테이블에 추가)
pool.query(`ALTER TABLE record_edit_history ADD COLUMN service_description_before TEXT AFTER action`)
  .catch(() => {}); // 이미 존재하면 무시
pool.query(`ALTER TABLE record_edit_history ADD COLUMN agent_opinion_before TEXT AFTER service_description_before`)
  .catch(() => {});

// share_viewers 테이블 생성 (공유 링크 접근자 이력)
pool.query(`
  CREATE TABLE IF NOT EXISTS share_viewers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    share_token VARCHAR(255) NOT NULL,
    user_id VARCHAR(255) NOT NULL,
    name VARCHAR(100),
    first_accessed_at DATETIME DEFAULT NOW(),
    UNIQUE KEY uq_token_user (share_token, user_id),
    INDEX idx_sv_token (share_token)
  )
`).catch(err => console.error('[migration] share_viewers 테이블 생성 실패:', err.message));

// counselors 테이블 생성 (없으면)
pool.query(`
  CREATE TABLE IF NOT EXISTS counselors (
    id VARCHAR(64) PRIMARY KEY,
    user_id VARCHAR(128) NOT NULL,
    name VARCHAR(100) NOT NULL,
    is_self TINYINT(1) DEFAULT 0,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_counselor_user (user_id)
  )
`).catch(err => console.error('[migration] counselors 테이블 생성 실패:', err.message));

// cases 테이블에 counselor_id 컬럼 추가
pool.query("ALTER TABLE cases ADD COLUMN counselor_id VARCHAR(64) DEFAULT NULL")
  .catch(err => {
    if (err.code !== 'ER_DUP_FIELDNAME') {
      console.error('[migration] counselor_id 컬럼 추가 실패:', err.message);
    }
  });

pool.query("ALTER TABLE service_drafts ADD COLUMN reviewer_user_id VARCHAR(36) DEFAULT NULL")
  .catch(err => {
    if (err.code !== 'ER_DUP_FIELDNAME') {
      console.error('[migration] reviewer_user_id 컬럼 추가 실패:', err.message);
    }
  });

// [Security] encryption_key는 더 이상 서버에 저장하지 않음 — 컬럼은 레거시 호환을 위해 유지(NULL)
// 신규 레코드는 encryption_key를 서버로 전송하지 않으며, 키는 PIN-encrypted Vault에만 보관

// Phase 3-A: 공유 링크 만료 컬럼 추가
pool.query("ALTER TABLE service_drafts ADD COLUMN share_expires_at DATETIME DEFAULT NULL")
  .catch(err => {
    if (err.code !== 'ER_DUP_FIELDNAME') {
      console.error('[migration] share_expires_at 컬럼 추가 실패:', err.message);
    }
  });

// 기입자 이름 컬럼 추가
pool.query("ALTER TABLE service_drafts ADD COLUMN injected_by_name VARCHAR(100) DEFAULT NULL")
  .catch(err => { if (err.code !== 'ER_DUP_FIELDNAME') console.error('[migration] injected_by_name 추가 실패:', err.message); });

// 동행자가 공유받은 DB를 목록에서 숨길 수 있도록 (원본 보존, 담당자 데이터 무영향)
pool.query("ALTER TABLE share_viewers ADD COLUMN dismissed_at DATETIME DEFAULT NULL")
  .catch(err => { if (err.code !== 'ER_DUP_FIELDNAME') console.error('[migration] dismissed_at 추가 실패:', err.message); });

// is_shared_db: DB 생성 시 공유 목적인지 여부 (0=내 DB, 1=공유할 DB)
pool.query("ALTER TABLE service_drafts ADD COLUMN is_shared_db TINYINT(1) DEFAULT 0")
  .catch(err => { if (err.code !== 'ER_DUP_FIELDNAME') console.error('[migration] is_shared_db 추가 실패:', err.message); });

// Phase 4: 유저 활동 추적 컬럼 추가 (KPI 대시보드용)
pool.query("ALTER TABLE dash_users ADD COLUMN last_login_at DATETIME DEFAULT NULL")
  .catch(err => { if (err.code !== 'ER_DUP_FIELDNAME') console.error('[migration] last_login_at 추가 실패:', err.message); });
pool.query("ALTER TABLE dash_users ADD COLUMN login_count INT DEFAULT 0")
  .catch(err => { if (err.code !== 'ER_DUP_FIELDNAME') console.error('[migration] login_count 추가 실패:', err.message); });

// Phase 3-B: Vault 접근 Rate Limiting (메모리 기반, 서버 재시작 시 초기화)
const vaultAttempts = new Map(); // uid → { count, windowStart }
const VAULT_MAX_REQUESTS = 30;  // 10분당 최대 30회 (extension 5분 throttle 고려)
const VAULT_WINDOW_MS = 10 * 60 * 1000;

// --- API Endpoints ---

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'reviewer_site', 'index.html'));
});

app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'reviewer_site', 'admin.html'));
});

// 앱에서 /share?token=... 로 오는 요청을 /?token=... 으로 리다이렉트
app.get('/share', (req, res) => {
  const token = req.query.token;
  if (token) {
    return res.redirect(301, `/?token=${token}`);
  }
  res.redirect(301, '/');
});

// [공통] 서버 상태 확인 (UptimeRobot 등 외부 모니터링 대상)
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({
      status: 'ok',
      db: 'connected',
      uptime: Math.floor(process.uptime()),
      time: new Date().toISOString(),
    });
  } catch (err) {
    console.error('❌ [HEALTH] DB connection failed:', err.message);
    res.status(503).json({
      status: 'error',
      db: 'disconnected',
      time: new Date().toISOString(),
    });
  }
});

// [Admin] 종합 KPI 대시보드 (ADMIN_SECRET 헤더 인증)
app.get('/api/admin/kpi', async (req, res) => {
  const secret = req.headers['x-admin-secret'];
  if (!secret || secret !== process.env.ADMIN_SECRET) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // 개별 쿼리 실패 시 기본값 반환 (컬럼 마이그레이션 중 안전성 확보)
  async function safe(fn, fallback) {
    try { return await fn(); } catch (e) { console.warn('[KPI] query skipped:', e.message); return fallback; }
  }

  // ── 유저 기본 통계 ─────────────────────────────────────────────
  const [[userBase]] = await pool.query(`SELECT COUNT(*) AS total_users FROM dash_users`);
  const totalUsers = Number(userBase.total_users) || 0;

  // ── DAU / WAU / MAU (last_login_at 컬럼 없으면 0) ────────────
  const dauWauMau = await safe(async () => {
    const [[r]] = await pool.query(`
      SELECT
        SUM(last_login_at >= DATE_SUB(NOW(), INTERVAL 1 DAY))  AS dau,
        SUM(last_login_at >= DATE_SUB(NOW(), INTERVAL 7 DAY))  AS wau,
        SUM(last_login_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)) AS mau
      FROM dash_users
    `);
    return { dau: Number(r.dau) || 0, wau: Number(r.wau) || 0, mau: Number(r.mau) || 0 };
  }, { dau: 0, wau: 0, mau: 0 });

  const [[vaultStats]] = await pool.query(
    `SELECT COUNT(*) AS vault_activated FROM user_key_vault WHERE encrypted_vault IS NOT NULL`
  );

  // ── 사례 통계 ──────────────────────────────────────────────────
  const [[caseStats]] = await pool.query(`SELECT COUNT(*) AS total_cases FROM cases`);

  // ── 기록 통계 ──────────────────────────────────────────────────
  const [[recStats]] = await pool.query(`
    SELECT
      COUNT(*)                          AS total_records,
      SUM(status = 'Synced')            AS synced,
      SUM(status = 'Reviewed')          AS reviewed,
      SUM(status = 'Injected')          AS injected,
      SUM(share_token IS NOT NULL)      AS shared,
      SUM(reviewer_user_id IS NOT NULL) AS reviewer_linked,
      SUM(encrypted_blob IS NOT NULL)   AS e2ee
    FROM service_drafts
  `);
  const [[weeklyRec]] = await pool.query(
    `SELECT COUNT(*) AS new_this_week FROM service_drafts WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)`
  );

  // ── 유저별 평균 ────────────────────────────────────────────────
  const [[perUserAvg]] = await pool.query(`
    SELECT
      ROUND(AVG(case_cnt), 2)   AS avg_cases_per_user,
      ROUND(AVG(record_cnt), 2) AS avg_records_per_user
    FROM (
      SELECT u.id,
        COUNT(DISTINCT c.id)  AS case_cnt,
        COUNT(DISTINCT sd.id) AS record_cnt
      FROM dash_users u
      LEFT JOIN cases c ON c.user_id = u.id
      LEFT JOIN service_drafts sd ON sd.case_id = c.id
      GROUP BY u.id
    ) t
  `);

  // ── 공유 비율 ──────────────────────────────────────────────────
  const [[sharePerDb]] = await pool.query(`
    SELECT ROUND(AVG(share_ratio), 3) AS avg_share_ratio_per_user
    FROM (
      SELECT u.id,
        CASE WHEN COUNT(sd.id) = 0 THEN 0
             ELSE SUM(sd.share_token IS NOT NULL) / COUNT(sd.id)
        END AS share_ratio
      FROM dash_users u
      LEFT JOIN cases c ON c.user_id = u.id
      LEFT JOIN service_drafts sd ON sd.case_id = c.id
      GROUP BY u.id
    ) t
  `);

  // ── 유저 리스트 (last_login_at / login_count 없으면 NULL 안전 처리) ─
  const userList = await safe(async () => {
    const [rows] = await pool.query(`
      SELECT
        u.id,
        COALESCE(u.name, '이름 없음') AS name,
        u.email,
        u.last_login_at,
        COALESCE(u.login_count, 0)   AS login_count,
        u.created_at,
        COUNT(DISTINCT c.id)         AS case_count,
        COUNT(DISTINCT sd.id)        AS record_count
      FROM dash_users u
      LEFT JOIN cases c ON c.user_id = u.id
      LEFT JOIN service_drafts sd ON sd.case_id = c.id
      GROUP BY u.id, u.name, u.email, u.last_login_at, u.login_count, u.created_at
      ORDER BY u.last_login_at DESC
    `);
    return rows;
  }, await safe(async () => {
    // fallback: last_login_at/login_count 컬럼 없는 경우
    const [rows] = await pool.query(`
      SELECT
        u.id,
        COALESCE(u.name, '이름 없음') AS name,
        u.email,
        NULL AS last_login_at,
        0    AS login_count,
        u.created_at,
        COUNT(DISTINCT c.id)  AS case_count,
        COUNT(DISTINCT sd.id) AS record_count
      FROM dash_users u
      LEFT JOIN cases c ON c.user_id = u.id
      LEFT JOIN service_drafts sd ON sd.case_id = c.id
      GROUP BY u.id, u.name, u.email, u.created_at
      ORDER BY u.created_at DESC
    `);
    return rows;
  }, []));

  // ── 시계열 ─────────────────────────────────────────────────────
  const [monthlyRecords] = await pool.query(`
    SELECT DATE_FORMAT(created_at, '%Y-%m') AS month, COUNT(*) AS count
    FROM service_drafts
    WHERE created_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
    GROUP BY DATE_FORMAT(created_at, '%Y-%m')
    ORDER BY month ASC
  `);
  const [monthlyUsers] = await pool.query(`
    SELECT DATE_FORMAT(created_at, '%Y-%m') AS month, COUNT(*) AS count
    FROM dash_users
    WHERE created_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
    GROUP BY DATE_FORMAT(created_at, '%Y-%m')
    ORDER BY month ASC
  `);
  const [weeklyActivity] = await pool.query(`
    SELECT
      DATE_FORMAT(DATE_SUB(sd.created_at, INTERVAL WEEKDAY(sd.created_at) DAY), '%Y-%m-%d') AS week_start,
      COUNT(*) AS records,
      COUNT(DISTINCT c.user_id) AS active_users
    FROM service_drafts sd
    LEFT JOIN cases c ON sd.case_id = c.id
    WHERE sd.created_at >= DATE_SUB(NOW(), INTERVAL 12 WEEK)
    GROUP BY DATE_FORMAT(DATE_SUB(sd.created_at, INTERVAL WEEKDAY(sd.created_at) DAY), '%Y-%m-%d')
    ORDER BY week_start ASC
  `);

  const total = Number(recStats.total_records) || 1;
  const totalCases = Number(caseStats.total_cases) || 1;

  res.json({
    snapshot_at: new Date().toISOString(),
    users: {
      total: totalUsers,
      vault_activated: Number(vaultStats.vault_activated) || 0,
      vault_rate: totalUsers > 0
        ? ((Number(vaultStats.vault_activated) / totalUsers) * 100).toFixed(1) + '%'
        : '0%',
      dau: dauWauMau.dau,
      wau: dauWauMau.wau,
      mau: dauWauMau.mau,
    },
    cases: {
      total: Number(caseStats.total_cases) || 0,
      avg_per_user: perUserAvg.avg_cases_per_user || 0,
    },
    records: {
      total: Number(recStats.total_records) || 0,
      new_this_week: Number(weeklyRec.new_this_week) || 0,
      avg_per_user: perUserAvg.avg_records_per_user || 0,
      avg_per_case: ((Number(recStats.total_records) || 0) / totalCases).toFixed(2),
      synced: Number(recStats.synced) || 0,
      reviewed: Number(recStats.reviewed) || 0,
      injected: Number(recStats.injected) || 0,
      shared: Number(recStats.shared) || 0,
      reviewer_linked: Number(recStats.reviewer_linked) || 0,
      e2ee: Number(recStats.e2ee) || 0,
      injection_rate: ((Number(recStats.injected) / total) * 100).toFixed(1) + '%',
      share_rate: ((Number(recStats.shared) / total) * 100).toFixed(1) + '%',
      avg_share_ratio_per_user: sharePerDb.avg_share_ratio_per_user || 0,
    },
    user_list: userList,
    monthly_records: monthlyRecords,
    monthly_users: monthlyUsers,
    weekly_activity: weeklyActivity,
  });
});

// [Mobile/Web] SSE Stream
app.get('/api/events', verifyFirebaseAuth, (req, res) => {
  const { email } = req.query;
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  res.write(`data: ${JSON.stringify({ event: 'connected', status: 'ok' })}\n\n`);

  const client = { id: Date.now(), res, email };
  sseClients.push(client);
  console.log(`🔌 New SSE client connected: ${email || 'unknown'} (Total: ${sseClients.length})`);

  // Heartbeat: Railway 프록시 idle timeout 방지 (25초마다 keep-alive 전송)
  const heartbeat = setInterval(() => {
    try {
      res.write(': heartbeat\n\n');
    } catch (e) {
      clearInterval(heartbeat);
      sseClients = sseClients.filter(c => c.id !== client.id);
    }
  }, 25000);

  req.on('close', () => {
    clearInterval(heartbeat);
    sseClients = sseClients.filter(c => c.id !== client.id);
    console.log(`🔌 SSE client disconnected (Total: ${sseClients.length})`);
  });
});

// [Mobile] 0. 사용자 정보 조회 및 관리
app.get('/api/users/:id', verifyFirebaseAuth, async (req, res) => {
  const { id } = req.params;
  try {
    let [users] = await queryWithTimeout('SELECT * FROM dash_users WHERE id = ?', [id]);
    if (users.length === 0) {
      // UID 불일치 대응: 이메일로 폴백 조회 (save-to-my-db와 동일 패턴)
      const email = req.firebaseUser?.email;
      if (email) {
        [users] = await queryWithTimeout('SELECT * FROM dash_users WHERE email = ?', [email]);
      }
    }
    if (users.length > 0) {
      res.json(users[0]);
    } else {
      res.status(404).json({ error: 'User not found' });
    }
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

app.post('/api/users/update_profile', verifyFirebaseAuth, async (req, res) => {
  const { id, name, email } = req.body;
  console.log(`\n👤 [PROFILE UPDATE] User: ${id}, New Name: ${name}, Email: ${email}`);
  try {
    const resolvedEmail = email || `user_${id.substring(0, 8)}@gmail.com`;
    const [result] = await queryWithTimeout(
      `INSERT INTO dash_users (id, email, name, organization_id) 
       VALUES (?, ?, ?, 'DEFAULT_ORG') 
       ON DUPLICATE KEY UPDATE name = VALUES(name)`,
      [id, resolvedEmail, name]
    );
    res.json({ message: 'Profile updated' });
  } catch (err) {
    console.error('❌ Profile Update Error:', err);
    res.status(500).json({ error: err.message || err.toString() });
  }
});

// [Mobile] FCM 토큰 저장
app.post('/api/users/fcm_token', verifyFirebaseAuth, async (req, res) => {
  const { id, token, email } = req.body;
  console.log(`\n📱 [FCM TOKEN] User: ${id}, Token: ${token.substring(0, 10)}..., Email: ${email}`);
  try {
    const resolvedEmail = email || `user_${id.substring(0, 8)}@gmail.com`;
    // 같은 기기에서 다른 계정으로 로그인 시 이전 계정의 FCM 토큰을 제거 (토큰 전용성 보장)
    await queryWithTimeout(
      `UPDATE dash_users SET fcm_token = NULL WHERE fcm_token = ? AND id != ?`,
      [token, id]
    );
    await queryWithTimeout(
      `INSERT INTO dash_users (id, email, fcm_token, organization_id, last_login_at, login_count)
       VALUES (?, ?, ?, 'DEFAULT_ORG', NOW(), 1)
       ON DUPLICATE KEY UPDATE fcm_token = VALUES(fcm_token), last_login_at = NOW(), login_count = login_count + 1`,
      [id, resolvedEmail, token]
    );
    res.json({ message: 'FCM token saved' });
  } catch (err) {
    console.error('❌ FCM Token Save Error:', err);
    res.status(500).json({ error: err.message || err.toString() });
  }
});

// [E2EE] RSA 공개키 저장 및 조회
app.post('/api/users/public_key', verifyFirebaseAuth, async (req, res) => {
  const { id, public_key } = req.body;
  console.log(`\n🔑 [PUBLIC KEY] Saving for User: ${id}`);
  try {
    await queryWithTimeout('UPDATE dash_users SET public_key = ? WHERE id = ?', [public_key, id]);
    res.json({ message: 'Public key saved' });
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

app.get('/api/users/:id/public_key', verifyFirebaseAuth, async (req, res) => {
  const { id } = req.params;
  try {
    const [rows] = await queryWithTimeout('SELECT public_key FROM dash_users WHERE id = ?', [id]);
    if (rows.length > 0) {
      res.json({ public_key: rows[0].public_key });
    } else {
      res.status(404).json({ error: 'User not found' });
    }
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// ── 상담원(Counselors) API ──────────────────────────────────────────────────

// GET /api/counselors/:userId — 상담원 목록 조회
app.get('/api/counselors/:userId', verifyFirebaseAuth, async (req, res) => {
  const { userId } = req.params;
  try {
    const resolvedId = await resolveUserId(userId, req.firebaseUser?.email);
    const [rows] = await queryWithTimeout(
      'SELECT id, name, is_self, sort_order FROM counselors WHERE user_id = ? ORDER BY sort_order ASC, created_at ASC',
      [resolvedId]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// POST /api/counselors — 상담원 생성/업데이트
app.post('/api/counselors', verifyFirebaseAuth, async (req, res) => {
  const { id, user_id, name, is_self, sort_order } = req.body;
  try {
    const resolvedId = await ensureUserExists(user_id, req.firebaseUser?.email);
    await queryWithTimeout(
      `INSERT INTO counselors (id, user_id, name, is_self, sort_order)
       VALUES (?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE name = VALUES(name), sort_order = VALUES(sort_order)`,
      [id, resolvedId, name, is_self ? 1 : 0, sort_order || 0]
    );
    res.json({ id, message: 'Counselor saved' });
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// DELETE /api/counselors/:counselorId — 상담원 삭제 (소속 사례도 함께 삭제)
app.delete('/api/counselors/:counselorId', verifyFirebaseAuth, async (req, res) => {
  const { counselorId } = req.params;
  const uid = req.firebaseUser?.uid;
  try {
    const [rows] = await queryWithTimeout('SELECT id FROM counselors WHERE id = ? AND user_id = ?', [counselorId, uid]);
    if (rows.length === 0) return res.status(403).json({ error: 'Forbidden' });
    await queryWithTimeout('DELETE FROM cases WHERE counselor_id = ?', [counselorId]);
    await queryWithTimeout('DELETE FROM counselors WHERE id = ?', [counselorId]);
    res.json({ message: 'Counselor deleted' });
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// PUT /api/counselors/reorder — 상담원 순서 변경
app.put('/api/counselors/reorder', verifyFirebaseAuth, async (req, res) => {
  const { counselors } = req.body; // [{id, sort_order}]
  const uid = req.firebaseUser?.uid;
  try {
    for (const c of counselors) {
      await queryWithTimeout('UPDATE counselors SET sort_order = ? WHERE id = ? AND user_id = ?', [c.sort_order, c.id, uid]);
    }
    res.json({ message: 'Reordered' });
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// [Mobile] 1. 새로운 사례(Case) 생성
app.post('/api/cases', verifyFirebaseAuth, async (req, res) => {
  const { id, user_id, case_name, dong, target_system_code, user_name, counselor_id } = req.body;
  console.log(`\n📦 [NEW CASE] 아동명: ${case_name}, 동: ${dong} (ID: ${id})`);

  try {
    // 1. 해당 사용자 아이디가 dash_users에 없으면 자동으로 생성 (이메일 기반 폴백 포함)
    const resolvedCaseUserId = await ensureUserExists(user_id, req.body.user_email, user_name);

    // 2. 사례 저장
    await queryWithTimeout(
      `INSERT INTO cases (id, user_id, case_name, dong, target_system_code, counselor_id)
       VALUES (?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
       case_name = VALUES(case_name),
       dong = VALUES(dong),
       user_id = VALUES(user_id),
       counselor_id = VALUES(counselor_id)`,
      [id, resolvedCaseUserId, case_name, dong, target_system_code || 'NCADS_v2', counselor_id || null]
    );
    console.log(`✅ Case saved/updated in DB (ID: ${id})`);
    res.json({ id: id, message: 'Case created or updated' });
  } catch (err) {
    console.error('❌ Case creation error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Mobile] 1-1. 사용자의 사례 목록 조회 (재로그인 후 복구용)
app.get('/api/cases/user/:userId', verifyFirebaseAuth, async (req, res) => {
  const { userId } = req.params;
  try {
    const resolvedId = await resolveUserId(userId, req.firebaseUser?.email);
    const [rows] = await queryWithTimeout(
      'SELECT id, case_name, dong, target_system_code, counselor_id FROM cases WHERE user_id = ? ORDER BY created_at DESC',
      [resolvedId]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// [Mobile] 사례 삭제
app.delete('/api/cases/:caseId', verifyFirebaseAuth, async (req, res) => {
  const { caseId } = req.params;
  try {
    const [result] = await queryWithTimeout('DELETE FROM cases WHERE id = ?', [caseId]);
    console.log(`[DELETE CASE] id=${caseId} affectedRows=${result.affectedRows}`);
    res.json({ ok: true, affectedRows: result.affectedRows });
  } catch (err) {
    console.error(`[DELETE CASE ERROR] id=${caseId}`, err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Mobile] 2. 상담 기록(Draft) 서버로 동기화
app.post('/api/records', verifyFirebaseAuth, async (req, res) => {
  const {
    case_id, case_name, dong, user_id, user_email, user_name, target, provision_type, method, service_type, service_category, service_name,
    location, start_time, end_time, service_count, travel_time,
    service_description, agent_opinion, encrypted_blob, encryption_key, share_token: client_share_token,
    is_shared_db
  } = req.body;
  
  // 입력 길이 검증
  if (service_description != null && String(service_description).length > 100000) {
    return res.status(400).json({ error: '서비스 내용이 너무 깁니다.' });
  }
  if (agent_opinion != null && String(agent_opinion).length > 50000) {
    return res.status(400).json({ error: '상담원 소견이 너무 깁니다.' });
  }

  console.log(`\n========================================`);
  console.log(`📝 [NEW RECORD RECEIVED]`);
  console.log(`----------------------------------------`);
  console.log(`🆔 사례ID      : ${case_id}`);
  console.log(`👤 유저ID      : ${user_id || '-'}`);
  console.log(`📧 이메일      : ${user_email || '-'}`);

  try {
    let resolvedUserId = user_id;
    // 1. 해당 사례(Case)가 DB에 있는지 확인
    const [cases] = await queryWithTimeout('SELECT id FROM cases WHERE id = ?', [case_id]);

    // 2. 만약 사례가 없다면 (과거 동기화 누락 등), 임시 사례 생성
    if (cases.length === 0) {
      console.log(`⚠️  Case ID ${case_id} not found. Creating placeholder case...`);
      if (!resolvedUserId) {
        const [users] = await queryWithTimeout('SELECT id FROM dash_users LIMIT 1', []);
        resolvedUserId = users.length > 0 ? users[0].id : null;
      }
      if (resolvedUserId) {
        resolvedUserId = await ensureUserExists(resolvedUserId, user_email, null);
      }
      await queryWithTimeout(
        `INSERT INTO cases (id, user_id, case_name, dong) VALUES (?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE case_name = VALUES(case_name), dong = VALUES(dong), user_id = VALUES(user_id)`,
        [case_id, resolvedUserId, case_name || '미지정 사례', dong || '확인 필요']
      );
    } else {
      // 사례가 이미 있으면, 이름이 '복구된 사례'인 경우 올바른 이름으로 업데이트
      const existingCase = cases[0];
      if (case_name) {
        await queryWithTimeout(
          'UPDATE cases SET case_name = ?, dong = ? WHERE id = ? AND case_name = ?',
          [case_name, dong || existingCase.dong, case_id, '복구된 사례']
        );
      }
    }

    console.log(`🔋 제공구분/방법: ${provision_type} / ${method}`);
    console.log(`📂 유형/서비스  : ${service_type} / ${service_name}`);
    console.log(`📍 장소        : ${location}`);
    console.log(`⏰ 일시        : ${start_time} ~ ${end_time}`);
    console.log(`🔢 횟수/이동    : ${service_count}회 / ${travel_time}분`);
    console.log(`📄 서비스 내용  : ${service_description?.substring(0, 50)}...`);
    console.log(`💡 상담원 소견  : ${agent_opinion?.substring(0, 50)}...`);
    console.log(`🔒 E2EE Blob  : ${encrypted_blob ? 'Received (Encrypted)' : 'None'}`);
    console.log(`----------------------------------------`);

    let share_token = client_share_token;
    let recordId;

    if (share_token) {
      const [existing] = await queryWithTimeout('SELECT id FROM service_drafts WHERE share_token = ?', [share_token]);
      if (existing.length > 0) {
        recordId = existing[0].id;
        await queryWithTimeout(
          `UPDATE service_drafts SET
            status='Synced',
            provision_type=?,
            method=?,
            service_type=?,
            service_category=?,
            service_name=?,
            location=?,
            start_time=?,
            end_time=?,
            service_count=?,
            travel_time=?,
            service_description=?,
            agent_opinion=?,
            encrypted_blob=?,
            target=?,
            is_shared_db=COALESCE(?, is_shared_db)
          WHERE id=?`,
          [provision_type, method, service_type, service_category || '', service_name, location, start_time, end_time, service_count, travel_time, service_description || '', agent_opinion || '', encrypted_blob, target || '', (is_shared_db ? 1 : null), recordId]
        );
        console.log(`🔄 Record updated successfully (DB ID: ${recordId})`);
      }
    }

    if (!recordId) {
      share_token = Math.random().toString(36).substring(2, 15) + Date.now().toString(36);
      const [result] = await queryWithTimeout(
        `INSERT INTO service_drafts
        (case_id, provision_type, method, service_type, service_category, service_name, location, start_time, end_time, service_count, travel_time, service_description, agent_opinion, encrypted_blob, target, share_token, status, is_shared_db)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Synced', ?)`,
        [case_id, provision_type, method, service_type, service_category || '', service_name, location, start_time, end_time, service_count, travel_time, service_description || '', agent_opinion || '', encrypted_blob, target || '', share_token, is_shared_db ? 1 : 0]
      );
      recordId = result.insertId;
      console.log(`✅ Record synced successfully (DB ID: ${recordId})`);
    }

    // 닉네임 자동 동기화: user_name이 제공된 경우 dash_users.name 업데이트
    if (user_name && resolvedUserId) {
      await queryWithTimeout('UPDATE dash_users SET name = ? WHERE id = ?', [user_name, resolvedUserId]);
    }

    // Broadcast update via SSE
    broadcastEvent('new_record', { id: recordId, user_email, user_id: resolvedUserId });

    res.json({ id: recordId, share_token, message: 'Record synced' });
  } catch (err) {
    console.error('❌ Record sync error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Mobile] 2-1. 동기화된 상담 기록 단건 삭제
app.delete('/api/records/token/:token', verifyFirebaseAuth, async (req, res) => {
  const { token } = req.params;
  const { user_email } = req.body || {};
  console.log(`\n🗑️ [DELETE RECORD] Token: ${token} (User: ${user_email||'unknown'})`);
  try {
    const [result] = await queryWithTimeout('DELETE FROM service_drafts WHERE share_token = ?', [token]);
    if (result.affectedRows > 0) {
      console.log(`✅ Deleted record (Token: ${token})`);
      res.json({ message: 'Record deleted' });
      broadcastEvent('record_deleted', { token, user_email });
    } else {
      res.json({ message: 'Record deleted or already non-existent' });
    }
  } catch (err) {
    console.error('❌ Record delete error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

app.delete('/api/records/id/:id', verifyFirebaseAuth, async (req, res) => {
  const { id } = req.params;
  const uid = req.firebaseUser?.uid;
  console.log(`\n🗑️ [DELETE RECORD] ID: ${id}`);
  try {
    const [result] = await queryWithTimeout(
      'DELETE sd FROM service_drafts sd JOIN cases c ON sd.case_id = c.id WHERE sd.id = ? AND c.user_id = ?',
      [id, uid]
    );
    if (result.affectedRows > 0) {
      console.log(`✅ Deleted record (ID: ${id})`);
      res.json({ message: 'Record deleted' });
      // Notify all clients (mobile/extension) to refresh
      broadcastEvent('record_deleted', { id: parseInt(id) });
    } else {
      res.status(404).json({ error: 'Record not found' });
    }
  } catch (err) {
    console.error('❌ Record delete error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Mobile] PIN 리셋 전용 — 해당 사용자의 서버 레코드 전체 삭제
app.delete('/api/records/user/all', verifyFirebaseAuth, async (req, res) => {
  const email = req.firebaseUser?.email;
  if (!email) return res.status(400).json({ error: 'email required' });
  const { confirmation } = req.body;
  if (confirmation !== 'CONFIRM_RESET') {
    return res.status(400).json({ error: 'PIN 초기화 확인이 필요합니다.' });
  }
  console.log(`\n🔑 [PIN RESET] Deleting all records for: ${email}`);
  try {
    const [result] = await queryWithTimeout(
      `DELETE r FROM service_drafts r
       JOIN cases c ON r.case_id = c.id
       JOIN dash_users u ON c.user_id = u.id
       WHERE u.email = ?`,
      [email]
    );
    console.log(`✅ [PIN RESET] Deleted ${result.affectedRows} records for ${email}`);
    broadcastEvent('record_deleted', { user_email: email, reason: 'pin_reset' });
    res.json({ message: 'All records deleted', deleted_count: result.affectedRows });
  } catch (err) {
    console.error('❌ PIN reset delete error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Mobile] 2-2. 활성 상태의 토큰 목록과 서버 간 동기화 (유령 데이터 정리)
app.post('/api/records/sync_active', verifyFirebaseAuth, async (req, res) => {
  const { user_email, active_tokens } = req.body;
  if (!user_email) return res.status(400).json({ error: 'user_email required' });
  
  try {
    // Guard: If active_tokens is empty or missing, skip cleanup to prevent accidental full wipe
    if (!active_tokens || active_tokens.length === 0) {
      console.log(`⚠️  [SYNC_ACTIVE] Empty tokens for ${user_email} — skipping cleanup to prevent data loss`);
      return res.json({ message: 'Sync skipped (no active tokens)', deleted_count: 0 });
    }

    const deleteQuery = `
      DELETE r FROM service_drafts r
      JOIN cases c ON r.case_id = c.id
      JOIN dash_users u ON c.user_id = u.id
      WHERE u.email = ? AND r.share_token NOT IN (?)
    `;
    const deleteParams = [user_email, active_tokens];
    
    const [result] = await queryWithTimeout(deleteQuery, deleteParams);
    if (result.affectedRows > 0) {
      console.log(`🧹 Cleaned up ${result.affectedRows} orphan records for user: ${user_email}`);
      // Notify extension to refresh instantly
      broadcastEvent('record_deleted', { user_email, reason: 'cleanup' });
    }
    
    res.json({ message: 'Sync complete', deleted_count: result.affectedRows });
  } catch (err) {
    console.error('❌ Active sync error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Mobile] 2-3. 사용자 알림 리스트 조회
app.get('/api/notifications/:userId', verifyFirebaseAuth, async (req, res) => {
  const { userId } = req.params;
  try {
    const [rows] = await queryWithTimeout(
      'SELECT id, case_name, record_token, message, is_read, created_at FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 50',
      [userId]
    );
    res.json(rows);
  } catch (err) {
    console.error('❌ Fetch Notifications Error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

app.put('/api/notifications/:id/read', verifyFirebaseAuth, async (req, res) => {
  const { id } = req.params;
  try {
    await queryWithTimeout('UPDATE notifications SET is_read = 1 WHERE id = ?', [id]);
    res.json({ message: 'Notification marked as read' });
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

app.post('/api/records/reviewed/:token', verifyFirebaseAuth, async (req, res) => {
  const { token } = req.params;
  const { service_description, agent_opinion } = req.body;
  const { uid, email } = req.firebaseUser;
  // 세션 체크는 폴백으로만 사용 (서버 재시작 후에도 Firebase 인증으로 통과 가능)
  const session = authAttempts.get(token);
  if (!session?.verified) {
    // Firebase 인증된 Dash 사용자면 허용
    const [userCheck] = await queryWithTimeout(
      'SELECT id FROM dash_users WHERE id = ? OR email = ?', [uid, email]
    );
    if (userCheck.length === 0) return res.status(403).json({ error: '인증이 필요합니다.' });
  }
  try {
    const [infoResult] = await queryWithTimeout(
      `SELECT s.case_id, c.case_name, c.user_id, u.email,
              CASE WHEN r.name IS NOT NULL AND r.name != '' AND r.name != r.email THEN r.name ELSE '동행상담원' END AS reviewer_name
       FROM service_drafts s
       JOIN cases c ON s.case_id = c.id
       JOIN dash_users u ON c.user_id = u.id
       LEFT JOIN dash_users r ON s.reviewer_user_id = r.id
       WHERE s.share_token = ?`, [token]
    );

    if (infoResult.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }

    const { case_name, user_id, email: user_email, reviewer_name } = infoResult[0];

    const { encrypted_blob } = req.body;

    // ✅ UPDATE 전에 현재(이전) 값 읽기 — 히스토리 before 컬럼용
    const [beforeRows] = await queryWithTimeout(
      'SELECT service_description, agent_opinion FROM service_drafts WHERE share_token = ? LIMIT 1',
      [token]
    );
    const descBefore = beforeRows[0]?.service_description || '';
    const opinionBefore = beforeRows[0]?.agent_opinion || '';

    // encrypted_blob이 없으면 NULL로 덮어써서 확장프로그램이 stale blob 대신 plaintext를 사용하게 함
    const updateQuery = `UPDATE service_drafts SET status = 'Reviewed', encrypted_blob = ?, service_description = ?, agent_opinion = ?, updated_at = NOW() WHERE share_token = ?`;
    const queryParams = [encrypted_blob || null, service_description || '', agent_opinion || '', token];

    const [result] = await queryWithTimeout(updateQuery, queryParams);

    if (result.affectedRows > 0) {
      // 📝 Create Notification for the counselor
      const message = `${reviewer_name} 상담원님이 DB를 저장했어요.`;
      // 📝 Mark previous unread notifications for the same record as read (Requirement: Replace with latest for same DB)
      await queryWithTimeout(
        'UPDATE notifications SET is_read = 1 WHERE user_id = ? AND record_token = ? AND is_read = 0',
        [user_id, token]
      );

      await queryWithTimeout(
        'INSERT INTO notifications (user_id, case_name, record_token, message, is_read) VALUES (?, ?, ?, ?, 0)',
        [user_id, case_name, token, message]
      );

      // ✅ 수정 히스토리 기록 (UPDATE 전에 읽은 before 값 사용)
      queryWithTimeout(
        `INSERT INTO record_edit_history
           (share_token, editor_user_id, editor_name, action,
            service_description_before, agent_opinion_before,
            service_description_snapshot, agent_opinion_snapshot, encrypted_blob_snapshot)
         SELECT share_token, reviewer_user_id, ?, 'reviewed',
                ?, ?,
                ?, ?, ?
         FROM service_drafts WHERE share_token = ? LIMIT 1`,
        [reviewer_name,
         descBefore, opinionBefore,
         service_description || '', agent_opinion || '', encrypted_blob || null,
         token]
      ).catch(err => console.error('[history] 기록 실패:', err.message));

      console.log(`✅ Record reviewed & Notified (Token: ${token})`);
      res.json({ message: 'Reviewed' });
      
      // Notify extension and mobile app (SSE) — owner + reviewer 모두에게 전송
      broadcastEvent('new_record', { user_email, reason: 'reviewed', record_token: token });
      if (email && email !== user_email) {
        broadcastEvent('new_record', { user_email: email, reason: 'reviewed', record_token: token });
      }

      // 📧 Send Push Notification (FCM)
      if (fcmInitialized) {
        try {
          // Get user's FCM token
          const [userRows] = await queryWithTimeout('SELECT fcm_token FROM dash_users WHERE id = ?', [user_id]);
          console.log(`📱 FCM lookup for user_id=${user_id}, found=${userRows.length}, has_token=${!!(userRows[0]?.fcm_token)}`);
          if (userRows.length > 0 && userRows[0].fcm_token) {
            const fcmToken = userRows[0].fcm_token;
            const message = {
              notification: {
                title: `${reviewer_name} 상담원님이 DB를 저장했어요.`,
              },
              data: {
                type: 'review_completed',
                target_user_id: String(user_id),
                record_token: token
              },
              android: {
                priority: 'high',
                notification: { channelId: 'high_importance_channel' },
              },
              apns: {
                payload: { aps: { 'content-available': 1 } },
                headers: { 'apns-priority': '10' }
              },
              token: fcmToken
            };

            await admin.messaging().send(message);
            console.log(`🚀 Push Notification Sent to ${user_email}`);
          }
        } catch (pushErr) {
          console.error('❌ Push Notification Error:', pushErr.message);
        }
      }
    } else {
      res.status(404).json({ error: 'Not found' });
    }
  } catch (err) {
    console.error('❌ Review Error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Web] 4. 사례담당자가 공유받은 DB를 자신의 계정에 저장 (save-to-my-db)
app.post('/api/records/save-to-my-db/:token', verifyFirebaseAuth, async (req, res) => {
  const { token } = req.params;
  const { uid, email } = req.firebaseUser;
  const { service_description, agent_opinion, encrypted_blob } = req.body || {};
  console.log(`\n💾 [SAVE-TO-MY-DB] Token: ${token} | Requester: ${email}`);

  try {
    // 1. 요청자가 등록된 Dash 사용자인지 확인 (UID → 이메일 폴백)
    let [userRows] = await queryWithTimeout('SELECT id, name FROM dash_users WHERE id = ?', [uid]);
    if (userRows.length === 0 && email) {
      [userRows] = await queryWithTimeout('SELECT id, name FROM dash_users WHERE email = ?', [email]);
    }
    if (userRows.length === 0) return res.status(403).json({ error: 'not_registered' });
    const requesterUid = userRows[0].id;
    const requesterName = userRows[0].name || email;
    console.log(`[SAVE-TO-MY-DB] step1 ok: requesterUid=${requesterUid}`);

    // 2. 원본 draft + case 정보 조회
    const [draftRows] = await queryWithTimeout(
      `SELECT sd.*, c.case_name, c.dong, c.target_system_code, c.user_id AS owner_user_id, u.name AS owner_name
       FROM service_drafts sd
       JOIN cases c ON sd.case_id = c.id
       JOIN dash_users u ON c.user_id = u.id
       WHERE sd.share_token = ?`,
      [token]
    );
    if (draftRows.length === 0) return res.status(404).json({ error: '존재하지 않는 링크입니다.' });

    const orig = draftRows[0];
    console.log(`[SAVE-TO-MY-DB] step2 ok: case_name=${orig.case_name}, owner=${orig.owner_user_id}`);
    // 자기 자신이 작성한 DB는 저장 불가
    if (orig.owner_user_id === requesterUid) return res.status(400).json({ error: 'own_record' });

    // 3. 요청자 계정에서 동일 case_name 사례 찾기 (없으면 생성)
    // cases.id: 실제 DB 컬럼이 INT(max ~21억)일 수 있으므로 초 단위 Unix timestamp 사용 (10자리)
    // Date.now()는 13자리라 INT overflow 발생 → Math.floor(Date.now()/1000)은 INT/BIGINT 모두 안전
    const caseId = Math.floor(Date.now() / 1000);
    const [existingCase] = await queryWithTimeout(
      'SELECT id FROM cases WHERE user_id = ? AND case_name = ?',
      [requesterUid, orig.case_name]
    );
    let targetCaseId;
    // UUID로 잘못 생성된 잔류 레코드(id가 숫자가 아닌 경우)는 무시하고 새 numeric id로 생성
    const numericCase = existingCase.find(row => !isNaN(Number(row.id)) && String(row.id).trim() !== '');
    if (numericCase) {
      targetCaseId = numericCase.id;
    } else {
      targetCaseId = caseId;
      await queryWithTimeout(
        'INSERT INTO cases (id, user_id, case_name, dong, target_system_code) VALUES (?, ?, ?, ?, ?)',
        [targetCaseId, requesterUid, orig.case_name, orig.dong || '', orig.target_system_code || 'NCADS_v2']
      );
    }
    console.log(`[SAVE-TO-MY-DB] step3 ok: targetCaseId=${targetCaseId}`);

    // 4. 원본 draft에 리뷰어 편집 내용 반영 (내용이 전달된 경우)
    const finalDesc = (service_description !== undefined && service_description !== null) ? service_description : orig.service_description;
    const finalOpinion = (agent_opinion !== undefined && agent_opinion !== null) ? agent_opinion : orig.agent_opinion;
    const finalBlob = (encrypted_blob !== undefined && encrypted_blob !== null) ? encrypted_blob : orig.encrypted_blob;

    if (service_description !== undefined || agent_opinion !== undefined || encrypted_blob !== undefined) {
      let updateOrigQuery = 'UPDATE service_drafts SET service_description = ?, agent_opinion = ?, updated_at = NOW()';
      const updateOrigParams = [finalDesc, finalOpinion];
      if (finalBlob !== orig.encrypted_blob) {
        updateOrigQuery += ', encrypted_blob = ?';
        updateOrigParams.push(finalBlob);
      }
      updateOrigQuery += ' WHERE share_token = ?';
      updateOrigParams.push(token);
      await queryWithTimeout(updateOrigQuery, updateOrigParams);
      console.log(`[SAVE-TO-MY-DB] step4-orig updated: desc_len=${finalDesc?.length}`);
    }

    // 4-1. draft 복사 (중복 방지: 이미 저장된 사본이 있으면 UPDATE, 없으면 INSERT)
    const [existingCopy] = await queryWithTimeout(
      'SELECT id FROM service_drafts WHERE case_id = ? AND is_shared_db = 0 ORDER BY id DESC LIMIT 1',
      [targetCaseId]
    );
    let newToken = null;
    if (existingCopy.length > 0) {
      await queryWithTimeout(
        `UPDATE service_drafts SET
          service_description = ?, agent_opinion = ?, encrypted_blob = ?,
          injected_by_name = ?, status = 'Synced', updated_at = NOW()
         WHERE id = ?`,
        [finalDesc, finalOpinion, finalBlob, orig.owner_name, existingCopy[0].id]
      );
      console.log(`[SAVE-TO-MY-DB] step4 ok (updated existing copy): id=${existingCopy[0].id}`);
    } else {
      newToken = require('crypto').randomBytes(16).toString('hex');
      await queryWithTimeout(
        `INSERT INTO service_drafts
          (case_id, provision_type, method, service_type, service_category, service_name, location,
           start_time, end_time, service_count, travel_time, service_description, agent_opinion,
           encrypted_blob, target, share_token, status, is_shared_db, injected_by_name)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Synced', 0, ?)`,
        [
          targetCaseId, orig.provision_type, orig.method, orig.service_type, orig.service_category,
          orig.service_name, orig.location, orig.start_time, orig.end_time, orig.service_count,
          orig.travel_time, finalDesc, finalOpinion, finalBlob,
          orig.target, newToken, orig.owner_name
        ]
      );
      console.log(`[SAVE-TO-MY-DB] step4 ok (inserted new copy): newToken=${newToken}`);
    }

    // 5. 원본 소유자에게 알림 생성
    const notifyMsg = `${requesterName} 상담원님이 DB를 저장했어요.`;
    await queryWithTimeout(
      'INSERT INTO notifications (user_id, case_name, record_token, message, is_read) VALUES (?, ?, ?, ?, 0)',
      [orig.owner_user_id, orig.case_name, token, notifyMsg]
    );
    console.log(`[SAVE-TO-MY-DB] step5 ok`);

    // 5-1. 저장 완료 → 리뷰어의 share_viewers dismissed_at 설정 (공유받은 DB 목록에서 숨김)
    await queryWithTimeout(
      'UPDATE share_viewers SET dismissed_at = NOW() WHERE share_token = ? AND user_id = ?',
      [token, requesterUid]
    );
    console.log(`[SAVE-TO-MY-DB] step5-1 ok: share_viewers dismissed for requester`);

    // 5-2. 수정 히스토리 기록
    queryWithTimeout(
      `INSERT INTO record_edit_history
         (share_token, editor_user_id, editor_name, action,
          service_description_before, agent_opinion_before,
          service_description_snapshot, agent_opinion_snapshot, encrypted_blob_snapshot)
       VALUES (?, ?, ?, 'synced', ?, ?, ?, ?, ?)`,
      [token, requesterUid, requesterName,
       orig.service_description || '', orig.agent_opinion || '',
       finalDesc || '', finalOpinion || '', finalBlob || null]
    ).catch(err => console.error('[history] save-to-my-db 기록 실패:', err.message));

    // 6. 원본 소유자에게 FCM Push
    if (fcmInitialized) {
      try {
        const [ownerFcm] = await queryWithTimeout('SELECT fcm_token FROM dash_users WHERE id = ?', [orig.owner_user_id]);
        if (ownerFcm.length > 0 && ownerFcm[0].fcm_token) {
          await admin.messaging().send({
            notification: {
              title: notifyMsg,
            },
            data: {
              type: 'db_saved_by_case_manager',
              target_user_id: String(orig.owner_user_id),
              record_token: token,
            },
            android: { priority: 'high', notification: { channelId: 'high_importance_channel' } },
            apns: { payload: { aps: { 'content-available': 1 } }, headers: { 'apns-priority': '10' } },
            token: ownerFcm[0].fcm_token,
          });
          console.log(`🚀 FCM 'db_saved_by_case_manager' sent to owner: ${orig.owner_user_id}`);
        }
      } catch (pushErr) {
        console.error('❌ FCM Push Error (save-to-my-db):', pushErr.message);
      }
    }

    console.log(`✅ DB saved to case manager's account. New token: ${newToken}`);
    res.json({ ok: true, new_token: newToken });
  } catch (err) {
    console.error('❌ save-to-my-db error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Web] 공유 링크 세션 저장소
const authAttempts = new Map(); // token -> { verified, verifiedAt, uid?, count?, lockedUntil? }

// [Web] 2-4. 리뷰어 구글 로그인 (Firebase ID 토큰 검증 후 세션 승인)
app.post('/api/records/reviewer-login/:token', verifyFirebaseAuth, async (req, res) => {
  const { token } = req.params;
  const { uid, email } = req.firebaseUser;

  try {
    const [rows] = await queryWithTimeout(
      'SELECT id FROM service_drafts WHERE share_token = ?', [token]
    );
    if (rows.length === 0) return res.status(404).json({ error: '존재하지 않는 링크입니다.' });

    // 모바일 앱 가입 회원인지 확인 (UID 직접 조회 → 이메일 폴백)
    let [userRows] = await queryWithTimeout(
      `SELECT id, name, email FROM dash_users WHERE id = ?`,
      [uid]
    );
    if (userRows.length === 0 && email) {
      [userRows] = await queryWithTimeout(
        `SELECT id, name, email FROM dash_users WHERE email = ?`,
        [email]
      );
    }
    if (userRows.length === 0) {
      return res.status(403).json({ error: 'not_registered' });
    }

    // 레코드 작성자 UID 조회 (본인 여부 확인용)
    const [ownerRows] = await queryWithTimeout(
      `SELECT c.user_id AS owner_uid
       FROM service_drafts sd
       JOIN cases c ON sd.case_id = c.id
       WHERE sd.share_token = ?`,
      [token]
    );
    const isOwner = ownerRows.length > 0 && ownerRows[0].owner_uid === uid;

    if (!isOwner) {
      const reviewerDbId = userRows[0].id;

      // 공유 인원 제한: 최대 2명 (이미 등록된 사람은 통과)
      const [viewerCount] = await queryWithTimeout(
        `SELECT COUNT(*) AS cnt FROM share_viewers WHERE share_token = ? AND user_id != ?`,
        [token, reviewerDbId]
      );
      if (viewerCount[0].cnt >= 2) {
        return res.status(403).json({ error: 'viewer_limit_reached' });
      }

      // 이름 인증 대기 상태 저장 (share_viewers 등록은 verify-name에서 수행)
      const viewerName = userRows[0].name || userRows[0].email || email || '알 수 없음';
      authAttempts.set(`${token}:${uid}`, { pendingName: true, reviewerDbId, viewerName });
      console.log(`🔒 [REVIEWER LOGIN] uid=${uid} → token=${token} 이름 인증 대기`);
      return res.json({ ok: true, isOwner: false, needsNameVerification: true });
    }

    // 오너: 바로 인증 완료
    authAttempts.set(token, { verified: true, verifiedAt: Date.now(), uid });
    console.log(`✅ [REVIEWER LOGIN] uid=${uid} → token=${token} isOwner=true`);
    return res.json({ ok: true, isOwner: true });
  } catch (err) {
    console.error('Reviewer login error:', err);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Web] 공유자 이름 인증 (Google 로그인 후 2단계)
app.post('/api/records/verify-name/:token', verifyFirebaseAuth, async (req, res) => {
  const { token } = req.params;
  const { uid } = req.firebaseUser;
  const { owner_name: submittedName } = req.body;

  const pending = authAttempts.get(`${token}:${uid}`);
  if (!pending?.pendingName) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const [ownerRows] = await queryWithTimeout(
      `SELECT u.name AS owner_name
       FROM service_drafts sd
       JOIN cases c ON sd.case_id = c.id
       JOIN dash_users u ON c.user_id = u.id
       WHERE sd.share_token = ?`,
      [token]
    );
    if (!ownerRows.length) return res.status(404).json({ error: '존재하지 않는 링크입니다.' });

    const normalize = s => (s || '').trim().replace(/\s+/g, '');
    if (!submittedName || normalize(submittedName) !== normalize(ownerRows[0].owner_name)) {
      console.log(`❌ [VERIFY NAME] uid=${uid} token=${token} 이름 불일치`);
      return res.status(403).json({ error: 'name_mismatch' });
    }

    // 인원 재확인 후 share_viewers 등록
    const { reviewerDbId, viewerName } = pending;
    const [viewerCount] = await queryWithTimeout(
      `SELECT COUNT(*) AS cnt FROM share_viewers WHERE share_token = ? AND user_id != ?`,
      [token, reviewerDbId]
    );
    if (viewerCount[0].cnt >= 2) {
      authAttempts.delete(`${token}:${uid}`);
      return res.status(403).json({ error: 'viewer_limit_reached' });
    }

    await queryWithTimeout(
      `INSERT INTO share_viewers (share_token, user_id, name) VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE name = ?`,
      [token, reviewerDbId, viewerName, viewerName]
    );
    await queryWithTimeout(
      'UPDATE service_drafts SET reviewer_user_id = ? WHERE share_token = ?',
      [reviewerDbId, token]
    );

    authAttempts.delete(`${token}:${uid}`);
    authAttempts.set(token, { verified: true, verifiedAt: Date.now(), uid });
    console.log(`✅ [VERIFY NAME] uid=${uid} → token=${token} 인증 완료`);
    return res.json({ ok: true });
  } catch (err) {
    console.error('verify-name error:', err);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Web] 2-5. 공유 링크 접근 전 상담원 이름 인증 (5회 실패 시 10분 잠금) — 레거시 유지 // token -> { count, lockedUntil }

app.post('/api/records/auth/:token', async (req, res) => {
  const { token } = req.params;
  const { name } = req.body;

  if (!name || !name.trim()) {
    return res.status(400).json({ error: '이름을 입력해주세요.' });
  }

  const attempts = authAttempts.get(token) || { count: 0, lockedUntil: null };
  if (attempts.lockedUntil && Date.now() < attempts.lockedUntil) {
    const remainingMin = Math.ceil((attempts.lockedUntil - Date.now()) / 60000);
    return res.status(429).json({ error: `시도 횟수를 초과했습니다. ${remainingMin}분 후 다시 시도해주세요.`, locked: true });
  }

  try {
    const [rows] = await queryWithTimeout(
      `SELECT u.name as user_name FROM service_drafts s
       JOIN cases c ON s.case_id = c.id
       LEFT JOIN dash_users u ON c.user_id = u.id
       WHERE s.share_token = ?`,
      [token]
    );

    if (rows.length === 0) return res.status(404).json({ error: '존재하지 않는 링크입니다.' });

    const authorName = (rows[0].user_name || '').trim();
    const inputName = name.trim();

    if (inputName === authorName) {
      authAttempts.set(token, { verified: true, verifiedAt: Date.now() });
      return res.json({ verified: true });
    }

    attempts.count = (attempts.count || 0) + 1;
    if (attempts.count >= 5) {
      attempts.lockedUntil = Date.now() + 10 * 60 * 1000;
      attempts.count = 0;
      authAttempts.set(token, attempts);
      return res.status(429).json({ error: '시도 횟수를 초과했습니다. 10분 후 다시 시도해주세요.', locked: true });
    }
    authAttempts.set(token, attempts);
    return res.status(401).json({ error: '이름이 일치하지 않습니다.', remaining: 5 - attempts.count });
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// [Web] 3. 공유 토큰으로 모든 데이터 불러오기 (이름 인증 필수)
app.get('/api/records/share/:token', async (req, res) => {
  const { token } = req.params;
  console.log(`\n🔗 [WEB ACCESS] Token: ${token}`);

  // 이름 인증 여부 확인 (4시간 유효)
  const session = authAttempts.get(token);
  const isVerified = session?.verified === true && (Date.now() - session.verifiedAt) < 4 * 60 * 60 * 1000;
  if (!isVerified) {
    return res.status(401).json({ needs_auth: true });
  }

  try {
    const [rows] = await queryWithTimeout(
      `SELECT r.*, c.case_name, c.dong, c.target_system_code, u.name as user_name
       FROM service_drafts r
       JOIN cases c ON r.case_id = c.id
       LEFT JOIN dash_users u ON c.user_id = u.id
       WHERE r.share_token = ?`,
      [token]
    );

    if (rows.length === 0) {
      console.log('⚠️  Data not found for token');
      return res.status(404).json({ error: 'Data not found' });
    }
    // Phase 3-A: 공유 링크 만료 검증
    if (rows[0].share_expires_at && new Date() > new Date(rows[0].share_expires_at)) {
      console.log(`⛔ [SHARE] Expired link accessed: ${token}`);
      return res.status(410).json({ error: '만료된 공유 링크입니다.' });
    }

    const [viewers] = await queryWithTimeout(
      `SELECT name FROM share_viewers WHERE share_token = ? ORDER BY first_accessed_at ASC`,
      [token]
    );

    const shareViewerNames = viewers.map(v => v.name);
    console.log(`✅ Data fetched for ${rows[0].case_name} | share_viewers=${JSON.stringify(shareViewerNames)}`);
    res.json({ ...rows[0], share_viewers: shareViewerNames });
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// [Web] 3.1. 공유 토큰으로 중간 저장 (Auto-save)
app.put('/api/records/share/:token', async (req, res) => {
  const { token } = req.params;
  const { service_description, agent_opinion, encrypted_blob } = req.body;
  console.log(`\n💾 [WEB AUTO-SAVE] Token: ${token}`);

  // 세션 인증 확인 (reviewer-login 또는 name-auth 완료 필요)
  const session = authAttempts.get(token);
  const isVerified = session?.verified === true && (Date.now() - session.verifiedAt) < 4 * 60 * 60 * 1000;
  if (!isVerified) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // encrypted_blob이 없으면 NULL로 덮어써서 확장프로그램이 stale blob 대신 plaintext를 사용하게 함
    const query = 'UPDATE service_drafts SET service_description = ?, agent_opinion = ?, encrypted_blob = ?, updated_at = NOW() WHERE share_token = ?';
    const params = [service_description || '', agent_opinion || '', encrypted_blob || null, token];

    const [result] = await queryWithTimeout(query, params);
    if (result.affectedRows > 0) {
      // 수정 히스토리 기록 (저장 전 상태 함께 저장)
      const session = authAttempts.get(token);
      if (session?.uid) {
        queryWithTimeout(
          `INSERT INTO record_edit_history
             (share_token, editor_user_id, editor_name, action,
              service_description_before, agent_opinion_before,
              service_description_snapshot, agent_opinion_snapshot, encrypted_blob_snapshot)
           SELECT ?, ?, COALESCE(NULLIF(u.name,''), u.email), 'saved',
                  sd.service_description, sd.agent_opinion,
                  ?, ?, ?
           FROM dash_users u, service_drafts sd
           WHERE u.id = ? AND sd.share_token = ?`,
          [token, session.uid, service_description || '', agent_opinion || '', encrypted_blob || null, session.uid, token]
        ).catch(err => console.error('[history] 저장 기록 실패:', err.message));
      }
      // ⚠️ 옵션 2: 리뷰어의 중간 저장은 로컬 임시 저장 개념.
      // 원 생성자에게 SSE 알림을 보내지 않음 — 버튼 클릭(/reviewed) 시에만 반영됨.
      res.json({ message: 'Saved' });
    } else {
      res.status(404).json({ error: 'Not found' });
    }
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// [Web] 3.1-B. 공유 참여자 목록 조회 (세션 인증 우선, Firebase 폴백)
app.get('/api/records/share/:token/participants', async (req, res) => {
  const { token } = req.params;

  // 세션 인증 확인 (기존 방식)
  const session = authAttempts.get(token);
  const isVerified = session?.verified === true && (Date.now() - session.verifiedAt) < 4 * 60 * 60 * 1000;

  if (!isVerified) {
    // Firebase 인증 폴백
    const authHeader = req.headers.authorization || '';
    const bearerToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
    if (!bearerToken) return res.status(401).json({ error: 'Unauthorized' });
    try {
      const decoded = await admin.auth().verifyIdToken(bearerToken);
      const { uid, email } = decoded;
      const [access] = await queryWithTimeout(
        `SELECT 1 FROM service_drafts sd JOIN cases c ON sd.case_id = c.id
         WHERE sd.share_token = ?
           AND (c.user_id = ? OR c.user_id IN (SELECT id FROM dash_users WHERE email = ?)
                OR EXISTS (SELECT 1 FROM share_viewers sv WHERE sv.share_token = sd.share_token AND sv.user_id IN (SELECT id FROM dash_users WHERE email = ?)))
         LIMIT 1`,
        [token, uid, email, email]
      );
      if (!access.length) return res.status(403).json({ error: 'Forbidden' });
    } catch (e) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
  }

  try {
    const [rows] = await queryWithTimeout(
      `SELECT u.name AS owner_name
       FROM service_drafts sd
       JOIN cases c ON sd.case_id = c.id
       LEFT JOIN dash_users u ON c.user_id = u.id
       WHERE sd.share_token = ? LIMIT 1`,
      [token]
    );
    const [viewers] = await queryWithTimeout(
      `SELECT name FROM share_viewers WHERE share_token = ? ORDER BY first_accessed_at ASC`,
      [token]
    );
    console.log(`📋 [PARTICIPANTS] token=${token} viewers=${JSON.stringify(viewers.map(v=>v.name))}`);
    res.json({ owner_name: rows[0]?.owner_name || '', viewers: viewers.map(v => v.name) });
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// [Web/Mobile] 3.2. 수정 히스토리 조회
app.get('/api/records/history/:token', async (req, res) => {
  const { token } = req.params;
  const session = authAttempts.get(token);
  const isVerified = session?.verified === true && (Date.now() - session.verifiedAt) < 4 * 60 * 60 * 1000;

  if (!isVerified) {
    // 세션 만료 시 Firebase 토큰으로 폴백 — 토큰 소유자가 owner 또는 share_viewer인지 확인
    const authHeader = req.headers.authorization || '';
    const bearerToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
    if (!bearerToken) return res.status(401).json({ error: 'Unauthorized' });
    try {
      const decoded = await admin.auth().verifyIdToken(bearerToken);
      const { uid, email } = decoded;
      const [access] = await queryWithTimeout(
        `SELECT 1 FROM service_drafts sd
         JOIN cases c ON sd.case_id = c.id
         WHERE sd.share_token = ?
           AND (c.user_id = ? OR c.user_id IN (SELECT id FROM dash_users WHERE email = ?)
                OR EXISTS (SELECT 1 FROM share_viewers sv WHERE sv.share_token = sd.share_token AND sv.user_id IN (SELECT id FROM dash_users WHERE email = ?)))
         LIMIT 1`,
        [token, uid, email, email]
      );
      if (!access.length) return res.status(403).json({ error: 'Forbidden' });
    } catch (e) {
      return res.status(401).json({ error: 'Invalid token' });
    }
  }

  try {
    const [rows] = await queryWithTimeout(
      `SELECT id, editor_name, action,
              service_description_before, agent_opinion_before,
              service_description_snapshot, agent_opinion_snapshot,
              encrypted_blob_snapshot, created_at
       FROM record_edit_history
       WHERE share_token = ?
       ORDER BY created_at DESC`,
      [token]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// [Web] 4. 검토 완료 및 데이터 수정 사항 반영
app.put('/api/records/:id/review', async (req, res) => {
  const { id } = req.params;
  const updateData = req.body;
  console.log(`\n✨ [REVIEW COMPLETED] Record ID: ${id}`);
  
  const ALLOWED_UPDATE_FIELDS = [
    'service_description', 'agent_opinion', 'provision_type', 'method',
    'service_type', 'service_category', 'service_name', 'location',
    'start_time', 'end_time', 'service_count', 'travel_time', 'target',
    'encrypted_blob', 'injected_by_name',
  ];
  const isInjected = updateData.status === 'Injected';
  try {
    const safeKeys = Object.keys(updateData).filter(k => ALLOWED_UPDATE_FIELDS.includes(k));
    const extraClause = safeKeys.map(k => `${k} = ?`).join(', ');
    const values = safeKeys.map(k => updateData[k]);
    const newStatus = isInjected ? 'Injected' : 'Reviewed';
    const setClause = extraClause
      ? `${extraClause}, status = ?, reviewed_at = NOW(), updated_at = NOW()`
      : `status = ?, reviewed_at = NOW(), updated_at = NOW()`;

    await queryWithTimeout(
      `UPDATE service_drafts SET ${setClause} WHERE id = ?`,
      [...values, newStatus, id]
    );

    // Get user email to notify
    const [info] = await queryWithTimeout(
      `SELECT u.email FROM service_drafts s JOIN cases c ON s.case_id = c.id JOIN dash_users u ON c.user_id = u.id WHERE s.id = ?`,
      [id]
    );

    if (info.length > 0) {
      broadcastEvent(isInjected ? 'injected' : 'reviewed', { user_email: info[0].email, record_id: id });
    }

    console.log(`✅ Record status updated to '${newStatus}' & Notification sent`);
    res.json({ message: 'Review completed and data updated' });
  } catch (err) {
    console.error('❌ Review update error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Extension] 5. 주입 대기 중인 목록 가져오기 (userId 또는 email로 필터링)
app.get('/api/records/ready', verifyFirebaseAuth, async (req, res) => {
  const { userId, email } = req.query;
  console.log(`\n🚀 [EXTENSION FETCH] Fetching ready records (userId: ${userId || '-'}, email: ${email || '-'})...`);
  try {
    let query;
    const params = [];

    if (email) {
      // 이메일 기반: 내 DB + 공유받은 DB (share_viewers 기준 — 다중 공유 대응)
      query = `
        SELECT r.*, c.case_name, c.dong, u.name AS author_name, 'owned' AS record_type
        FROM service_drafts r
        JOIN cases c ON r.case_id = c.id
        LEFT JOIN dash_users u ON c.user_id = u.id
        WHERE r.status IN ('Synced', 'Reviewed')
          AND c.user_id IN (SELECT id FROM dash_users WHERE email = ?)
        UNION
        SELECT r.*, c.case_name, c.dong, u.name AS author_name, 'shared' AS record_type
        FROM service_drafts r
        JOIN cases c ON r.case_id = c.id
        LEFT JOIN dash_users u ON c.user_id = u.id
        WHERE r.status IN ('Synced', 'Reviewed')
          AND EXISTS (
            SELECT 1 FROM share_viewers sv
            WHERE sv.share_token = r.share_token
              AND sv.user_id IN (SELECT id FROM dash_users WHERE email = ?)
              AND sv.dismissed_at IS NULL
          )
          AND c.user_id NOT IN (SELECT id FROM dash_users WHERE email = ?)
        ORDER BY start_time IS NULL ASC, start_time ASC
      `;
      params.push(email, email, email);
    } else if (userId) {
      query = `
        SELECT r.*, c.case_name, c.dong, u.name AS author_name, 'owned' AS record_type
        FROM service_drafts r
        JOIN cases c ON r.case_id = c.id
        LEFT JOIN dash_users u ON c.user_id = u.id
        WHERE r.status IN ('Synced', 'Reviewed')
          AND c.user_id = ?
        UNION
        SELECT r.*, c.case_name, c.dong, u.name AS author_name, 'shared' AS record_type
        FROM service_drafts r
        JOIN cases c ON r.case_id = c.id
        LEFT JOIN dash_users u ON c.user_id = u.id
        WHERE r.status IN ('Synced', 'Reviewed')
          AND r.reviewer_user_id = ?
          AND c.user_id != ?
        ORDER BY start_time IS NULL ASC, start_time ASC
      `;
      params.push(userId, userId, userId);
    } else {
      query = `
        SELECT r.*, c.case_name, c.dong, NULL AS author_name, 'owned' AS record_type
        FROM service_drafts r
        JOIN cases c ON r.case_id = c.id
        WHERE r.status IN ('Synced', 'Reviewed')
        ORDER BY r.start_time IS NULL ASC, r.start_time ASC
      `;
    }

    const [rows] = await queryWithTimeout(query, params);
    console.log(`✅ Sent ${rows.length} records to extension`);
    res.json(rows);
  } catch (err) {
    console.error('❌ Extension fetch error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Mobile] 4-B. 공유 링크 만료 설정
app.patch('/api/records/:id/share-expiry', verifyFirebaseAuth, async (req, res) => {
  const { id } = req.params;
  const { expires_days } = req.body; // null = 무제한, 숫자 = 일수
  const uid = req.firebaseUser?.uid;
  try {
    let expiresAt = null;
    if (expires_days != null && expires_days > 0) {
      expiresAt = new Date(Date.now() + expires_days * 24 * 60 * 60 * 1000);
    }
    const [result] = await queryWithTimeout(
      `UPDATE service_drafts SET share_expires_at = ? WHERE id = ? AND user_id = (SELECT id FROM dash_users WHERE id = ? LIMIT 1)`,
      [expiresAt, id, uid]
    );
    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Not found or not authorized' });
    }
    res.json({ message: 'Updated', expires_at: expiresAt });
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// [Mobile] 5-0. 공유받은 DB 목록에서 숨기기 (동행자 전용)
// - service_drafts 원본은 절대 건드리지 않음 → 사례 담당자 데이터 100% 보존
// - share_viewers.dismissed_at 만 채워서 동행자 목록에서만 제거
app.delete('/api/records/shared/:id', verifyFirebaseAuth, async (req, res) => {
  const { id } = req.params;
  const uid = req.firebaseUser?.uid;
  try {
    // 1. 해당 draft의 share_token 조회 (권한 확인 겸)
    const [draftRows] = await queryWithTimeout(
      `SELECT sd.share_token FROM service_drafts sd
       JOIN cases c ON sd.case_id = c.id
       WHERE sd.id = ?
         AND EXISTS (
           SELECT 1 FROM share_viewers sv
           WHERE sv.share_token = sd.share_token AND sv.user_id = ?
         )
       LIMIT 1`,
      [id, uid]
    );
    if (draftRows.length === 0) {
      return res.status(404).json({ error: 'Not found or not authorized' });
    }
    const shareToken = draftRows[0].share_token;

    // 2. 동행자의 share_viewers 행에만 dismissed_at 기록 (원본 보존)
    await queryWithTimeout(
      `UPDATE share_viewers SET dismissed_at = NOW() WHERE share_token = ? AND user_id = ?`,
      [shareToken, uid]
    );

    // 3. reviewer_user_id도 해제 (하위 호환 — 다른 동행자 재공유 가능하도록)
    await queryWithTimeout(
      `UPDATE service_drafts SET reviewer_user_id = NULL WHERE id = ? AND reviewer_user_id = ?`,
      [id, uid]
    );

    res.json({ message: 'Removed from shared list' });
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// [Extension+Mobile] 5-1. 기입 완료(Injected) 기록 조회 (이전 기록 탭)
// 본인 소유 기록 + 리뷰어로서 기입한 공유 기록 모두 포함
app.get('/api/records/history', verifyFirebaseAuth, async (req, res) => {
  const { email } = req.query;
  try {
    let query, params;
    if (email) {
      // 소유 기록: c.user_id가 해당 이메일의 사용자
      // 공유 기록: reviewer_user_id가 해당 이메일의 사용자 (리뷰어로서 기입 완료한 기록)
      query = `
        SELECT r.*, c.case_name, c.dong
        FROM service_drafts r
        JOIN cases c ON r.case_id = c.id
        WHERE r.status = 'Injected'
          AND (
            c.user_id IN (SELECT id FROM dash_users WHERE email = ?)
            OR r.reviewer_user_id IN (SELECT id FROM dash_users WHERE email = ?)
          )
        ORDER BY r.updated_at DESC
      `;
      params = [email, email];
    } else {
      query = `
        SELECT r.*, c.case_name, c.dong
        FROM service_drafts r
        JOIN cases c ON r.case_id = c.id
        WHERE r.status = 'Injected'
        ORDER BY r.updated_at DESC
      `;
      params = [];
    }
    const [rows] = await queryWithTimeout(query, params);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// [Mobile] 6. 특정 사용자의 모든 상담 기록 가져오기 (앱 동기화용)
// 동일 이메일로 여러 Firebase UID가 존재할 수 있으므로 항상 이메일 기반으로 조회
app.get('/api/records/user/:userId', verifyFirebaseAuth, async (req, res) => {
  const { userId } = req.params;
  console.log(`\n📱 [MOBILE SYNC] Fetching records for user: ${userId}`);
  try {
    // userId로 이메일 확인, 없으면 Firebase 토큰의 이메일 폴백
    const [userRows] = await queryWithTimeout('SELECT email FROM dash_users WHERE id = ?', [userId]);
    const email = userRows.length > 0 ? userRows[0].email : req.firebaseUser?.email;

    let rows;
    if (email) {
      // 이메일 기반으로 조회 — 동일 이메일의 모든 UID 포함 (UID 불일치 대응)
      // 공유받은 DB: reviewer_user_id 단일값 대신 share_viewers 테이블로 확인 (다중 공유 대응)
      [rows] = await queryWithTimeout(
        `SELECT r.*, c.case_name, c.dong, u.name AS author_name, 'owned' AS record_type
         FROM service_drafts r
         JOIN cases c ON r.case_id = c.id
         LEFT JOIN dash_users u ON c.user_id = u.id
         WHERE c.user_id IN (SELECT id FROM dash_users WHERE email = ?)
         UNION
         SELECT r.*, c.case_name, c.dong, u.name AS author_name, 'shared' AS record_type
         FROM service_drafts r
         JOIN cases c ON r.case_id = c.id
         LEFT JOIN dash_users u ON c.user_id = u.id
         WHERE EXISTS (
           SELECT 1 FROM share_viewers sv
           WHERE sv.share_token = r.share_token
             AND sv.user_id IN (SELECT id FROM dash_users WHERE email = ?)
             AND sv.dismissed_at IS NULL
         )
           AND c.user_id NOT IN (SELECT id FROM dash_users WHERE email = ?)
           AND r.status != 'Injected'
         ORDER BY created_at DESC`,
        [email, email, email]
      );
      console.log(`✅ Found ${rows.length} records for userId: ${userId} (email: ${email})`);
    } else {
      rows = [];
      console.log(`⚠️  No email available for userId: ${userId}, returning empty`);
    }
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

// [Security] 7. Key Vault API (Zero-Knowledge PIN Sync)
app.get('/api/users/vault/:userId', verifyFirebaseAuth, async (req, res) => {
  const { userId } = req.params;

  // Phase 3-B: Rate limiting — 10분 window에 최대 10회
  const now = Date.now();
  const attempts = vaultAttempts.get(userId) || { count: 0, windowStart: now };
  if (now - attempts.windowStart > VAULT_WINDOW_MS) {
    attempts.count = 0;
    attempts.windowStart = now;
  }
  attempts.count++;
  vaultAttempts.set(userId, attempts);
  if (attempts.count > VAULT_MAX_REQUESTS) {
    console.warn(`⚠️ [VAULT] Rate limit exceeded for userId: ${userId}`);
    return res.status(429).json({ error: 'Too many requests. Try again later.' });
  }

  try {
    // 1차: uid로 직접 조회
    let [rows] = await queryWithTimeout(
      'SELECT encrypted_vault, salt FROM user_key_vault WHERE user_id = ?',
      [userId]
    );
    // 2차: uid로 없으면 Firebase 검증 이메일로 user_id 찾아 재조회 (UID 불일치 대응)
    if (rows.length === 0 && req.firebaseUser?.email) {
      const [byEmail] = await queryWithTimeout(
        'SELECT id FROM dash_users WHERE email = ?',
        [req.firebaseUser.email]
      );
      if (byEmail.length > 0 && byEmail[0].id !== userId) {
        [rows] = await queryWithTimeout(
          'SELECT encrypted_vault, salt FROM user_key_vault WHERE user_id = ?',
          [byEmail[0].id]
        );
      }
    }
    if (rows.length === 0) {
      console.log(`[VAULT GET] userId=${userId} → not found`);
      return res.status(404).json({ message: 'Vault not found' });
    }
    const hasVault = !!rows[0].encrypted_vault;
    const hasSalt = !!rows[0].salt;
    console.log(`[VAULT GET] userId=${userId} → encrypted_vault=${hasVault}, salt=${hasSalt}`);
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: safeError(err) });
  }
});

app.post('/api/users/vault', verifyFirebaseAuth, async (req, res) => {
  const { user_id, encrypted_vault, salt } = req.body;
  if (!user_id || !encrypted_vault) {
    return res.status(400).json({ error: 'Missing required fields' });
  }
  try {
    // Firebase UID가 dash_users에 없으면 이메일로 실제 user_id를 찾아 사용
    const resolvedId = await resolveUserId(user_id, req.firebaseUser?.email);
    await queryWithTimeout(
      `INSERT INTO user_key_vault (user_id, encrypted_vault, salt) 
       VALUES (?, ?, ?) 
       ON DUPLICATE KEY UPDATE encrypted_vault = ?, salt = ?`,
      [resolvedId, encrypted_vault, salt, encrypted_vault, salt]
    );
    res.json({ success: true, message: 'Vault updated successfully' });
  } catch (err) {
    console.error('❌ Vault update error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

// [Security] 8. User Deletion (PIPL Compliance)
app.delete('/api/users/:id', verifyFirebaseAuth, async (req, res) => {
  const { id } = req.params;
  const { email } = req.query;
  console.log(`\n🗑️ [USER DELETION] User ID: ${id}, Email: ${email}`);
  try {
    // 삭제 대상 user_id 목록 수집 (Firebase UID & Chrome OAuth ID 모두 포함)
    const [targetRows] = await queryWithTimeout(
      'SELECT id FROM dash_users WHERE id = ?' + (email ? ' OR email = ?' : ''),
      email ? [id, email] : [id]
    );

    if (targetRows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    const targetIds = targetRows.map(r => r.id);

    // cases FK가 ON DELETE SET NULL이라 service_drafts·cases를 명시적으로 삭제
    for (const uid of targetIds) {
      // 공유받은 DB에서 이 사용자의 reviewer 참조 제거 (탈퇴 후 재가입 시 재노출 방지)
      await queryWithTimeout(
        'UPDATE service_drafts SET reviewer_user_id = NULL WHERE reviewer_user_id = ?',
        [uid]
      );
      await queryWithTimeout(
        'DELETE sd FROM service_drafts sd JOIN cases c ON sd.case_id = c.id WHERE c.user_id = ?',
        [uid]
      );
      await queryWithTimeout('DELETE FROM cases WHERE user_id = ?', [uid]);
      await queryWithTimeout('DELETE FROM counselors WHERE user_id = ?', [uid]);
    }

    // dash_users 삭제 (notifications, vault은 ON DELETE CASCADE로 자동 삭제)
    const [result] = await queryWithTimeout(
      'DELETE FROM dash_users WHERE id = ?' + (email ? ' OR email = ?' : ''),
      email ? [id, email] : [id]
    );

    console.log(`✅ [USER DELETION] Deleted user + ${targetIds.length} uid(s), affected: ${result.affectedRows}`);
    res.json({ success: true, message: 'User data deleted successfully' });
  } catch (err) {
    console.error('❌ User deletion error:', err.message);
    res.status(500).json({ error: safeError(err) });
  }
});

const server = app.listen(port, '0.0.0.0', () => {
  console.log(`\n========================================`);
  console.log(`🚀 Dash Server running on 0.0.0.0:${port}`);
  console.log(`========================================\n`);
});

// Graceful shutdown — Railway/Docker가 SIGTERM을 보낼 때 정상 종료
process.on('SIGTERM', () => {
  console.log('⚡ SIGTERM received. Shutting down gracefully...');
  server.close(() => {
    console.log('✅ Server closed.');
    process.exit(0);
  });
});

// ============================================================
// 개인정보 자동 파기 스케줄러 (개인정보보호법 제21조)
// 매일 새벽 2시 실행
// - 상담 기록(service_drafts): 아동복지법 제28조 → 5년 보존 후 파기
// - 알림(notifications): 1년 보존 후 파기
// ============================================================
async function ensureSchemaUpdates() {
  try {
    const [columns] = await queryWithTimeout(`
      SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'service_drafts'
        AND COLUMN_NAME = 'service_category'
    `);
    if (columns.length === 0) {
      await queryWithTimeout(`
        ALTER TABLE service_drafts
        ADD COLUMN service_category VARCHAR(100) DEFAULT '' COMMENT '서비스세부목표(대분류)'
      `);
      console.log('✅ service_drafts.service_category 컬럼 추가 완료');
    } else {
      console.log('✅ service_drafts.service_category 컬럼 이미 존재');
    }
  } catch (err) {
    console.warn('⚠️  service_category 컬럼 추가 실패:', err.message);
  }
}

async function ensureRetentionLogTable() {
  try {
    await queryWithTimeout(`
      CREATE TABLE IF NOT EXISTS retention_policy_log (
        id          INT AUTO_INCREMENT PRIMARY KEY,
        target_table VARCHAR(64)  NOT NULL COMMENT '파기 대상 테이블',
        deleted_count INT         NOT NULL DEFAULT 0 COMMENT '파기된 레코드 수',
        cutoff_date  DATE         NOT NULL COMMENT '파기 기준일(이 날짜 이전 생성분 파기)',
        law_basis    VARCHAR(255) NOT NULL COMMENT '법적 근거',
        executed_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '실행 일시'
      ) COMMENT='개인정보 자동 파기 이력 (개인정보보호법 제21조)';
    `);
  } catch (err) {
    console.warn('⚠️  retention_policy_log 테이블 생성 실패:', err.message);
  }
}

async function runRetentionPurge() {
  console.log('\n========================================');
  console.log('🗑️  [RETENTION PURGE] 개인정보 자동 파기 시작');
  console.log(`⏰  실행 시각: ${new Date().toLocaleString('ko-KR')}`);
  console.log('========================================');

  try {
    await ensureRetentionLogTable();

    // 1. 상담 기록 파기: 5년 경과분 (아동복지법 제28조)
    const fiveYearsAgo = new Date();
    fiveYearsAgo.setFullYear(fiveYearsAgo.getFullYear() - 5);
    const fiveYearsAgoStr = fiveYearsAgo.toISOString().split('T')[0];

    const [draftsResult] = await queryWithTimeout(
      `DELETE FROM service_drafts WHERE created_at < ?`,
      [fiveYearsAgoStr],
      30000
    );
    await queryWithTimeout(
      `INSERT INTO retention_policy_log (target_table, deleted_count, cutoff_date, law_basis)
       VALUES (?, ?, ?, ?)`,
      ['service_drafts', draftsResult.affectedRows, fiveYearsAgoStr, '아동복지법 제28조 (5년 보존)']
    );
    console.log(`✅ service_drafts: ${draftsResult.affectedRows}건 파기 (기준일: ${fiveYearsAgoStr})`);

    // 2. 알림 파기: 1년 경과분
    const oneYearAgo = new Date();
    oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);
    const oneYearAgoStr = oneYearAgo.toISOString().split('T')[0];

    const [notifResult] = await queryWithTimeout(
      `DELETE FROM notifications WHERE created_at < ?`,
      [oneYearAgoStr],
      30000
    );
    await queryWithTimeout(
      `INSERT INTO retention_policy_log (target_table, deleted_count, cutoff_date, law_basis)
       VALUES (?, ?, ?, ?)`,
      ['notifications', notifResult.affectedRows, oneYearAgoStr, '내부 정책 (1년 보존)']
    );
    console.log(`✅ notifications: ${notifResult.affectedRows}건 파기 (기준일: ${oneYearAgoStr})`);

    console.log('🎉 [RETENTION PURGE] 완료\n');
  } catch (err) {
    console.error('❌ [RETENTION PURGE] 오류:', err.message);
  }
}

// 매일 새벽 2:00 실행 (서버 로컬 타임 기준)
cron.schedule('0 2 * * *', runRetentionPurge, {
  timezone: 'Asia/Seoul',
});
console.log('⏰ 개인정보 자동 파기 스케줄러 등록 완료 (매일 02:00 KST)');

// 서버 시작 시 DB 스키마 업데이트
ensureSchemaUpdates();
