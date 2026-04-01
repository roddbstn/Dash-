require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const mysql = require('mysql2/promise');

const app = express();
const port = process.env.PORT || 3000;

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
app.use(cors()); // In production, we can restrict this to specific domains later
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '10mb' }));
app.use(express.static(path.join(__dirname, 'reviewer_site'))); // Serve static files

// --- SSE Clients ---
let sseClients = [];

function broadcastEvent(event, data) {
  console.log(`📡 Broadcasting [${event}] to ${sseClients.length} clients...`);
  sseClients.forEach(client => {
    // Check if client has a filter (like email) or just send to all
    if (!client.email || (data.user_email && client.email === data.user_email)) {
      client.res.write(`data: ${JSON.stringify({ event, ...data })}\n\n`);
    }
  });
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
app.get('/api/events', (req, res) => {
  const { email } = req.query;
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  
  res.write(`data: ${JSON.stringify({ event: 'connected', status: 'ok' })}\n\n`);
  
  const client = { id: Date.now(), res, email };
  sseClients.push(client);
  console.log(`🔌 New SSE client connected: ${email || 'unknown'} (Total: ${sseClients.length})`);
  
  req.on('close', () => {
    sseClients = sseClients.filter(c => c.id !== client.id);
    console.log(`🔌 SSE client disconnected (Total: ${sseClients.length})`);
  });
});

// Alias for compatibility
app.get('/api/stream', (req, res) => {
  res.redirect('/api/events');
});

// [Mobile] 0. 사용자 정보 조회 및 관리
app.get('/api/users/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const [users] = await pool.query('SELECT * FROM dash_users WHERE id = ?', [id]);
    if (users.length > 0) {
      res.json(users[0]);
    } else {
      res.status(404).json({ error: 'User not found' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/users/update_profile', async (req, res) => {
  const { id, name, email } = req.body;
  console.log(`\n👤 [PROFILE UPDATE] User: ${id}, New Name: ${name}, Email: ${email}`);
  try {
    const resolvedEmail = email || `user_${id.substring(0, 8)}@gmail.com`;
    const [result] = await pool.query(
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

// [Test] 로컬 익스텐션 테스트용 UID 조회 (이메일로 실제 모바일의 UID 찾기)
app.get('/api/test/uid-by-email', async (req, res) => {
  const { email } = req.query;
  try {
    const [rows] = await pool.query('SELECT user_id FROM service_drafts WHERE user_email = ? LIMIT 1', [email]);
    if (rows.length > 0) {
      return res.json({ uid: rows[0].user_id });
    }
    res.json({ uid: email.split('@')[0] });
  } catch (err) {
    res.json({ uid: email.split('@')[0] });
  }
});

// [Mobile] FCM 토큰 저장
app.post('/api/users/fcm_token', async (req, res) => {
  const { id, token, email } = req.body;
  console.log(`\n📱 [FCM TOKEN] User: ${id}, Token: ${token.substring(0, 10)}..., Email: ${email}`);
  try {
    const resolvedEmail = email || `user_${id.substring(0, 8)}@gmail.com`;
    await pool.query(
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
app.post('/api/users/public_key', async (req, res) => {
  const { id, public_key } = req.body;
  console.log(`\n🔑 [PUBLIC KEY] Saving for User: ${id}`);
  try {
    await pool.query('UPDATE dash_users SET public_key = ? WHERE id = ?', [public_key, id]);
    res.json({ message: 'Public key saved' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/users/:id/public_key', async (req, res) => {
  const { id } = req.params;
  try {
    const [rows] = await pool.query('SELECT public_key FROM dash_users WHERE id = ?', [id]);
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
app.post('/api/cases', async (req, res) => {
  const { id, user_id, case_name, dong, target_system_code, user_name } = req.body;
  console.log(`\n📦 [NEW CASE] 아동명: ${case_name}, 동: ${dong} (ID: ${id})`);
  
  try {
    // 1. 해당 사용자 아이디가 dash_users에 없으면 자동으로 생성
    const [users] = await pool.query('SELECT id FROM dash_users WHERE id = ?', [user_id]);
    if (users.length === 0) {
      console.log(`👤 New Social User detected (${user_id}), creating user record...`);
      const userEmail = req.body.user_email || `user_${user_id.substring(0,8)}@gmail.com`;
      const name = user_name || userEmail.split('@')[0];
      await pool.query(
        'INSERT INTO dash_users (id, email, name, organization_id) VALUES (?, ?, ?, ?)',
        [user_id, userEmail, name, 'DEFAULT_ORG']
      );
    } else if (user_name) {
      // 이미 사용자가 있고 이름이 전달되었다면 이름 업데이트 (최초 연동 시 displayName 적용 용도)
      // 단, 수동으로 이미 이름을 정했거나(NULL이 아니거나) 이메일이 아닌 경우만 스킵
      await pool.query('UPDATE dash_users SET name = ? WHERE id = ? AND (name IS NULL OR name = email OR name = "")', [user_name, user_id]);
    }

    // 2. 사례 저장 (사용자가 보낸 ID를 그대로 사용)
    const [result] = await pool.query(
      `INSERT INTO cases (id, user_id, case_name, dong, target_system_code) 
       VALUES (?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE 
       case_name = VALUES(case_name), 
       dong = VALUES(dong),
       user_id = VALUES(user_id)`,
      [id, user_id, case_name, dong, target_system_code || 'NCADS_v2']
    );
    console.log(`✅ Case saved/updated in DB (ID: ${id})`);
    res.json({ id: id, message: 'Case created or updated' });
  } catch (err) {
    console.error('❌ Case creation error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// [Mobile] 2. 상담 기록(Draft) 서버로 동기화
app.post('/api/records', async (req, res) => {
  const { 
    case_id, case_name, dong, user_id, user_email, target, provision_type, method, service_type, service_name, 
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
    const [cases] = await pool.query('SELECT id FROM cases WHERE id = ?', [case_id]);
    
    // 2. 만약 사례가 없다면 (과거 동기화 누락 등), 임시 사례 생성
    if (cases.length === 0) {
      console.log(`⚠️  Case ID ${case_id} not found. Creating placeholder case...`);
      
      // user_id가 요청에 포함되어 있으면 사용, 없으면 DB에서 찾기
      if (!resolvedUserId) {
        const [users] = await pool.query('SELECT id FROM dash_users LIMIT 1');
        resolvedUserId = users.length > 0 ? users[0].id : null;
      }
      
      // user_id로 dash_users에 레코드가 없으면 생성
      if (resolvedUserId) {
        const [existingUser] = await pool.query('SELECT id FROM dash_users WHERE id = ?', [resolvedUserId]);
        if (existingUser.length === 0) {
          const email = user_email || `user_${resolvedUserId.substring(0,8)}@gmail.com`;
          await pool.query(
            'INSERT INTO dash_users (id, email, organization_id) VALUES (?, ?, ?)',
            [resolvedUserId, email, 'DEFAULT_ORG']
          );
          console.log(`👤 Auto-created user: ${resolvedUserId} (${email})`);
        }
      }
      
      await pool.query(
        `INSERT INTO cases (id, user_id, case_name, dong) VALUES (?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE case_name = VALUES(case_name), dong = VALUES(dong), user_id = VALUES(user_id)`,
        [case_id, resolvedUserId, case_name || '미지정 사례', dong || '확인 필요']
      );
    } else {
      // 사례가 이미 있으면, 이름이 '복구된 사례'인 경우 올바른 이름으로 업데이트
      const existingCase = cases[0];
      if (case_name) {
        await pool.query(
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
      const [existing] = await pool.query('SELECT id FROM service_drafts WHERE share_token = ?', [share_token]);
      if (existing.length > 0) {
        recordId = existing[0].id;
        await pool.query(
          `UPDATE service_drafts SET 
            status='Synced', 
            provision_type=?, 
            method=?, 
            service_type=?, 
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
          [provision_type, method, service_type, service_name, location, start_time, end_time, service_count, travel_time, service_description || '', agent_opinion || '', encrypted_blob, target || '', recordId]
        );
        console.log(`🔄 Record updated successfully (DB ID: ${recordId})`);
      }
    }

    if (!recordId) {
      share_token = Math.random().toString(36).substring(2, 15) + Date.now().toString(36);
      const [result] = await pool.query(
        `INSERT INTO service_drafts 
        (case_id, provision_type, method, service_type, service_name, location, start_time, end_time, service_count, travel_time, service_description, agent_opinion, encrypted_blob, target, share_token, status) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Synced')`,
        [case_id, provision_type, method, service_type, service_name, location, start_time, end_time, service_count, travel_time, service_description || '', agent_opinion || '', encrypted_blob, target || '', share_token]
      );
      recordId = result.insertId;
      console.log(`✅ Record synced successfully (DB ID: ${recordId})`);
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
app.delete('/api/records/token/:token', async (req, res) => {
  const { token } = req.params;
  const { user_email } = req.body || {};
  console.log(`\n🗑️ [DELETE RECORD] Token: ${token} (User: ${user_email||'unknown'})`);
  try {
    const [result] = await pool.query('DELETE FROM service_drafts WHERE share_token = ?', [token]);
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

app.delete('/api/records/id/:id', async (req, res) => {
  const { id } = req.params;
  console.log(`\n🗑️ [DELETE RECORD] ID: ${id}`);
  try {
    const [result] = await pool.query('DELETE FROM service_drafts WHERE id = ?', [id]);
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

// [Mobile] 2-2. 활성 상태의 토큰 목록과 서버 간 동기화 (유령 데이터 정리)
app.post('/api/records/sync_active', async (req, res) => {
  const { user_email, active_tokens } = req.body;
  if (!user_email) return res.status(400).json({ error: 'user_email required' });
  
  try {
    // 찾을 대상: 내 이메일로 작성된 모든 service_drafts 중 active_tokens에 포함되지 않은 것.
    // user_email로 찾기 위해 dash_users를 조인하거나, cases 테이블을 통해 유저 확인.
    // 여기서는 간단히 dash_users -> cases -> service_drafts 로 조회.
    let deleteQuery;
    let deleteParams;
    
    if (active_tokens && active_tokens.length > 0) {
      deleteQuery = `
        DELETE r FROM service_drafts r
        JOIN cases c ON r.case_id = c.id
        JOIN dash_users u ON c.user_id = u.id
        WHERE u.email = ? AND r.share_token NOT IN (?)
      `;
      deleteParams = [user_email, active_tokens];
    } else {
      // active_tokens가 빈 배열이면 사용자의 모든 drafts 삭제
      deleteQuery = `
        DELETE r FROM service_drafts r
        JOIN cases c ON r.case_id = c.id
        JOIN dash_users u ON c.user_id = u.id
        WHERE u.email = ?
      `;
      deleteParams = [user_email];
    }
    
    const [result] = await pool.query(deleteQuery, deleteParams);
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
app.get('/api/notifications/:userId', async (req, res) => {
  const { userId } = req.params;
  try {
    const [rows] = await pool.query(
      'SELECT id, case_name, record_token, message, is_read, created_at FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 50',
      [userId]
    );
    res.json(rows);
  } catch (err) {
    console.error('❌ Fetch Notifications Error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

app.put('/api/notifications/:id/read', async (req, res) => {
  const { id } = req.params;
  try {
    await pool.query('UPDATE notifications SET is_read = 1 WHERE id = ?', [id]);
    res.json({ message: 'Notification marked as read' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/records/reviewed/:token', async (req, res) => {
  const { token } = req.params;
  const { service_description, agent_opinion } = req.body;
  try {
    const [infoResult] = await pool.query(
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

    const [result] = await pool.query(updateQuery, queryParams);

    if (result.affectedRows > 0) {
      // 📝 Create Notification for the counselor
      const message = `${case_name} 아동 상담 사례 검토가 완료되었어요. 리포트를 확인해 보세요!`;
      // 📝 Mark previous unread notifications for the same record as read (Requirement: Replace with latest for same DB)
      await pool.query(
        'UPDATE notifications SET is_read = 1 WHERE user_id = ? AND record_token = ? AND is_read = 0',
        [user_id, token]
      );

      await pool.query(
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
          const [userRows] = await pool.query('SELECT fcm_token FROM dash_users WHERE id = ?', [user_id]);
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

// [Web] 3. 공유 토큰으로 모든 데이터 불러오기
app.get('/api/records/share/:token', async (req, res) => {
  console.log(`\n🔗 [WEB ACCESS] Token: ${req.params.token}`);
  try {
    const [rows] = await pool.query(
      `SELECT r.*, c.case_name, c.dong, c.target_system_code, u.name as user_name
       FROM service_drafts r 
       JOIN cases c ON r.case_id = c.id 
       LEFT JOIN dash_users u ON c.user_id = u.id
       WHERE r.share_token = ?`,
      [req.params.token]
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
    const [result] = await pool.query(
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
  
  try {
    const fields = Object.keys(updateData).map(key => `${key} = ?`).join(', ');
    const values = Object.values(updateData);
    
    await pool.query(
      `UPDATE service_drafts SET ${fields}, status = 'Reviewed', reviewed_at = NOW() WHERE id = ?`,
      [...values, id]
    );

    // Get user email to notify
    const [info] = await pool.query(
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
app.get('/api/records/ready', async (req, res) => {
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

    const [rows] = await pool.query(query, params);
    console.log(`✅ Sent ${rows.length} records to extension`);
    res.json(rows);
  } catch (err) {
    console.error('❌ Extension fetch error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// [Mobile] 6. 특정 사용자의 모든 상담 기록 가져오기 (앱 동기화용)
app.get('/api/records/user/:userId', async (req, res) => {
  const { userId } = req.params;
  console.log(`\n📱 [MOBILE SYNC] Fetching records for user: ${userId}`);
  try {
    const [rows] = await pool.query(
      `SELECT r.*, c.case_name, c.dong 
       FROM service_drafts r 
       JOIN cases c ON r.case_id = c.id 
       WHERE c.user_id = ? 
       ORDER BY r.created_at DESC`,
      [userId]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// [Security] 7. Key Vault API (Zero-Knowledge PIN Sync)
app.get('/api/users/vault/:userId', async (req, res) => {
  const { userId } = req.params;
  try {
    const [rows] = await pool.query(
      'SELECT encrypted_vault, salt FROM user_key_vault WHERE user_id = ?',
      [userId]
    );
    if (rows.length === 0) {
      return res.status(404).json({ message: 'Vault not found' });
    }
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/users/vault', async (req, res) => {
  const { user_id, encrypted_vault, salt } = req.body;
  if (!user_id || !encrypted_vault) {
    return res.status(400).json({ error: 'Missing required fields' });
  }
  try {
    await pool.query(
      `INSERT INTO user_key_vault (user_id, encrypted_vault, salt) 
       VALUES (?, ?, ?) 
       ON DUPLICATE KEY UPDATE encrypted_vault = ?, salt = ?`,
      [user_id, encrypted_vault, salt, encrypted_vault, salt]
    );
    res.json({ success: true, message: 'Vault updated successfully' });
  } catch (err) {
    console.error('❌ Vault update error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// [Security] 8. User Deletion (PIPL Compliance)
app.delete('/api/users/:id', async (req, res) => {
  const { id } = req.params;
  const { email } = req.query;
  console.log(`\n🗑️ [USER DEletion] User ID: ${id}, Email: ${email}`);
  try {
    let query = 'DELETE FROM dash_users WHERE id = ?';
    let params = [id];
    if (email) {
      query = 'DELETE FROM dash_users WHERE id = ? OR email = ?';
      params = [id, email];
    }
    // 모든 유저 데이터(사례, 볼트, 알림 등)는 Foreign Key ON DELETE CASCADE로 자동 삭제됨
    const [result] = await pool.query(query, params);
    if (result.affectedRows > 0) {
      res.json({ success: true, message: 'User data deleted successfully' });
    } else {
      res.status(404).json({ error: 'User not found' });
    }
  } catch (err) {
    console.error('❌ User deletion error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

app.listen(port, () => {
  console.log(`\n========================================`);
  console.log(`🚀 Dash Server running on http://localhost:${port}`);
  console.log(`========================================\n`);
});
