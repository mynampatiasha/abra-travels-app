// utils/redis_lock_manager.js
const { getRedisClient } = require('../config/redis');

/**
 * ============================================================================
 * REDIS LOCK MANAGER - PREVENT CONCURRENT ASSIGNMENT CONFLICTS
 * ============================================================================
 * 
 * Ensures only ONE dispatcher can assign a vehicle/roster at a time.
 * 
 * HOW IT WORKS:
 * 1. Dispatcher A tries to assign VEH-001 to Roster RST-001
 * 2. Lock Manager creates: lock:vehicle:VEH-001 = "dispatcher-A-id"
 * 3. Dispatcher B tries to assign VEH-001 (same vehicle, different roster)
 * 4. Lock Manager checks: lock:vehicle:VEH-001 already exists!
 * 5. Returns error: "Vehicle is being assigned by another dispatcher"
 * 6. After assignment, lock is released
 * 
 * FEATURES:
 * ✅ Auto-expiry (locks expire after 30 seconds to prevent deadlocks)
 * ✅ Owner tracking (stores who acquired the lock)
 * ✅ Graceful fallback (if Redis unavailable, uses in-memory locks)
 * ✅ Lock extension (can extend lock if operation takes longer)
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

const DEFAULT_LOCK_DURATION_SEC = 30; // Locks expire after 30 seconds
const EXTENDED_LOCK_DURATION_SEC = 60; // Extended locks for complex operations
const IN_MEMORY_FALLBACK = true; // Use in-memory locks if Redis unavailable

// In-memory fallback (when Redis is down)
const inMemoryLocks = new Map();

// ============================================================================
// HELPER: Clean expired in-memory locks
// ============================================================================

function cleanExpiredMemoryLocks() {
  const now = Date.now();
  for (const [key, lockData] of inMemoryLocks.entries()) {
    if (lockData.expiresAt < now) {
      inMemoryLocks.delete(key);
      console.log(`🧹 Cleaned expired in-memory lock: ${key}`);
    }
  }
}

// Run cleanup every 10 seconds
if (IN_MEMORY_FALLBACK) {
  setInterval(cleanExpiredMemoryLocks, 10000);
}

// ============================================================================
// ACQUIRE LOCK
// ============================================================================

/**
 * Acquire a lock for a resource (vehicle or roster)
 * 
 * @param {string} resourceType - 'vehicle' or 'roster'
 * @param {string} resourceId - ID of the resource to lock
 * @param {string} ownerId - ID of who is acquiring the lock (dispatcher ID)
 * @param {number} durationSec - Lock duration in seconds (default: 30)
 * @returns {Promise<Object>} { success: true/false, lockId, message }
 */
