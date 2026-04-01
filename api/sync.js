import { kv } from '@vercel/kv';

export default async function handler(req, res) {
  // Broad CORS Headers for browser syncing
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Expect Bearer token from settings (defaults to 'default-secret-key' if not set in Vercel ENV)
  const authHeader = req.headers.authorization;
  const expectedKey = process.env.API_KEY || 'default-secret-key';

  if (!authHeader || authHeader !== `Bearer ${expectedKey}`) {
    return res.status(401).json({ error: 'Unauthorized. Invalid API Key.' });
  }

  const KV_KEY = 'issue_tracker_production_data';

  try {
    if (req.method === 'GET') {
      const storedData = await kv.get(KV_KEY);

      if (!storedData) {
        // Return structured default if nothing exists yet
        return res.status(200).json({
          content: null,
          sha: '' // empty sha signals new initialization
        });
      }

      return res.status(200).json(storedData);
    }

    if (req.method === 'POST' || req.method === 'PUT') {
      const { content, sha: clientSha } = req.body;

      if (!content) {
        return res.status(400).json({ error: 'Missing content payload. Sync aborted.' });
      }

      const existingData = await kv.get(KV_KEY);

      // Conflict Check: 
      // If remote has a SHA and client is either missing it or it doesn't match
      if (existingData && existingData.sha) {
        if (!clientSha || clientSha !== existingData.sha) {
          return res.status(409).json({ 
            error: 'Conflict: Remote has a newer version.',
            remoteSHA: existingData.sha
          });
        }
      }

      // Valid push: generate new version SHA and save
      const newSha = Date.now().toString(36) + '-' + Math.random().toString(36).substring(2, 6);
      
      const payloadToSave = {
        content: content,
        sha: newSha,
        updatedAt: new Date().toISOString()
      };

      await kv.set(KV_KEY, payloadToSave);
      
      return res.status(200).json({ success: true, sha: newSha });
    }

    return res.status(405).json({ error: 'Method not allowed' });
  } catch (error) {
    console.error('API Error:', error);
    return res.status(500).json({ error: 'Internal server error', details: error.message });
  }
}
