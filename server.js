require('dotenv').config();

const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Configuration - Update these for production
const DIFY_API_KEY = process.env.DIFY_API_KEY || 'app-Z3TEMkZSNuUjvltxnIgfhC2l';
const DIFY_API_URL = process.env.DIFY_API_URL || 'http://44.255.35.142/v1';

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('.'));

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', message: 'Cyberdelias backend is running' });
});

// Chat proxy endpoint
app.post('/api/chat', async (req, res) => {
  try {
    const { message, conversationId } = req.body;

    if (!message) {
      return res.status(400).json({ error: 'Message is required' });
    }

    // Generate a unique user ID for this session
    const userId = req.headers['x-user-id'] || 'ctf-user-' + Math.random().toString(36).substring(7);

    // Forward request to Dify
    const response = await fetch(`${DIFY_API_URL}/chat-messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${DIFY_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        inputs: {},
        query: message,
        response_mode: 'blocking',
        conversation_id: conversationId || '',
        user: userId
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('Dify API error:', response.status, errorText);
      return res.status(response.status).json({
        error: 'Failed to communicate with Delia',
        details: errorText
      });
    }

    const data = await response.json();

    // Return only necessary data to frontend
    res.json({
      answer: data.answer || data.message || 'No response received',
      conversationId: data.conversation_id
    });

  } catch (error) {
    console.error('Server error:', error);
    res.status(500).json({
      error: 'Internal server error',
      message: error.message
    });
  }
});

// Serve the HTML file
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'cyberdelia.html'));
});

// Start server
app.listen(PORT, () => {
  console.log(`Cyberdelias server running on port ${PORT}`);
  console.log(`Dify API: ${DIFY_API_URL}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});
