# Architectural Decisions

## 1. Blob Sync vs Granular CRUD for Database Storage

**Date:** March 31, 2026

**Context:** 
We were tasked with replacing a GitHub JSON sync feature with a generic backend API (such as Vercel) while maintaining strong offline capabilities and the simplicity of a single-file application. The user requested "simple database storage with CRUD operations" but explicitly noted "The backend should be for syncing between browsers only."

**Decision:** 
We opted to replace the GitHub sync with a **full JSON payload (blob) sync API** rather than granular per-issue CRUD endpoints.

**Rationale:**
1. **Offline Robustness:** The entire state of this application is already built around leveraging `localStorage` as a single blob. For offline-first architectures, it is significantly less complex to persist changes locally, then optimistically sync the entire updated state at the backend when the internet connection is restored. A granular REST backend would require building an offline event queue (to log exactly which fields changed, and which ones were deleted while disconnected).
2. **Performance Considerations:** For personal or small team use cases, modern browsers and servers automatically gzip compress JSON endpoints. A large tracker (~5MB) parses in milliseconds and transfers in under a second. Furthermore, switching from GitHub (which requires Base64 encoding overhead) to a native API results in a net structural performance gain compared to the previous process.
3. **Simplicity:** Keeping the backend logic to two extremely simple endpoint methods (`GET` and `POST`) minimizes API surface area and eliminates the need for expensive multi-indexed relational databases, pairing nicely with serverless key-value stores like Vercel KV.
