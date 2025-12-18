# System Cards Quick Reference

## What You Get

**3 System Cards (all visible by default):**

```
┌────────────────────────────────────┐
│ 🚀 Release Manager                 │ Semantic versioning & releases
├────────────────────────────────────┤
│ 📊 Git Status                      │ Quick git repository check
├────────────────────────────────────┤
│ 🔨 Build Project                   │ Build automation
└────────────────────────────────────┘
```

## Quick Setup (1 Minute)

### To Use Defaults
**Just start using them!** No setup needed.

### To Customize for Your Project

**Step 1:** Copy example config for your project type

Node.js:
```bash
cp docs/.forge-system-cards.example.nodejs.json .forge-system-cards.json
```

Go:
```bash
cp docs/.forge-system-cards.example.go.json .forge-system-cards.json
```

Python:
```bash
cp docs/.forge-system-cards.example.python.json .forge-system-cards.json
```

**Step 2:** Edit `.forge-system-cards.json` with your commands

**Step 3:** Restart Forge Terminal - cards auto-update!

## Common Customizations

### Node.js Project
```json
{
  "buildProject": {
    "command": "npm run build",
    "preCommands": ["npm install"]
  },
  "releaseManager": {
    "testCommand": "npm test"
  }
}
```

### Go Project
```json
{
  "buildProject": {
    "command": "go build -o ./bin/app"
  },
  "releaseManager": {
    "testCommand": "go test ./..."
  }
}
```

### Python Project
```json
{
  "buildProject": {
    "command": "python -m build"
  },
  "releaseManager": {
    "testCommand": "pytest -v"
  }
}
```

## Card Features

### Each Card Has
- 📋 **Copy** button - Copy command to clipboard
- ▶️ **Execute** button - Run command immediately
- ⚙️ **Settings** button - Configure for your project

### Cards Support
- ✅ Execution in terminal
- ✅ Clipboard copy
- ✅ Configuration per-project
- ✅ Enable/disable per card
- ✅ Pre/post command chains

## Configuration File Location

Place `.forge-system-cards.json` in your **project root**:

```
my-project/
├── .forge-system-cards.json  ← Put it here
├── src/
├── package.json
└── README.md
```

## Disable a Card

```json
{
  "gitStatus": {
    "enabled": false
  }
}
```

## Add Custom System Cards

```json
{
  "customSystemCards": [
    {
      "id": "start-dev",
      "name": "Start Dev",
      "description": "Start development server",
      "command": "npm run dev",
      "colorTheme": "green"
    }
  ]
}
```

## Card Colors
- `blue` - 📊 Blue theme
- `purple` - 🔨 Purple theme
- `orange` - 🚀 Orange theme
- `green` - ✅ Green theme

## Examples

- **Full examples:** `docs/.forge-system-cards.example.*.json`
- **Full guide:** `docs/SYSTEM_CARDS_CONFIGURATION.md`

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Cards not visible | Restart Forge Terminal |
| Config not loading | Check JSON syntax, restart |
| Command not found | Test command manually first |
| Pre/post commands | Set proper PATH or use full path |

## What Changed

| Feature | Before | Now |
|---------|--------|-----|
| System cards visible | 1 of 3 | ✅ All 3 |
| Git Status | Hidden | ✅ Visible |
| Build Project | Hidden | ✅ Visible |
| Project config | ❌ No | ✅ Yes |
| Custom cards | ❌ No | ✅ Yes |

## Next: Project-Specific Release Strategy

Release Manager is fully configurable:

```json
{
  "releaseManager": {
    "releaseStrategy": "semver",        // semver, calendar, custom
    "releaseBranch": "main",            // Target branch
    "createTags": true,                 // Create git tags
    "createGitHubRelease": true,        // Create GitHub releases
    "runTests": true,                   // Run tests before
    "testCommand": "npm test"           // Test command
  }
}
```

Different projects = different release needs ✅

---

**Start now:** Copy `.forge-system-cards.example.*.json` to `.forge-system-cards.json` and customize!
