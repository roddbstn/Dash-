require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const mysql = require('mysql2/promise');
const cron = require('node-cron');

const app = express();
const port = process.env.PORT || 3000;

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
// CORS: 모바일 앱(Origin 없음), Chrome 확장프로그램, 리뷰어 사이트(동일 서버) 허용
const ALLOWED_ORIGINS = [
  'https://dash.qpon',
  'http://localhost:3000',
  process.env.ALLOWED_ORIGIN,
].filter(Boolean);

app.use(cors({
  origin: (origin, callback) => {
    if (!origin) return callback(null, true);                         // 모바일 앱 / Origin 없음
    if (origin.startsWith('chrome-extension://')) return callback(null, true); // Chrome 확장
    if (ALLOWED_ORIGINS.includes(origin)) return callback(null, true); // 리뷰어 사이트 (same-server)
    return callback(new Error('CORS: 허용되지 않은 출처입니다.'));
  },
}));
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '10mb' }));
app.use(express.static(path.join(__dirname, 'reviewer_site'))); // Serve static files

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
async function resolveUserId(uid, emailFallback) {
  const [rows] = await queryWithTimeout('SELECT id FROM dash_users WHERE id = ?', [uid]);
  if (rows.length > 0) return uid;
  if (!emailFallback) return uid;
  const [byEmail] = await queryWithTimeout('SELECT id FROM dash_users WHERE email = ?', [emailFallback]);
  if (byEmail.length > 0) {
    console.log(`🔄 Resolved user id via email: ${byEmail[0].id} (was: ${uid})`);
    return byEmail[0].id;
  }
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
pool.query("ALTER TABLE service_drafts ADD COLUMN IF NOT EXISTS reviewer_user_id VARCHAR(36) DEFAULT NULL")
  .catch(() => {}); // 이미 있으면 무시

// --- API Endpoints ---

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'reviewer_site', 'index.html'));
});

