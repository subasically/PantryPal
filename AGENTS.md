# Repository Guidelines

## Project Structure & Module Organization
- `server/`: Node.js/Express API. Key areas: `server/src/app.js` (app factory), `server/src/routes/` (resource endpoints), `server/src/models/` (DB access), `server/src/services/` (external integrations), `server/db/schema.sql` (SQLite schema), `server/tests/` (Jest tests).
- `ios/`: SwiftUI app. Code lives in `ios/PantryPal/` with `Views/`, `ViewModels/`, `Services/`, `Models/`, and shared UI utilities in `Utils/`. Assets and audio are in `ios/PantryPal/Assets.xcassets/` and `ios/PantryPal/Resources/`.

## Build, Test, and Development Commands
```bash
cd server
docker compose up -d          # Run API in Docker (http://localhost:3002)
cp .env.example .env          # Configure JWT secret for local dev
npm install
npm run dev                   # Local API with hot reload (http://localhost:3000)
npm start                     # Local API without reload
npm test                      # Jest test suite
npm run test:watch            # Jest watch mode
npm run test:coverage         # Coverage report
```
- iOS: open `ios/PantryPal.xcodeproj` in Xcode and build/run on a simulator or device.

## Coding Style & Naming Conventions
- JavaScript (server): CommonJS modules, 4-space indentation, camelCase for variables/functions. Route files are resource-named (e.g., `inventory.js`, `grocery.js`).
- Swift (iOS): Swift 6 + SwiftUI, 4-space indentation. Types in UpperCamelCase, properties/functions in lowerCamelCase. Files usually match the main type name.
- No repo-wide formatter or linter is configured; follow existing patterns in nearby files.

## Testing Guidelines
- Frameworks: Jest + Supertest in `server/tests/`.
- Naming: `*.test.js` files per feature area (e.g., `inventory.test.js`).
- Run tests from `server/`. Use `npm run test:coverage` when changing API behavior or DB logic.

## Commit & Pull Request Guidelines
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`, `revert:`).
- PRs should include a clear summary, tests run, and linked issues. Add screenshots for UI changes and call out API/DB migrations when applicable.

## Configuration & Deployment Notes
- Local secrets live in `server/.env` (derived from `server/.env.example`). Do not commit secrets or local `.db` artifacts.
- Production and ops commands are documented in `DEPLOYMENT.md` and `SERVER_COMMANDS.md`.
- **Docker Network:** The production `docker-compose.yml` MUST include `networks: - web` under the service and `networks: web: external: true` at the root level. This connects the container to the external `web` network used by the reverse proxy (Traefik/nginx-proxy) for Cloudflare routing. Without this, the API returns 502 Bad Gateway errors.

## Testing & Debugging Workflow
- **Test Plan:** Follow structured test scenarios in `TESTING.md` (7 tests from free tier → premium → multi-device → offline).
- **Database Reset:** Use `./server/scripts/reset-database.sh` to reset production database on VPS. Script SSHs to server, stops containers, removes volumes, and recreates fresh database. Supports `--force` or `-f` flag to skip confirmation.
- **iOS Debug Tools:** Settings → Debug → Force Full Sync (clears sync cursor and pending actions).
- **Sync Debugging:** If items not syncing: (1) Check sync_log table for correct entity_id/action values, (2) Verify syncLogger parameter order matches call sites, (3) Use Force Full Sync to clear stuck cursor.
- **Common Patterns:**
  - Always create household before dismissing HouseholdSetupView (call `completeHouseholdSetup()`)
  - Sync issues often caused by parameter order mismatches in service functions
  - Test multi-device scenarios early to catch sync bugs (not visible in single-device dev)
  - Use console logs to trace sync flow: "Received X changes", "Applied X changes", "processed successfully"
