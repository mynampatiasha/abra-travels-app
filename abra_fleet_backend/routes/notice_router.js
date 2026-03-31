// ============================================================================
// FILE: backend/routes/notice_router.js
// NOTICE BOARD SYSTEM - BACKEND API ROUTES
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

module.exports = (db) => {
  const noticesCollection = db.collection('notices');
  const usersCollection = db.collection('users');

  // =========================================================================
  // 1. GET ALL NOTICES (with pagination and filtering)
  // =========================================================================
  router.get('/', async (req, res) => {
    try {
      const { 
        page = 1, 
        limit = 10, 
        category = 'all', 
        priority = 'all',
        search = ''
      } = req.query;

      const skip = (parseInt(page) - 1) * parseInt(limit);
      
      // Build query
      const query = {};
      
      if (category !== 'all') {
        query.category = category;
      }
      
      if (priority !== 'all') {
        query.priority = priority;
      }
      
      if (search) {
        query.$or = [
          { title: { $regex: search, $options: 'i' } },
          { content: { $regex: search, $options: 'i' } }
        ];
      }

      // Get notices with pagination
      const notices = await noticesCollection
        .find(query)
        .sort({ publishedDate: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .toArray();

      // Get total count for pagination
      const totalCount = await noticesCollection.countDocuments(query);
      const totalPages = Math.ceil(totalCount / parseInt(limit));

      console.log(`✅ Retrieved ${notices.length} notices (page ${page}/${totalPages})`);

      res.json({
        success: true,
        data: notices,
        pagination: {
          currentPage: parseInt(page),
          totalPages,
          totalCount,
          hasNext: parseInt(page) < totalPages,
          hasPrev: parseInt(page) > 1
        }
      });

    } catch (error) {
      console.error('❌ Error fetching notices:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 2. GET SINGLE NOTICE BY ID
  // =========================================================================
  router.get('/:id', async (req, res) => {
    try {
      const { id } = req.params;

      if (!ObjectId.isValid(id)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid notice ID format',
        });
      }

      const notice = await noticesCollection.findOne({ 
        _id: new ObjectId(id) 
      });

      if (!notice) {
        return res.status(404).json({
          success: false,
          message: 'Notice not found',
        });
      }

      console.log(`✅ Retrieved notice: ${notice.title}`);

      res.json({
        success: true,
        data: notice,
      });

    } catch (error) {
      console.error('❌ Error fetching notice:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 3. CREATE NEW NOTICE
  // =========================================================================
  router.post('/', async (req, res) => {
    try {
      const { 
        title, 
        content, 
        category = 'General', 
        priority = 'medium',
        publishedBy,
        publishedByName 
      } = req.body;

      // Validation
      if (!title || !content) {
        return res.status(400).json({
          success: false,
          message: 'Title and content are required',
        });
      }

      if (!publishedBy) {
        return res.status(400).json({
          success: false,
          message: 'Publisher information is required',
        });
      }

      // Validate priority
      const validPriorities = ['low', 'medium', 'high'];
      if (!validPriorities.includes(priority)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid priority. Must be: low, medium, or high',
        });
      }

      // Get publisher info if not provided
      let publisherName = publishedByName;
      if (!publisherName) {
        try {
          const publisher = await usersCollection.findOne({ 
            _id: ObjectId.isValid(publishedBy) ? new ObjectId(publishedBy) : publishedBy 
          });
          publisherName = publisher?.name || 'Admin';
        } catch (e) {
          publisherName = 'Admin';
        }
      }

      const now = new Date();
      const notice = {
        title: title.trim(),
        content: content.trim(),
        category: category.trim(),
        priority,
        publishedBy,
        publishedByName: publisherName,
        publishedDate: now,
        createdAt: now,
        updatedAt: now,
        isActive: true,
        viewCount: 0,
        tags: [], // For future use
      };

      const result = await noticesCollection.insertOne(notice);
      notice._id = result.insertedId;

      console.log(`✅ Notice created: ${title} by ${publisherName}`);

      res.status(201).json({
        success: true,
        message: 'Notice created successfully',
        data: notice,
      });

    } catch (error) {
      console.error('❌ Error creating notice:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 4. UPDATE NOTICE
  // =========================================================================
  router.put('/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const { 
        title, 
        content, 
        category, 
        priority,
        isActive 
      } = req.body;

      if (!ObjectId.isValid(id)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid notice ID format',
        });
      }

      // Build update object
      const updateData = {
        updatedAt: new Date(),
      };

      if (title) updateData.title = title.trim();
      if (content) updateData.content = content.trim();
      if (category) updateData.category = category.trim();
      if (priority) {
        const validPriorities = ['low', 'medium', 'high'];
        if (!validPriorities.includes(priority)) {
          return res.status(400).json({
            success: false,
            message: 'Invalid priority. Must be: low, medium, or high',
          });
        }
        updateData.priority = priority;
      }
      if (typeof isActive === 'boolean') updateData.isActive = isActive;

      const result = await noticesCollection.updateOne(
        { _id: new ObjectId(id) },
        { $set: updateData }
      );

      if (result.matchedCount === 0) {
        return res.status(404).json({
          success: false,
          message: 'Notice not found',
        });
      }

      // Get updated notice
      const updatedNotice = await noticesCollection.findOne({ 
        _id: new ObjectId(id) 
      });

      console.log(`✅ Notice updated: ${updatedNotice.title}`);

      res.json({
        success: true,
        message: 'Notice updated successfully',
        data: updatedNotice,
      });

    } catch (error) {
      console.error('❌ Error updating notice:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 5. DELETE NOTICE
  // =========================================================================
  router.delete('/:id', async (req, res) => {
    try {
      const { id } = req.params;

      if (!ObjectId.isValid(id)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid notice ID format',
        });
      }

      const result = await noticesCollection.deleteOne({ 
        _id: new ObjectId(id) 
      });

      if (result.deletedCount === 0) {
        return res.status(404).json({
          success: false,
          message: 'Notice not found',
        });
      }

      console.log(`✅ Notice deleted: ${id}`);

      res.json({
        success: true,
        message: 'Notice deleted successfully',
      });

    } catch (error) {
      console.error('❌ Error deleting notice:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 6. INCREMENT VIEW COUNT
  // =========================================================================
  router.post('/:id/view', async (req, res) => {
    try {
      const { id } = req.params;

      if (!ObjectId.isValid(id)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid notice ID format',
        });
      }

      await noticesCollection.updateOne(
        { _id: new ObjectId(id) },
        { $inc: { viewCount: 1 } }
      );

      res.json({
        success: true,
        message: 'View count updated',
      });

    } catch (error) {
      console.error('❌ Error updating view count:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 7. GET NOTICE CATEGORIES
  // =========================================================================
  router.get('/meta/categories', async (req, res) => {
    try {
      const categories = await noticesCollection.distinct('category');
      
      res.json({
        success: true,
        data: categories.sort(),
      });

    } catch (error) {
      console.error('❌ Error fetching categories:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  // =========================================================================
  // 8. GET NOTICE STATISTICS
  // =========================================================================
  router.get('/meta/stats', async (req, res) => {
    try {
      const totalNotices = await noticesCollection.countDocuments();
      const activeNotices = await noticesCollection.countDocuments({ isActive: true });
      
      const priorityStats = await noticesCollection.aggregate([
        { $group: { _id: '$priority', count: { $sum: 1 } } }
      ]).toArray();

      const categoryStats = await noticesCollection.aggregate([
        { $group: { _id: '$category', count: { $sum: 1 } } }
      ]).toArray();

      const recentNotices = await noticesCollection
        .find({ isActive: true })
        .sort({ publishedDate: -1 })
        .limit(5)
        .toArray();

      res.json({
        success: true,
        data: {
          totalNotices,
          activeNotices,
          inactiveNotices: totalNotices - activeNotices,
          priorityBreakdown: priorityStats,
          categoryBreakdown: categoryStats,
          recentNotices,
        },
      });

    } catch (error) {
      console.error('❌ Error fetching notice stats:', error);
      res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  });

  return router;
};

// ============================================================================
// HOW TO USE IN server.js:
// ============================================================================
// const noticeRouter = require('./routes/notice_router');
// app.use('/api/notices', verifyToken, noticeRouter(db));
// ============================================================================