// [공통] 서버 상태 확인
app.get('/health', (req, res) => {
  console.log('--- Health Check ---');
  res.json({ status: 'ok', time: new Date() });
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
    const [users] = await queryWithTimeout('SELECT * FROM dash_users WHERE id = ?', [id]);
    if (users.length > 0) {
      res.json(users[0]);
    } else {
      res.status(404).json({ error: 'User not found' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
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
    await queryWithTimeout(
      `INSERT INTO dash_users (id, email, fcm_token, organization_id) 
       VALUES (?, ?, ?, 'DEFAULT_ORG') 
       ON DUPLICATE KEY UPDATE fcm_token = VALUES(fcm_token)`,
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
    res.status(500).json({ error: err.message });
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
    res.status(500).json({ error: err.message });
  }
});

// [Mobile] 1. 새로운 사례(Case) 생성
app.post('/api/cases', verifyFirebaseAuth, async (req, res) => {
  const { id, user_id, case_name, dong, target_system_code, user_name } = req.body;
  console.log(`\n📦 [NEW CASE] 아동명: ${case_name}, 동: ${dong} (ID: ${id})`);
  
  try {
    // 1. 해당 사용자 아이디가 dash_users에 없으면 자동으로 생성 (이메일 기반 폴백 포함)
    const resolvedCaseUserId = await ensureUserExists(user_id, req.body.user_email, user_name);

    // 2. 사례 저장
    await queryWithTimeout(
      `INSERT INTO cases (id, user_id, case_name, dong, target_system_code) 
       VALUES (?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE 
       case_name = VALUES(case_name), 
       dong = VALUES(dong),
       user_id = VALUES(user_id)`,
      [id, resolvedCaseUserId, case_name, dong, target_system_code || 'NCADS_v2']
    );
    console.log(`✅ Case saved/updated in DB (ID: ${id})`);
    res.json({ id: id, message: 'Case created or updated' });
  } catch (err) {
    console.error('❌ Case creation error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// [Mobile] 2. 상담 기록(Draft) 서버로 동기화
app.post('/api/records', verifyFirebaseAuth, async (req, res) => {
  const {
    case_id, case_name, dong, user_id, user_email, user_name, target, provision_type, method, service_type, service_category, service_name,
    location, start_time, end_time, service_count, travel_time,
    service_description, agent_opinion, encrypted_blob, share_token: client_share_token
  } = req.body;
  
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
            target=?
          WHERE id=?`,
          [provision_type, method, service_type, service_category || '', service_name, location, start_time, end_time, service_count, travel_time, service_description || '', agent_opinion || '', encrypted_blob, target || '', recordId]
        );
        console.log(`🔄 Record updated successfully (DB ID: ${recordId})`);
      }
    }

    if (!recordId) {
      share_token = Math.random().toString(36).substring(2, 15) + Date.now().toString(36);
      const [result] = await queryWithTimeout(
        `INSERT INTO service_drafts
        (case_id, provision_type, method, service_type, service_category, service_name, location, start_time, end_time, service_count, travel_time, service_description, agent_opinion, encrypted_blob, target, share_token, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Synced')`,
        [case_id, provision_type, method, service_type, service_category || '', service_name, location, start_time, end_time, service_count, travel_time, service_description || '', agent_opinion || '', encrypted_blob, target || '', share_token]
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
    res.status(500).json({ error: err.message });
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
    res.status(500).json({ error: err.message });
  }
});

app.delete('/api/records/id/:id', verifyFirebaseAuth, async (req, res) => {
  const { id } = req.params;
  console.log(`\n🗑️ [DELETE RECORD] ID: ${id}`);
  try {
    const [result] = await queryWithTimeout('DELETE FROM service_drafts WHERE id = ?', [id]);
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
    res.status(500).json({ error: err.message });
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
    res.status(500).json({ error: err.message });
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
    res.status(500).json({ error: err.message });
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
    res.status(500).json({ error: err.message });
  }
});

app.put('/api/notifications/:id/read', verifyFirebaseAuth, async (req, res) => {
  const { id } = req.params;
  try {
    await queryWithTimeout('UPDATE notifications SET is_read = 1 WHERE id = ?', [id]);
    res.json({ message: 'Notification marked as read' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/records/reviewed/:token', async (req, res) => {
  const { token } = req.params;
  const { service_description, agent_opinion } = req.body;
  try {
    const [infoResult] = await queryWithTimeout(
      `SELECT s.case_id, c.case_name, c.user_id, u.email 
       FROM service_drafts s 
       JOIN cases c ON s.case_id = c.id 
       JOIN dash_users u ON c.user_id = u.id 
       WHERE s.share_token = ?`, [token]
    );
    
    if (infoResult.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }

    const { case_name, user_id, email: user_email } = infoResult[0];

    const { encrypted_blob } = req.body;
    
    let updateQuery = `UPDATE service_drafts SET status = 'Reviewed', service_description = ?, agent_opinion = ?, updated_at = NOW()`;
    let queryParams = [service_description || '', agent_opinion || ''];

    if (encrypted_blob) {
      updateQuery = `UPDATE service_drafts SET status = 'Reviewed', encrypted_blob = ?, service_description = ?, agent_opinion = ?, updated_at = NOW()`;
      queryParams = [encrypted_blob, service_description || '', agent_opinion || ''];
    }
    
    updateQuery += ` WHERE share_token = ?`;
    queryParams.push(token);

    const [result] = await queryWithTimeout(updateQuery, queryParams);

    if (result.affectedRows > 0) {
      // 📝 Create Notification for the counselor
      const message = `동행자가 ${case_name} 아동 DB 내용을 수정했어요. 확인해보세요`;
      // 📝 Mark previous unread notifications for the same record as read (Requirement: Replace with latest for same DB)
      await queryWithTimeout(
        'UPDATE notifications SET is_read = 1 WHERE user_id = ? AND record_token = ? AND is_read = 0',
        [user_id, token]
      );

      await queryWithTimeout(
        'INSERT INTO notifications (user_id, case_name, record_token, message, is_read) VALUES (?, ?, ?, ?, 0)',
        [user_id, case_name, token, message]
      );

      console.log(`✅ Record reviewed & Notified (Token: ${token})`);
      res.json({ message: 'Reviewed' });
      
      // Notify extension and mobile app (SSE)
      broadcastEvent('new_record', { user_email, reason: 'reviewed', record_token: token }); 

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
                title: '검토 완료 📝',
                body: `${case_name} 아동 사례 상담 기록이 검토 완료되었어요.`
              },
              data: {
                type: 'review_completed',
                case_id: user_id, // Fallback
                record_token: token
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
    res.status(500).json({ error: err.message });
  }
});

// [Web] 공유 링크 세션 저장소
const authAttempts = new Map(); // token -> { verified, verifiedAt, uid?, count?, lockedUntil? }

// [Web] 2-4. 리뷰어 구글 로그인 (Firebase ID 토큰 검증 후 세션 승인)
app.post('/api/records/reviewer-login/:token', verifyFirebaseAuth, async (req, res) => {
  const { token } = req.params;
  const { uid, email, name, display_name } = req.firebaseUser;
  const reviewerName = display_name || name || email;

  try {
    const [rows] = await queryWithTimeout(
      'SELECT id FROM service_drafts WHERE share_token = ?', [token]
    );
    if (rows.length === 0) return res.status(404).json({ error: '존재하지 않는 링크입니다.' });

    // 리뷰어 계정 생성 또는 조회
    await ensureUserExists(uid, email, reviewerName);

    // 최초 접근 시 reviewer_user_id 연결 (이미 연결된 경우 덮어쓰지 않음)
    await queryWithTimeout(
      'UPDATE service_drafts SET reviewer_user_id = ? WHERE share_token = ? AND reviewer_user_id IS NULL',
      [uid, token]
    );

    // 세션 인증 완료 처리 (기존 share 엔드포인트가 authAttempts로 검증하므로 동일하게 기록)
    authAttempts.set(token, { verified: true, verifiedAt: Date.now(), uid });
    console.log(`✅ [REVIEWER LOGIN] uid=${uid} → token=${token}`);
    res.json({ ok: true });
  } catch (err) {
    console.error('Reviewer login error:', err);
    res.status(500).json({ error: err.message });
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
    res.status(500).json({ error: err.message });
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
    console.log(`✅ Data fetched for ${rows[0].case_name}`);
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// [Web] 3.1. 공유 토큰으로 중간 저장 (Auto-save)
app.put('/api/records/share/:token', async (req, res) => {
  const { token } = req.params;
  const { service_description, agent_opinion } = req.body;
  console.log(`\n💾 [WEB AUTO-SAVE] Token: ${token}`);
  try {
    const [result] = await queryWithTimeout(
      'UPDATE service_drafts SET service_description = ?, agent_opinion = ?, updated_at = NOW() WHERE share_token = ?',
      [service_description || '', agent_opinion || '', token]
    );
    if (result.affectedRows > 0) {
      res.json({ message: 'Saved' });
    } else {
      res.status(404).json({ error: 'Not found' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
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
    'encrypted_blob',
  ];
  try {
    const safeKeys = Object.keys(updateData).filter(k => ALLOWED_UPDATE_FIELDS.includes(k));
    const extraClause = safeKeys.map(k => `${k} = ?`).join(', ');
    const values = safeKeys.map(k => updateData[k]);
    const setClause = extraClause
      ? `${extraClause}, status = 'Reviewed', reviewed_at = NOW()`
      : `status = 'Reviewed', reviewed_at = NOW()`;

    await queryWithTimeout(
      `UPDATE service_drafts SET ${setClause} WHERE id = ?`,
      [...values, id]
    );

    // Get user email to notify
    const [info] = await queryWithTimeout(
      `SELECT u.email FROM service_drafts s JOIN cases c ON s.case_id = c.id JOIN dash_users u ON c.user_id = u.id WHERE s.id = ?`,
      [id]
    );

    if (info.length > 0) {
      broadcastEvent('reviewed', { user_email: info[0].email, record_id: id });
    }

    console.log(`✅ Record status updated to 'Reviewed' & Notification sent`);
    res.json({ message: 'Review completed and data updated' });
  } catch (err) {
    console.error('❌ Review update error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// [Extension] 5. 주입 대기 중인 목록 가져오기 (userId 또는 email로 필터링)
app.get('/api/records/ready', verifyFirebaseAuth, async (req, res) => {
  const { userId, email } = req.query;
  console.log(`\n🚀 [EXTENSION FETCH] Fetching ready records (userId: ${userId || '-'}, email: ${email || '-'})...`);
  try {
    let query = `
      SELECT r.*, c.case_name, c.dong 
      FROM service_drafts r 
      JOIN cases c ON r.case_id = c.id 
      WHERE r.status IN ('Synced', 'Reviewed')
    `;
    const params = [];

    if (email) {
      // 이메일 기반 매칭: Firebase UID와 Google OAuth ID가 달라도 같은 이메일이면 매칭됨
      query += ` AND c.user_id IN (SELECT id FROM dash_users WHERE email = ?)`;
      params.push(email);
    } else if (userId) {
      query += ` AND c.user_id = ?`;
      params.push(userId);
    }

    query += ` ORDER BY r.created_at DESC`;

    const [rows] = await queryWithTimeout(query, params);
    console.log(`✅ Sent ${rows.length} records to extension`);
    res.json(rows);
  } catch (err) {
    console.error('❌ Extension fetch error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// [Mobile] 6. 특정 사용자의 모든 상담 기록 가져오기 (앱 동기화용)
// Firebase UID가 DB에 없는 경우 토큰 이메일로 폴백 (OAuth id vs Firebase UID 불일치 대응)
app.get('/api/records/user/:userId', verifyFirebaseAuth, async (req, res) => {
  const { userId } = req.params;
  console.log(`\n📱 [MOBILE SYNC] Fetching records for user: ${userId}`);
  try {
    // 1) userId로 이메일 조회 
    let email = null;
    const [userRows] = await queryWithTimeout('SELECT email FROM dash_users WHERE id = ?', [userId]);
    if (userRows.length > 0) {
      email = userRows[0].email;
    } else {
      // 2) DB에 없으면 Firebase 토큰의 이메일 사용 (INSERT IGNORE로 누락된 경우)
      email = req.firebaseUser?.email;
      console.log(`⚠️  User ${userId} not in dash_users, using token email: ${email}`);
    }
    
    let rows;
    if (email) {
      // 같은 이메일의 모든 user_id로 레코드 조회 (Chrome OAuth id, Firebase UID 모두 포함)
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
         WHERE r.reviewer_user_id = (SELECT id FROM dash_users WHERE email = ? LIMIT 1)
           AND c.user_id NOT IN (SELECT id FROM dash_users WHERE email = ?)
         ORDER BY created_at DESC`,
        [email, email, email]
      );
      console.log(`✅ Found ${rows.length} records for email: ${email}`);
    } else {
      [rows] = await queryWithTimeout(
        `SELECT r.*, c.case_name, c.dong, u.name AS author_name, 'owned' AS record_type
         FROM service_drafts r
         JOIN cases c ON r.case_id = c.id
         LEFT JOIN dash_users u ON c.user_id = u.id
         WHERE c.user_id = ?
         ORDER BY r.created_at DESC`,
        [userId]
      );
    }
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// [Security] 7. Key Vault API (Zero-Knowledge PIN Sync)
app.get('/api/users/vault/:userId', verifyFirebaseAuth, async (req, res) => {
  const { userId } = req.params;
  try {
    // userId가 DB에 없으면 Firebase 토큰 이메일로 실제 user_id 해석
    const resolvedId = await resolveUserId(userId, req.firebaseUser?.email);
    const [rows] = await queryWithTimeout(
      'SELECT encrypted_vault, salt FROM user_key_vault WHERE user_id = ?',
      [resolvedId]
    );
    if (rows.length === 0) {
      return res.status(404).json({ message: 'Vault not found' });
    }
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
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
    res.status(500).json({ error: err.message });
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
      await queryWithTimeout(
        'DELETE sd FROM service_drafts sd JOIN cases c ON sd.case_id = c.id WHERE c.user_id = ?',
        [uid]
      );
      await queryWithTimeout('DELETE FROM cases WHERE user_id = ?', [uid]);
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
    res.status(500).json({ error: err.message });
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
