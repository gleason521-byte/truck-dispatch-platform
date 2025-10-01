const http = require('http');
const fs = require('fs');
const path = require('path');

// Load .ENV if present so GOOGLE_APPLICATION_CREDENTIALS and other vars are available
try {
  require('dotenv').config({ path: path.join(__dirname, '..', '.ENV') });
} catch (e) {
  // dotenv may not be installed yet; ignore and continue
}

// Ensure we load .ENV manually too (robust fallback) so processes started without dotenv still pick it up
try {
  const repoEnv = path.join(__dirname, '..', '.ENV');
  if (fs.existsSync(repoEnv)) {
    const raw = fs.readFileSync(repoEnv, 'utf8');
    raw.split(/\r?\n/).forEach(line => {
      line = line.trim();
      if (!line || line.startsWith('#') || line.startsWith('```')) return;
      const idx = line.indexOf('=');
      if (idx > 0) {
        const key = line.slice(0, idx).trim();
        const val = line.slice(idx + 1).trim();
        if (!process.env[key]) {
          process.env[key] = val;
        }
      }
    });
  }
} catch (e) {
  // don't fail startup for env parsing
}

const port = process.env.PORT || 3000;

// Logging setup
const logsDir = path.join(__dirname, '..', 'logs');
if (!fs.existsSync(logsDir)) { fs.mkdirSync(logsDir, { recursive: true }); }
const logPath = path.join(logsDir, 'API_Server.log');
function log(message, meta) {
  const entry = { ts: new Date().toISOString(), msg: message };
  if (meta) entry.meta = meta;
  try { fs.appendFileSync(logPath, JSON.stringify(entry) + '\n'); } catch (e) { /* ignore logging errors */ }
}

function slog(level, message, meta) {
  log(message, Object.assign({ level: level }, meta || {}));
}

// Initialize Firebase Admin using the bundled service account (local dev)
let firebaseAdmin = null;
let firebaseInitError = null;
try {
  const admin = require('firebase-admin');
  const serviceAccountPath = path.resolve(__dirname, '..', 'studio-9174896613-347b2-firebase-adminsdk-fbsvc-81489eb59d.json');

  console.log('[Startup] Using bundled Firebase credential:', serviceAccountPath);

  if (!fs.existsSync(serviceAccountPath)) {
    const msg = '[Startup] Credential file not found: ' + serviceAccountPath;
    console.error(msg);
    firebaseInitError = msg;
  } else {
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    firebaseAdmin = admin;
    firebaseInitError = null;
    console.log('[Startup] Firebase Admin initialized successfully.');
    log('Firebase Admin initialized with ' + serviceAccountPath);
  }
} catch (e) {
  firebaseInitError = String(e);
  log('Firebase Admin initialization error: ' + firebaseInitError);
}

// Simple in-memory user store for dev auth endpoints
const users = {}; // email -> { salt, hash }
const sessions = {}; // token -> email

function hashPassword(password, salt) {
  const crypto = require('crypto');
  salt = salt || crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(password, salt, 100000, 64, 'sha512').toString('hex');
  return { salt, hash };
}

function verifyPassword(password, salt, hash) {
  const crypto = require('crypto');
  const h = crypto.pbkdf2Sync(password, salt, 100000, 64, 'sha512').toString('hex');
  return h === hash;
}

function parseJsonBody(req) {
  return new Promise((resolve, reject) => {
    let s = '';
    req.on('data', c => s += c);
    req.on('end', () => {
      if (!s) return resolve(null);
      try { resolve(JSON.parse(s)); } catch (e) { reject(e); }
    });
    req.on('error', reject);
  });
}

const express = require('express');
const app = express();
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'ok', pid: process.pid });
});

app.get('/firebase', (req, res) => {
  const info = {
    initialized: !!(firebaseAdmin && !firebaseInitError),
    error: firebaseInitError,
    projectId: firebaseAdmin?.app()?.options?.credential?.projectId || null
  };
  res.json(info);
});

app.post('/auth/signup', (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });
  const lower = email.toLowerCase();
  if (users[lower]) return res.status(409).json({ error: 'user exists' });
  const { salt, hash } = hashPassword(password);
  users[lower] = { salt, hash };
  slog('info', 'user_signup', { email: lower });
  res.status(201).json({ ok: true });
});

app.post('/auth/login', (req, res) => {
  const { email, password } = req.body;
  const lower = email.toLowerCase();
  const user = users[lower];
  if (!user || !verifyPassword(password, user.salt, user.hash)) return res.status(401).json({ error: 'invalid credentials' });
  const token = require('crypto').randomBytes(24).toString('hex');
  sessions[token] = lower;
  slog('info', 'user_login', { email: lower });
  res.json({ token });
});

function verifyToken(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const token = authHeader.replace('Bearer ', '');
  firebaseAdmin.auth().verifyIdToken(token)
    .then(decoded => {
      req.user = decoded;
      next();
    })
    .catch(() => res.status(401).json({ error: 'Unauthorized' }));
}

app.get('/secure', verifyToken, (req, res) => {
  res.json({ message: `Welcome ${req.user.email}` });
});

app.listen(port, () => {
  console.log(`API server listening on ${port}`);
  log(`API server listening on ${port}`);
});
