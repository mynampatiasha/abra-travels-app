// services/driver_login_credentials.js
// ============================================================================
// Helpers for the driver login-credentials feature:
// temporary password generation + audit logging (no secrets ever logged).
// ============================================================================

const crypto = require('crypto');

const PASSWORD_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
const PASSWORD_LENGTH = 12;

function randomPassword() {
  let password = '';
  for (let i = 0; i < PASSWORD_LENGTH; i++) {
    password += PASSWORD_ALPHABET.charAt(crypto.randomInt(PASSWORD_ALPHABET.length));
  }
  return password;
}

/**
 * Whether a candidate password is acceptable: must not be a repeated/narrow
 * pattern (fewer than 4 distinct characters) and must not contain the
 * driver's email local-part, phone number, or name.
 */
function isPasswordAcceptable(password, owner) {
  const lowered = password.toLowerCase();
  if (new Set(lowered).size < 4) return false;

  const emailLocalPart = owner.email ? owner.email.split('@')[0] : null;
  const candidates = [emailLocalPart, owner.phone, owner.firstName, owner.lastName]
    .filter((value) => typeof value === 'string' && value.length >= 4)
    .map((value) => value.toLowerCase());

  return !candidates.some((value) => lowered.includes(value));
}

/**
 * Generates a random temporary password that passes isPasswordAcceptable
 * for the given driver, retrying a few times if needed.
 */
function generateDriverTemporaryPassword(owner) {
  for (let attempt = 0; attempt < 10; attempt++) {
    const candidate = randomPassword();
    if (isPasswordAcceptable(candidate, owner)) {
      return candidate;
    }
  }
  throw new Error('Could not generate an acceptable temporary password');
}

/**
 * Records an audit entry for a driver-login action. Never pass secrets
 * (passwords, hashes, tokens) in `details`.
 */
async function recordDriverLoginAudit(db, { action, driverId, driverObjectId, performedBy, details }) {
  try {
    await db.collection('audit_logs').insertOne({
      action,
      targetType: 'driver_login',
      driverId: driverId || null,
      driverObjectId: driverObjectId || null,
      performedBy: performedBy
        ? {
            userId: performedBy.userId,
            email: performedBy.email,
            role: performedBy.role,
          }
        : null,
      details: details || {},
      createdAt: new Date(),
    });
  } catch (err) {
    console.error('⚠️ Failed to record driver login audit entry:', err.message);
  }
}

/**
 * Some drivers predate the drivers-collection login system: they already
 * have a working login stored as an admin_users record with role:'driver'
 * (a legacy path from before this feature existed), using the same email
 * as their driver record. For those, "no login" / "create login" would be
 * wrong — they already have one, just not in the drivers collection.
 * Returns the legacy account (no secrets) if one exists, else null.
 */
async function findLegacyDriverAccount(db, email) {
  if (!email) return null;
  const lowerEmail = email.toLowerCase();
  const legacy = await db.collection('admin_users').findOne(
    { email: lowerEmail, role: 'driver' },
    { projection: { _id: 1, email: 1, role: 1, status: 1, createdAt: 1 } }
  );
  return legacy || null;
}

module.exports = {
  generateDriverTemporaryPassword,
  isPasswordAcceptable,
  recordDriverLoginAudit,
  findLegacyDriverAccount,
};
