# Add Accessibility Identifier

Add accessibility IDs to SwiftUI views for UI testing.

## When to Use
- User says "add accessibility ID for X", "make X testable"
- When creating new UI elements
- When UI tests can't find elements

## Process

### Step 1: Identify the Element
Ask user:
- What view/screen is this in?
- What type of element? (Button, TextField, List, etc.)
- What's the element's purpose?

### Step 2: Choose ID Format
Use consistent naming pattern:
```
<screen>.<elementType><OptionalName>
```

Examples:
- `login.emailField`
- `login.loginButton`
- `inventory.addButton`
- `grocery.list`
- `settings.signOutButton`

### Step 3: Add to SwiftUI View
```swift
// For Buttons
Button("Sign Out") {
    // action
}
.accessibilityIdentifier("settings.signOutButton")

// For TextFields
TextField("Email", text: $email)
    .accessibilityIdentifier("login.emailField")

// For Lists
List {
    // content
}
.accessibilityIdentifier("inventory.list")

// For Views/Containers
VStack {
    // content
}
.accessibilityIdentifier("checkout.tabButton")
```

### Step 4: Verify in Test
Add to test file:
```swift
let element = app.buttons["settings.signOutButton"]
XCTAssertTrue(element.waitForExistence(timeout: 3), "Sign out button should exist")
```

### Step 5: Test It
Run the specific test to verify:
```bash
cd ios && xcodebuild test -scheme PantryPal \
  -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
  -only-testing:PantryPalUITests/PantryPalUITests/testXX \
  2>&1 | grep -E "(passed|failed)"
```

## Common Element Types

### Button
```swift
Button("Label") { }
    .accessibilityIdentifier("screen.actionButton")
```

### TextField
```swift
TextField("Placeholder", text: $value)
    .accessibilityIdentifier("screen.inputField")
```

### SecureField
```swift
SecureField("Password", text: $password)
    .accessibilityIdentifier("screen.passwordField")
```

### List
```swift
List { }
    .accessibilityIdentifier("screen.list")
```

### NavigationLink
```swift
NavigationLink("Settings") { }
    .accessibilityIdentifier("screen.settingsLink")
```

### TabView Item
```swift
.tabItem { Label("Home", systemImage: "house") }
.accessibilityIdentifier("tab.home")
```

### Toggle
```swift
Toggle("Enable", isOn: $enabled)
    .accessibilityIdentifier("settings.enableToggle")
```

## Existing IDs in PantryPal

### Login Screen
- `login.continueWithEmailButton`
- `login.emailField`
- `login.passwordField`
- `login.loginButton`

### Inventory Screen
- `inventory.list`
- `inventory.addButton`
- `inventory.scanButton`

### Grocery Screen
- `grocery.list`
- `grocery.addButton`

### Checkout Screen
- `checkout.tabButton`

### Settings Screen
- `settings.button` (person icon)
- `settings.signOutButton`

### Main Tab Container
- `mainTab.container`

### Onboarding
- `onboarding.skipButton`

## Pro Tips
- Use string literals for IDs (don't use enums)
- Keep IDs short but descriptive
- Use consistent naming across the app
- Document new IDs in this skill file
- Test immediately after adding ID
- Add modifier AFTER other view modifiers
- IDs are case-sensitive

## Example Session
```
User: "Make the delete button in grocery list testable"

You:
1. Found button in GroceryListView.swift line 45
2. Adding ID "grocery.deleteButton"
3. Code:
   Button("Delete") { }
       .accessibilityIdentifier("grocery.deleteButton")
4. Committed changes
5. Ready for testing!
```
