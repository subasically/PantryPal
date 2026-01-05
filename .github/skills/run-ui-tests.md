# Run UI Tests

Run PantryPal's UI test suite on simulator or device.

## When to Use
- User says "run tests", "run UI tests", "test the app"
- After making UI changes that need verification
- Before committing major features

## Steps

1. **Check if test server is running:**
   ```bash
   curl -s http://localhost:3002/health
   ```

2. **If not running, start test server:**
   ```bash
   ./scripts/start-test-server.sh
   ```

3. **Run tests on simulator (preferred):**
   ```bash
   cd ios && xcodebuild test -scheme PantryPal \
     -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
     -only-testing:PantryPalUITests \
     2>&1 | tee /tmp/ui-test-results.log | \
     grep -E "(Test case.*passed|Test case.*failed)" | tail -15
   ```

4. **Summarize results:**
   ```bash
   grep -E "Executed.*tests" /tmp/ui-test-results.log | tail -1
   ```

## Notes
- **Das iPhone (00008120-00104532210B401E) requires manual passcode** - use simulator instead
- Test server must be running on localhost:3002
- Tests take ~5-8 minutes total
- Expected pass rate: 36% (4/11 tests)
- **For comprehensive testing:** Follow `TESTING.md` test plan (7 scenarios)

## Troubleshooting
- "Connection refused" → Start test server
- "Build failed" → Check for compilation errors
- "Tests hanging" → Kill simulator and retry
- "Items not syncing" → See `.github/skills/debug-sync.md`
