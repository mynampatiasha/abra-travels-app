// config/redis.js
const Redis = require('ioredis');

let redisClient = null;
let redisPub = null;
let redisSub = null;

const REDIS_CONFIG = {
  host: process.env.REDIS_HOST || 'localhost',
  port: process.env.REDIS_PORT || 6379,
  password: process.env.REDIS_PASSWORD || undefined,
  retryStrategy: (times) => {
    const delay = Math.min(times * 50, 2000);
    return delay;
  },
  maxRetriesPerRequest: 3,
  enableReadyCheck: true,
  enableOfflineQueue: true,
};

async function connectRedis() {
  try {
    console.log('🔄 Connecting to Redis...');
    
    // Main client for get/set operations
    redisClient = new Redis(REDIS_CONFIG);
    
    // Publisher for Pub/Sub
    redisPub = new Redis(REDIS_CONFIG);
    
    // Subscriber for Pub/Sub
    redisSub = new Redis(REDIS_CONFIG);
    
    redisClient.on('connect', () => {
      console.log('✅ Redis connected');
    });
    
    redisClient.on('error', (err) => {
      console.warn('⚠️  Redis error (continuing without Redis):', err.message);
    });
    
    redisClient.on('ready', () => {
      console.log('✅ Redis ready');
    });
    
    // Test connection with timeout
    await Promise.race([
      redisClient.ping(),
      new Promise((_, reject) => setTimeout(() => reject(new Error('Redis connection timeout')), 3000))
    ]);
    
    console.log('✅ Redis connection verified');
    
    return { redisClient, redisPub, redisSub };
  } catch (error) {
    console.warn('⚠️  Redis connection failed:', error.message);
    console.warn('⚠️  Running without Redis - real-time features disabled');
    
    // Clean up failed connections
    if (redisClient) {
      redisClient.disconnect();
      redisClient = null;
    }
    if (redisPub) {
      redisPub.disconnect();
      redisPub = null;
    }
    if (redisSub) {
      redisSub.disconnect();
      redisSub = null;
    }
    
    return { redisClient: null, redisPub: null, redisSub: null };
  }
}

function getRedisClient() {
  return redisClient;
}

function getRedisPub() {
  return redisPub;
}

function getRedisSub() {
  return redisSub;
}

async function disconnectRedis() {
  try {
    if (redisClient) await redisClient.quit();
    if (redisPub) await redisPub.quit();
    if (redisSub) await redisSub.quit();
    console.log('✅ Redis disconnected');
  } catch (error) {
    console.error('❌ Redis disconnect error:', error.message);
  }
}

module.exports = {
  connectRedis,
  getRedisClient,
  getRedisPub,
  getRedisSub,
  disconnectRedis,
};