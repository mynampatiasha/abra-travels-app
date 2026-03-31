/**
 * Null Safety Utilities for Abra Fleet Backend
 * Provides safe operations to prevent null/undefined errors
 */

/**
 * Safely get nested object property
 * @param {Object} obj - The object to traverse
 * @param {string} path - Dot notation path (e.g., 'user.profile.name')
 * @param {*} defaultValue - Default value if path doesn't exist
 * @returns {*} The value at path or defaultValue
 */
function safeGet(obj, path, defaultValue = null) {
  if (!obj || typeof obj !== 'object') return defaultValue;
  
  const keys = path.split('.');
  let current = obj;
  
  for (const key of keys) {
    if (current === null || current === undefined || !(key in current)) {
      return defaultValue;
    }
    current = current[key];
  }
  
  return current;
}

/**
 * Safely parse JSON string
 * @param {string} jsonString - JSON string to parse
 * @param {*} defaultValue - Default value if parsing fails
 * @returns {*} Parsed object or defaultValue
 */
function safeJsonParse(jsonString, defaultValue = null) {
  if (!jsonString || typeof jsonString !== 'string') return defaultValue;
  
  try {
    return JSON.parse(jsonString);
  } catch (error) {
    console.warn('JSON parse failed:', error.message);
    return defaultValue;
  }
}

/**
 * Safely convert to string
 * @param {*} value - Value to convert
 * @param {string} defaultValue - Default if conversion fails
 * @returns {string} String representation or defaultValue
 */
function safeString(value, defaultValue = '') {
  if (value === null || value === undefined) return defaultValue;
  if (typeof value === 'string') return value;
  
  try {
    return String(value);
  } catch (error) {
    return defaultValue;
  }
}

/**
 * Safely convert to number
 * @param {*} value - Value to convert
 * @param {number} defaultValue - Default if conversion fails
 * @returns {number} Number or defaultValue
 */
function safeNumber(value, defaultValue = 0) {
  if (value === null || value === undefined || value === '') return defaultValue;
  
  const num = Number(value);
  return isNaN(num) ? defaultValue : num;
}

/**
 * Safely convert to boolean
 * @param {*} value - Value to convert
 * @param {boolean} defaultValue - Default if conversion fails
 * @returns {boolean} Boolean or defaultValue
 */
function safeBoolean(value, defaultValue = false) {
  if (value === null || value === undefined) return defaultValue;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const lower = value.toLowerCase();
    if (lower === 'true' || lower === '1' || lower === 'yes') return true;
    if (lower === 'false' || lower === '0' || lower === 'no') return false;
  }
  if (typeof value === 'number') return value !== 0;
  
  return defaultValue;
}

/**
 * Safely get array from value
 * @param {*} value - Value to convert to array
 * @param {Array} defaultValue - Default array if conversion fails
 * @returns {Array} Array or defaultValue
 */
function safeArray(value, defaultValue = []) {
  if (Array.isArray(value)) return value;
  if (value === null || value === undefined) return defaultValue;
  
  // Try to convert single value to array
  try {
    return [value];
  } catch (error) {
    return defaultValue;
  }
}

/**
 * Safely filter null/undefined values from object
 * @param {Object} obj - Object to filter
 * @returns {Object} Filtered object
 */
function filterNulls(obj) {
  if (!obj || typeof obj !== 'object') return {};
  
  const filtered = {};
  for (const [key, value] of Object.entries(obj)) {
    if (value !== null && value !== undefined && value !== '') {
      filtered[key] = value;
    }
  }
  return filtered;
}

/**
 * Safely create MongoDB query with null filtering
 * @param {Object} conditions - Query conditions
 * @returns {Object} Safe MongoDB query
 */
function safeMongoQuery(conditions) {
  if (!conditions || typeof conditions !== 'object') return {};
  
  const query = {};
  for (const [key, value] of Object.entries(conditions)) {
    if (value !== null && value !== undefined && value !== '') {
      // Handle special MongoDB operators
      if (key.startsWith('$')) {
        query[key] = value;
      } else {
        query[key] = value;
      }
    }
  }
  return query;
}

/**
 * Safely handle async operations with error catching
 * @param {Function} asyncFn - Async function to execute
 * @param {*} defaultValue - Default value on error
 * @returns {Promise} Promise that resolves to result or defaultValue
 */
async function safeAsync(asyncFn, defaultValue = null) {
  try {
    return await asyncFn();
  } catch (error) {
    console.error('Async operation failed:', error.message);
    return defaultValue;
  }
}

/**
 * Validate required fields in request body
 * @param {Object} body - Request body
 * @param {Array} requiredFields - Array of required field names
 * @returns {Object} Validation result { isValid, missing, errors }
 */
function validateRequired(body, requiredFields) {
  const missing = [];
  const errors = [];
  
  if (!body || typeof body !== 'object') {
    return {
      isValid: false,
      missing: requiredFields,
      errors: ['Request body is required']
    };
  }
  
  for (const field of requiredFields) {
    const value = safeGet(body, field);
    if (value === null || value === undefined || value === '') {
      missing.push(field);
      errors.push(`Field '${field}' is required`);
    }
  }
  
  return {
    isValid: missing.length === 0,
    missing,
    errors
  };
}

/**
 * Create safe response object
 * @param {boolean} success - Success status
 * @param {*} data - Response data
 * @param {string} message - Response message
 * @param {*} error - Error information
 * @returns {Object} Safe response object
 */
function safeResponse(success = true, data = null, message = '', error = null) {
  const response = {
    success: safeBoolean(success),
    timestamp: new Date().toISOString()
  };
  
  if (data !== null && data !== undefined) {
    response.data = data;
  }
  
  if (message && typeof message === 'string') {
    response.message = message;
  }
  
  if (!success && error) {
    response.error = safeString(error);
  }
  
  return response;
}

module.exports = {
  safeGet,
  safeJsonParse,
  safeString,
  safeNumber,
  safeBoolean,
  safeArray,
  filterNulls,
  safeMongoQuery,
  safeAsync,
  validateRequired,
  safeResponse
};