async function acquireLock(resourceType, resourceId, ownerId, durationSec = DEFAULT_LOCK_DURATION_SEC) {
  const lockKey = `lock:${resourceType}:${resourceId}`;
  const lockValue = JSON.stringify({
    ownerId,
    acquiredAt: new Date().toISOString(),
    expiresIn: durationSec,
  });
  
  console.log(`\n${'─'.repeat(80)}`);
  console.log(`🔒 ACQUIRING LOCK`);
  console.log(`${'─'.repeat(80)}`);
  console.log(`   Resource: ${resourceType} (${resourceId})`);
  console.log(`   Owner: ${ownerId}`);
  console.log(`   Duration: ${durationSec} seconds`);
  
  const redis = getRedisClient();
  
  // ──────────────────────────────────────────────────────────────────────
  // METHOD 1: Use Redis (Preferred)
  // ──────────────────────────────────────────────────────────────────────
  if (redis) {
    try {
      // SET key value EX seconds NX
      // - EX: Set expiry time in seconds
      // - NX: Only set if key does NOT exist (atomic operation)
      const result = await redis.set(
        lockKey,
        lockValue,
        'EX', durationSec,
        'NX'
      );
      
      if (result === 'OK') {
        console.log(`   ✅ Lock acquired successfully (Redis)`);
        console.log(`   Lock will expire in ${durationSec} seconds`);
        console.log(`${'─'.repeat(80)}\n`);
        
        return {
          success: true,
          lockId: lockKey,
          method: 'redis',
          expiresIn: durationSec,
          message: 'Lock acquired successfully',
        };
      } else {
        // Lock already exists - someone else has it
        console.log(`   ❌ Lock FAILED - Already locked by another user`);
        
        // Get current lock info
        let currentOwner = 'Unknown';
        try {
          const currentLock = await redis.get(lockKey);
          if (currentLock) {
            const lockData = JSON.parse(currentLock);
            currentOwner = lockData.ownerId;
            console.log(`   Current owner: ${currentOwner}`);
            console.log(`   Acquired at: ${lockData.acquiredAt}`);
          }
        } catch (e) {
          // Could not parse lock data
        }
        
        console.log(`${'─'.repeat(80)}\n`);
        
        return {
          success: false,
          lockId: null,
          method: 'redis',
          message: `${resourceType} is currently being assigned by another dispatcher`,
          currentOwner,
        };
      }
    } catch (error) {
      console.error(`   ⚠️ Redis lock error: ${error.message}`);
      console.log(`   Falling back to in-memory lock...`);
      // Fall through to in-memory method
    }
  }
  
  // ──────────────────────────────────────────────────────────────────────
  // METHOD 2: Use In-Memory Locks (Fallback)
  // ──────────────────────────────────────────────────────────────────────
  if (IN_MEMORY_FALLBACK) {
    console.log(`   Using in-memory lock (Redis unavailable)`);
    
    // Clean expired locks first
    cleanExpiredMemoryLocks();
    
    // Check if lock exists
    if (inMemoryLocks.has(lockKey)) {
      const existingLock = inMemoryLocks.get(lockKey);
      
      // Check if expired
      if (existingLock.expiresAt > Date.now()) {
        console.log(`   ❌ Lock FAILED - Already locked (in-memory)`);
        console.log(`   Current owner: ${existingLock.ownerId}`);
        console.log(`${'─'.repeat(80)}\n`);
        
        return {
          success: false,
          lockId: null,
          method: 'memory',
          message: `${resourceType} is currently being assigned by another dispatcher`,
          currentOwner: existingLock.ownerId,
        };
      } else {
        // Expired - remove it
        inMemoryLocks.delete(lockKey);
      }
    }
    
    // Acquire lock
    inMemoryLocks.set(lockKey, {
      ownerId,
      acquiredAt: new Date().toISOString(),
      expiresAt: Date.now() + (durationSec * 1000),
    });
    
    console.log(`   ✅ Lock acquired successfully (in-memory)`);
    console.log(`   ⚠️ WARNING: In-memory locks only work on single server`);
    console.log(`   Lock will expire in ${durationSec} seconds`);
    console.log(`${'─'.repeat(80)}\n`);
    
    return {
      success: true,
      lockId: lockKey,
      method: 'memory',
      expiresIn: durationSec,
      message: 'Lock acquired successfully (in-memory)',
      warning: 'Using in-memory lock - not suitable for multi-server setup',
    };
  }
  
  // ──────────────────────────────────────────────────────────────────────
  // NO LOCKING AVAILABLE
  // ──────────────────────────────────────────────────────────────────────
  console.log(`   ⚠️ WARNING: No locking mechanism available!`);
  console.log(`   Proceeding without lock (risk of double-assignment)`);
  console.log(`${'─'.repeat(80)}\n`);
  
  return {
    success: true, // Allow operation to proceed
    lockId: null,
    method: 'none',
    message: 'No locking available - proceeding without lock',
    warning: 'Double-assignment prevention disabled!',
  };
}

// ============================================================================
// RELEASE LOCK
// ============================================================================

/**
 * Release a previously acquired lock
 * 
 * @param {string} lockId - Lock ID returned from acquireLock()
 * @param {string} ownerId - ID of who acquired the lock (for verification)
 * @returns {Promise<Object>} { success: true/false, message }
 */
async function releaseLock(lockId, ownerId) {
  console.log(`\n${'─'.repeat(80)}`);
  console.log(`🔓 RELEASING LOCK`);
  console.log(`${'─'.repeat(80)}`);
  console.log(`   Lock ID: ${lockId}`);
  console.log(`   Owner: ${ownerId}`);
  
  if (!lockId) {
    console.log(`   ⚠️ No lock ID provided (probably no lock was acquired)`);
    console.log(`${'─'.repeat(80)}\n`);
    return { success: true, message: 'No lock to release' };
  }
  
  const redis = getRedisClient();
  
  // ──────────────────────────────────────────────────────────────────────
  // METHOD 1: Redis
  // ──────────────────────────────────────────────────────────────────────
  if (redis) {
    try {
      // Verify ownership before deleting (security check)
      const currentLock = await redis.get(lockId);
      
      if (!currentLock) {
        console.log(`   ⚠️ Lock already expired or doesn't exist`);
        console.log(`${'─'.repeat(80)}\n`);
        return {
          success: true,
          message: 'Lock already released or expired',
        };
      }
      
      // Verify owner
      try {
        const lockData = JSON.parse(currentLock);
        if (lockData.ownerId !== ownerId) {
          console.log(`   ❌ Cannot release - Lock owned by: ${lockData.ownerId}`);
          console.log(`${'─'.repeat(80)}\n`);
          return {
            success: false,
            message: 'Cannot release lock - owned by another user',
          };
        }
      } catch (e) {
        console.log(`   ⚠️ Could not verify lock ownership`);
      }
      
      // Delete lock
      await redis.del(lockId);
      
      console.log(`   ✅ Lock released successfully (Redis)`);
      console.log(`${'─'.repeat(80)}\n`);
      
      return {
        success: true,
        message: 'Lock released successfully',
      };
    } catch (error) {
      console.error(`   ⚠️ Redis error: ${error.message}`);
      // Fall through to in-memory
    }
  }
  
  // ──────────────────────────────────────────────────────────────────────
  // METHOD 2: In-Memory
  // ──────────────────────────────────────────────────────────────────────
  if (IN_MEMORY_FALLBACK && inMemoryLocks.has(lockId)) {
    const lockData = inMemoryLocks.get(lockId);
    
    // Verify ownership
    if (lockData.ownerId !== ownerId) {
      console.log(`   ❌ Cannot release - Lock owned by: ${lockData.ownerId}`);
      console.log(`${'─'.repeat(80)}\n`);
      return {
        success: false,
        message: 'Cannot release lock - owned by another user',
      };
    }
    
    inMemoryLocks.delete(lockId);
    
    console.log(`   ✅ Lock released successfully (in-memory)`);
    console.log(`${'─'.repeat(80)}\n`);
    
    return {
      success: true,
      message: 'Lock released successfully (in-memory)',
    };
  }
  
  console.log(`   ⚠️ Lock not found (may have already expired)`);
  console.log(`${'─'.repeat(80)}\n`);
  
  return {
    success: true,
    message: 'Lock not found (already released or expired)',
  };
}

