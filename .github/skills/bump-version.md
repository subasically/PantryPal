# Bump Version and Build

Increment app version and build number for App Store submission.

## When to Use
- User says "bump version", "bump build", "prepare for release"
- Before TestFlight upload
- Before App Store submission

## Process

1. **Read current version/build:**
   ```bash
   grep -A1 "MARKETING_VERSION = " ios/PantryPal.xcodeproj/project.pbxproj | head -2
   grep -A1 "CURRENT_PROJECT_VERSION = " ios/PantryPal.xcodeproj/project.pbxproj | head -2
   ```

2. **Generate new build number (timestamp format):**
   ```bash
   date +"%Y%m%d%H%M%S"
   # Example: 20251231182145
   ```

3. **Ask user for version bump type:**
   - **Patch:** 1.0.0 → 1.0.1 (bug fixes)
   - **Minor:** 1.0.0 → 1.1.0 (new features)
   - **Major:** 1.0.0 → 2.0.0 (breaking changes)

4. **Update project.pbxproj:**
   ```bash
   # Update MARKETING_VERSION
   sed -i '' 's/MARKETING_VERSION = [0-9.]*/MARKETING_VERSION = NEW_VERSION/g' ios/PantryPal.xcodeproj/project.pbxproj
   
   # Update CURRENT_PROJECT_VERSION
   sed -i '' 's/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = NEW_BUILD/g' ios/PantryPal.xcodeproj/project.pbxproj
   ```

5. **Verify changes:**
   ```bash
   grep "MARKETING_VERSION = " ios/PantryPal.xcodeproj/project.pbxproj | head -1
   grep "CURRENT_PROJECT_VERSION = " ios/PantryPal.xcodeproj/project.pbxproj | head -1
   ```

6. **Commit and tag:**
   ```bash
   git add ios/PantryPal.xcodeproj/project.pbxproj
   git commit -m "chore: Bump version to X.Y.Z (BUILD)"
   git tag -a "vX.Y.Z-BUILD" -m "Release vX.Y.Z (BUILD)"
   git push origin main --tags
   ```

## Version Format
- **MARKETING_VERSION:** `X.Y.Z` (e.g., `1.0.0`)
  - X = Major (breaking changes)
  - Y = Minor (new features)
  - Z = Patch (bug fixes)
- **CURRENT_PROJECT_VERSION:** `YYYYMMDDHHmmss` (e.g., `20251231182145`)

## Tag Format
- `vX.Y.Z-BUILD` (e.g., `v1.0.0-20251231182145`)

## Example Session
```
User: "Bump version and build"

You:
1. Current version: 1.0.0 (20251230120000)
2. What type of release?
   - Patch (1.0.1) - bug fixes only
   - Minor (1.1.0) - new features
   - Major (2.0.0) - breaking changes

User: "Patch"

You:
3. New version: 1.0.1
4. New build: 20251231182145
5. Updating project.pbxproj...
6. Committing and tagging...
7. Done! ✅
```

## Notes
- Build number is always a timestamp for uniqueness
- Tags help track releases in git history
- Always verify changes before pushing
