# Feature Roadmap — Mobile Client Parity

Based on Google Drive comparison analysis (2026-03-18). Prioritized for enterprise B2B, not consumer.

## Sprint 1: Quick Wins (1 week)

1. **Star/Favorite files** (S)
   - Add `is_starred` boolean to FileItem entity
   - `PATCH /api/files/{id}/star` toggle endpoint
   - Filter starred files in file browser (both clients)
   - Starred section in home/recent view (Sprint 3)

2. **File rename** (S)
   - Verify `PATCH /api/files/{id}` supports name change
   - Wire up rename UI in iOS (context menu) and Android (long press)

3. **File move to folder** (S)
   - Verify `PATCH /api/files/{id}` supports folder_id change
   - Add folder picker UI in both clients

4. **Storage quota display** (S)
   - Show tenant quota usage in Settings
   - Backend: `GET /api/me` already returns quota info (verify)
   - Progress bar: used / total with percentage

## Sprint 2: Core (2 weeks)

5. **Trash / Soft delete** (M)
   - Add `deleted_at` nullable timestamp to FileItem + Folder
   - Existing delete endpoints set `deleted_at` instead of hard delete
   - `GET /api/files/trash` — list trashed items
   - `POST /api/files/{id}/restore` — restore from trash
   - `DELETE /api/files/{id}/permanent` — permanent delete
   - Background job: purge items older than 30 days
   - Trash view in both clients (accessible from More/Settings)

6. **Global search** (M)
   - `GET /api/files/search?q=name&type=pdf&from=2026-01-01&to=2026-03-18`
   - Search across all user's files and folders by name
   - Filters: file type, date range, folder
   - Search bar at top of file browser (replaces in-folder search)
   - Recent searches (local storage)

## Sprint 3: Polish (2 weeks)

7. **Home / Recent files screen** (M)
   - New tab or replace file browser as landing screen
   - Sections: Recent files, Starred, Shared with me (preview)
   - Quick actions: Upload, Create folder, Scan (camera)
   - `GET /api/files/recent?limit=20` endpoint

8. **Offline file access** (L)
   - "Make available offline" toggle per file
   - Download + decrypt to local encrypted cache
   - Offline indicator (cloud icon with checkmark)
   - Sync changes on reconnect
   - Clear offline cache on tenant switch (already handled)
   - Storage management: show offline cache size in Settings

## Sprint 4: Enterprise (3 weeks)

9. **Version history** (L)
   - Store previous versions on each upload (same file ID, new version)
   - `GET /api/files/{id}/versions` — list versions with timestamps
   - `POST /api/files/{id}/versions/{versionId}/restore` — restore to version
   - Version diff not needed (binary files) — just restore
   - Retention policy: keep N versions or M days (configurable per tenant)

## Explicitly Skipped

| Feature | Reason |
|---------|--------|
| Document scanner | Use native OS scanner + upload |
| File comments | Out of scope — storage platform, not collaboration |
| Public share links | Conflicts with E2E encryption model |
| Content search | Zero-knowledge — server can't read file contents |
| AI file summaries | Files are encrypted — server can't summarize |
| Transfer ownership | Rare; admin portal can handle |
| Commenter permission | Read/Write sufficient; no comments feature |

## SSDID Drive Advantages (keep investing)

- E2E encryption (zero-knowledge)
- Post-quantum cryptography (KAZ-KEM + ML-KEM)
- DID-based authentication (no passwords)
- PII-protected AI chat
- Shamir secret sharing key recovery
- Multi-tenant with full isolation on switch
- Verifiable Credentials (W3C)