// ============================================================================
// CHECK LOCK STATUS
// ============================================================================

/**
 * Check if a resource is currently locked
 * 
 * @param {string} resourceType - 'vehicle' or 'roster'
 * @param {string} resourceId - ID of the resource
 * @returns {Promise<Object>} { isLocked: true/false, owner, acquiredAt, expiresIn }
 */
async function checkLock(resourceType, resourceId) {
  const lockKey = `lock:${resourceType}:${resourceId}`;
  
  const redis = getRedisClient();
  
  // Check Redis
  if (redis) {
    try {
      const lockData = await redis.get(lockKey);
      
      if (!lockData) {
        return {
          isLocked: false,
          message: 'Resource is available',
        };
      }
      
      const lock = JSON.parse(lockData);
      const ttl = await redis.ttl(lockKey);
      
      return {
        isLocked: true,
        owner: lock.ownerId,
        acquiredAt: lock.acquiredAt,
        expiresIn: ttl,
        method: 'redis',
      };
    } catch (error) {
      console.error(`Redis check error: ${error.message}`);
    }
  }
  
  // Check in-memory
  if (IN_MEMORY_FALLBACK && inMemoryLocks.has(lockKey)) {
    const lock = inMemoryLocks.get(lockKey);
    
    if (lock.expiresAt > Date.now()) {
      return {
        isLocked: true,
        owner: lock.ownerId,
        acquiredAt: lock.acquiredAt,
        expiresIn: Math.floor((lock.expiresAt - Date.now()) / 1000),
        method: 'memory',
      };
    } else {
      // Expired
      inMemoryLocks.delete(lockKey);
      return {
        isLocked: false,
        message: 'Resource is available',
      };
    }
  }
  
  return {
    isLocked: false,
    message: 'Resource is available (no locking system active)',
  };
}

// ============================================================================
// EXTEND LOCK
// ============================================================================

/**
 * Extend an existing lock (useful for long operations)
 * 
 * @param {string} lockId - Lock ID to extend
 * @param {string} ownerId - Owner ID (for verification)
 * @param {number} additionalSec - Additional seconds to add
 * @returns {Promise<Object>} { success: true/false, newExpiresIn }
 */
async function extendLock(lockId, ownerId, additionalSec = 30) {
  console.log(`\n⏱️ Extending lock: ${lockId} by ${additionalSec} seconds`);
  
  const redis = getRedisClient();
  
  // Redis
  if (redis) {
    try {
      // Verify ownership
      const currentLock = await redis.get(lockId);
      if (!currentLock) {
        return {
          success: false,
          message: 'Lock does not exist or has expired',
        };
      }
      
      const lockData = JSON.parse(currentLock);
      if (lockData.ownerId !== ownerId) {
        return {
          success: false,
          message: 'Cannot extend lock - not the owner',
        };
      }
      
      // Extend TTL
      const currentTTL = await redis.ttl(lockId);
      const newTTL = currentTTL + additionalSec;
      
      await redis.expire(lockId, newTTL);
      
      console.log(`   ✅ Lock extended to ${newTTL} seconds`);
      
      return {
        success: true,
        newExpiresIn: newTTL,
        message: 'Lock extended successfully',
      };
    } catch (error) {
      console.error(`   ❌ Error extending lock: ${error.message}`);
    }
  }
  
  // In-memory
  if (IN_MEMORY_FALLBACK && inMemoryLocks.has(lockId)) {
    const lock = inMemoryLocks.get(lockId);
    
    if (lock.ownerId !== ownerId) {
      return {
        success: false,
        message: 'Cannot extend lock - not the owner',
      };
    }
    
    lock.expiresAt += (additionalSec * 1000);
    inMemoryLocks.set(lockId, lock);
    
    console.log(`   ✅ Lock extended (in-memory)`);
    
    return {
      success: true,
      newExpiresIn: Math.floor((lock.expiresAt - Date.now()) / 1000),
      message: 'Lock extended successfully (in-memory)',
    };
  }
  
  return {
    success: false,
    message: 'Lock not found',
  };
}

