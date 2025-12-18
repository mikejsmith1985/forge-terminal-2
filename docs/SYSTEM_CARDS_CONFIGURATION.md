# System Cards Configuration Guide

Forge Terminal comes with **3 built-in system cards** that are automatically available to all projects:

1. **Release Manager** - Semantic versioning and automated release management
2. **Git Status** - Quick repository status check
3. **Build Project** - Project build automation

## Problem Solved ✅

Previously, only the **Release Manager** card was visible. Now **all 3 system cards are visible and configurable** based on your project needs.

## Why Configuration is Important

Different projects have different build and release requirements:

- **Node.js projects** use `npm build` or `yarn build`
- **Go projects** use `go build`
- **Python projects** use `pip install -e .` or `python setup.py build`
- **Monorepos** might need custom build chains
- **Release processes** vary by team and CI/CD setup

## Quick Start: Enable System Cards

By default, all 3 system cards are enabled and visible. No configuration needed!

```
┌─────────────────────────────────────┐
│ System Cards                        │
├─────────────────────────────────────┤
│ 🚀 Release Manager                  │
│ 📊 Git Status                       │
│ 🔨 Build Project                    │
└─────────────────────────────────────┘
```

## Project-Specific Configuration

To customize system cards for your project, create a `.forge-system-cards.json` file in your project root:

### For Node.js Projects

Copy this to your project root as `.forge-system-cards.json`:

```json
{
  "projectName": "My Node.js App",
  "gitStatus": {
    "enabled": true,
    "command": "git status --short"
  },
  "buildProject": {
    "enabled": true,
    "command": "npm run build",
    "preCommands": ["npm install"],
    "postCommands": ["npm run test"]
  },
  "releaseManager": {
    "enabled": true,
    "testCommand": "npm test",
    "runTests": true
  }
}
```

**See full example:** `docs/.forge-system-cards.example.nodejs.json`

### For Go Projects

```json
{
  "projectName": "My Go Service",
  "buildProject": {
    "enabled": true,
    "command": "go build -o ./bin/app",
    "preCommands": ["go mod tidy"]
  },
  "releaseManager": {
    "testCommand": "go test -v -race ./..."
  }
}
```

**See full example:** `docs/.forge-system-cards.example.go.json`

### For Python Projects

```json
{
  "projectName": "My Python App",
  "buildProject": {
    "enabled": true,
    "command": "python -m build"
  },
  "releaseManager": {
    "testCommand": "pytest -v --cov"
  }
}
```

**See full example:** `docs/.forge-system-cards.example.python.json`

## Configuration Options

### Git Status Card

```json
"gitStatus": {
  "enabled": true,           // Show this card
  "command": "git status",   // Command to execute
  "description": "..."       // Card description
}
```

### Build Project Card

```json
"buildProject": {
  "enabled": true,
  "command": "make build",
  "description": "Build the project",
  "preCommands": [],         // Run before build
  "postCommands": []         // Run after build
}
```

### Release Manager Card

```json
"releaseManager": {
  "enabled": true,
  "releaseStrategy": "semver",     // "semver", "calendar", or "custom"
  "releaseBranch": "main",         // Target branch
  "createTags": true,              // Create git tags
  "createGitHubRelease": true,     // Create GitHub releases
  "runTests": true,                // Run tests before release
  "testCommand": "make test"       // Test command
}
```

## Adding Custom System Cards

Add project-specific system cards to your configuration:

```json
{
  "customSystemCards": [
    {
      "id": "npm-start",
      "name": "Start Dev Server",
      "description": "Start development server",
      "command": "npm run dev",
      "colorTheme": "green",
      "category": "system"
    },
    {
      "id": "npm-lint",
      "name": "Lint Code",
      "description": "Run ESLint with auto-fix",
      "command": "npm run lint -- --fix",
      "colorTheme": "blue",
      "category": "system"
    }
  ]
}
```

### Color Themes

Available colors for custom cards: `blue`, `purple`, `orange`, `green`

## Disabling Cards

If you don't need a system card for your project, disable it:

```json
{
  "gitStatus": {
    "enabled": false
  }
}
```

## Migration from Defaults

If you just want to see what's available:

1. **All 3 system cards are visible by default**
2. **Click the ⚙️ settings icon** on any system card to configure it
3. **Create `.forge-system-cards.json`** in your project root for persistent configuration

## Feature Comparison

| Feature | Before | After |
|---------|--------|-------|
| System cards visible | ❌ Only Release Manager | ✅ All 3 cards |
| Git Status card | ❌ Hidden | ✅ Visible & executable |
| Build Project card | ❌ Hidden | ✅ Visible & executable |
| Project configuration | ❌ Not supported | ✅ Full support |
| Custom system cards | ❌ Not possible | ✅ Add unlimited cards |
| Release customization | ⚠️ Limited | ✅ Full control |

## Example Files

- `docs/.forge-system-cards.example.nodejs.json` - Node.js configuration
- `docs/.forge-system-cards.example.go.json` - Go configuration  
- `docs/.forge-system-cards.example.python.json` - Python configuration

## Troubleshooting

### System cards not visible
- Restart Forge Terminal
- Check that `isSystemCard: true` is set in card definition
- Verify no errors in browser console

### Configuration not loading
- Ensure `.forge-system-cards.json` is in project root (not in subdirectories)
- Check JSON syntax is valid
- Look at browser console for parsing errors

### Custom build command not working
- Test the command manually in terminal first
- Ensure the command is in PATH or use full path
- Add pre/post commands if needed for dependencies

## Next Steps

1. ✅ See all 3 system cards in your terminal
2. 📝 Copy example config for your project type
3. ⚙️ Customize for your specific build/release process
4. 🎯 Add custom system cards as needed
