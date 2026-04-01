# Vercel Deployment & Setup Guide

This guide will walk you through setting up your private Issue Tracker Sync Server using Vercel and Vercel KV (Redis). This setup is completely free under Vercel's Hobby tier.

## Prerequisites
1. You have pushed this codebase (including `index.html`, `api/`, `package.json`, and `vercel.json`) to a GitHub repository.
2. You have a free [Vercel account](https://vercel.com/signup) linked to your GitHub account.

---

## Step 1: Import the Project to Vercel
1. Go to your Vercel Dashboard and click **Add New** > **Project**.
2. Select the GitHub repository containing this codebase and click **Import**.
3. Leave all the default settings as they are (Vercel will automatically detect that there's no build step but will recognize the Serverless Functions in the `api/` directory).
4. Click **Deploy**. Vercel will create your project and assign it a domain (e.g., `https://issue-tracker.vercel.app`).

## Step 2: Set up the KV Database (Storage)
Because Vercel Serverless Functions are ephemeral (they reset after running), we need a database to store your `issues.json` blob permanently. We use Vercel KV for this.

1. Once your deployment finishes, click **Continue to Dashboard**.
2. Go to the **Storage** tab at the top of your project page.
3. Click **Create** and select **Redis**.
4. Read the prompt (Vercel uses Upstash Redis for KV storage behind the scenes), give it a name (e.g., `issue-tracker-db`), select a primary region close to you, and click **Create**.
5. Vercel will ask you to **Connect** this database to a project. Select your Issue Tracker project. 
*(This automatically adds the necessary `KV_REST_API_URL` and `KV_REST_API_TOKEN` environment variables to your project behind the scenes).*

## Step 3: Set up your secure API Key
To ensure no one else can read or write to your private Sync Server, we need to configure your secret key.

1. On your Vercel project dashboard, go to the **Settings** tab.
2. Click on **Environment Variables** in the left sidebar.
3. Add a new variable:
   - **Key**: `API_KEY`
   - **Value**: *(Type a secure, random password or long phrase. E.g., `super-secret-password-123`)*
4. Make sure all environments (Production, Preview, Development) are checked, and click **Save**.

## Step 4: Redeploy to apply changes
Environment variables only take effect on the *next* deployment.

1. Go to the **Deployments** tab.
2. Click the three dots (`...`) on your most recent deployment and select **Redeploy**.
3. Keep "Use existing Build Cache" checked and click **Redeploy**. Wait a few seconds for it to finish.

---

## Step 5: Connect your Frontend 🚀
You're done with the server! Now, just connect the web app to it.

1. Open your hosted `index.html` file in your browser (or open the live URL Vercel gave you).
2. Click **Connect to Sync Server** in the Settings panel.
3. Fill in the details:
   - **API URL**: `https://<your-vercel-domain>/api/sync` *(Make sure to add `/api/sync` exactly like that)*
   - **API KEY**: The exact password you provided in Step 3.
4. Click **Connect & Sync**.

If configured successfully, you will see a green **Connected!** toast, and your browser data is now securely syncing via your private API!