// ============================================================================
// ACQUIRE MULTIPLE LOCKS (For Complex Operations)
// ============================================================================

/**
 * Acquire locks for multiple resources atomically
 * If any lock fails, all are released
 * 
 * @param {Array} resources - Array of { type, id } objects
 * @param {string} ownerId - Owner ID
 * @param {number} durationSec - Lock duration
 * @returns {Promise<Object>} { success: true/false, locks: [], message }
 */
async function acquireMultipleLocks(resources, ownerId, durationSec = DEFAULT_LOCK_DURATION_SEC) {
  console.log(`\n${'═'.repeat(80)}`);
  console.log(`🔒 ACQUIRING ${resources.length} LOCKS`);
  console.log(`${'═'.repeat(80)}`);
  
  const acquiredLocks = [];
  
  try {
    // Try to acquire all locks
    for (const resource of resources) {
      const result = await acquireLock(resource.type, resource.id, ownerId, durationSec);
      
      if (!result.success) {
        // Failed to acquire this lock - release all previously acquired locks
        console.log(`\n❌ Failed to acquire lock for ${resource.type}:${resource.id}`);
        console.log(`   Rolling back all acquired locks...`);
        
        for (const lock of acquiredLocks) {
          await releaseLock(lock.lockId, ownerId);
        }
        
        console.log(`${'═'.repeat(80)}\n`);
        
        return {
          success: false,
          locks: [],
          message: result.message,
          failedResource: resource,
        };
      }
      
      acquiredLocks.push(result);
    }
    
    console.log(`\n✅ All ${resources.length} locks acquired successfully`);
    console.log(`${'═'.repeat(80)}\n`);
    
    return {
      success: true,
      locks: acquiredLocks,
      message: 'All locks acquired successfully',
    };
  } catch (error) {
    console.error(`\n❌ Error acquiring locks: ${error.message}`);
    
    // Release any acquired locks
    for (const lock of acquiredLocks) {
      await releaseLock(lock.lockId, ownerId);
    }
    
    console.log(`${'═'.repeat(80)}\n`);
    
    return {
      success: false,
      locks: [],
      message: error.message,
    };
  }
}

// ============================================================================
// RELEASE MULTIPLE LOCKS
// ============================================================================

/**
 * Release multiple locks at once
 * 
 * @param {Array} locks - Array of lock objects from acquireMultipleLocks
 * @param {string} ownerId - Owner ID
 * @returns {Promise<Object>} { success: true/false, released: number }
 */
async function releaseMultipleLocks(locks, ownerId) {
  console.log(`\n🔓 Releasing ${locks.length} locks...`);
  
  let releasedCount = 0;
  
  for (const lock of locks) {
    try {
      const result = await releaseLock(lock.lockId, ownerId);
      if (result.success) {
        releasedCount++;
      }
    } catch (error) {
      console.error(`   ⚠️ Error releasing lock ${lock.lockId}: ${error.message}`);
    }
  }
  
  console.log(`✅ Released ${releasedCount}/${locks.length} locks\n`);
  
  return {
    success: releasedCount === locks.length,
    released: releasedCount,
    total: locks.length,
  };
}

// ============================================================================
// EXPORTS
// ============================================================================

module.exports = {
  acquireLock,
  releaseLock,
  checkLock,
  extendLock,
  acquireMultipleLocks,
  releaseMultipleLocks,
  DEFAULT_LOCK_DURATION_SEC,
  EXTENDED_LOCK_DURATION_SEC,
};
// ```

// ---

// ## **✅ WHAT THIS FILE DOES:**
// ```
// 🔒 LOCK ACQUISITION
//    ├─ Try Redis first (distributed lock)
//    ├─ Fallback to in-memory (single server)
//    └─ Atomic operation (SET NX)

// 🔓 LOCK RELEASE
//    ├─ Verify ownership before releasing
//    ├─ Auto-cleanup expired locks
//    └─ Safe error handling

// ⏱️ LOCK EXTENSION
//    └─ Extend if operation takes longer

// 🔐 MULTIPLE LOCKS
//    ├─ Acquire all or none (atomic)
//    └─ Auto-rollback if any fails