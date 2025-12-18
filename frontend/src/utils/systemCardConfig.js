/**
 * Project-specific system card configuration
 *
 * This file allows customization of system cards based on project needs.
 * Each project can have different build commands, release processes, etc.
 *
 * Usage:
 * 1. Copy this file to your project root as `.forge-system-cards.json`
 * 2. Customize the commands and settings for your project
 * 3. The system will automatically load and apply these configurations
 */

export const SYSTEM_CARD_CONFIG_SCHEMA = {
  $schema: 'http://json-schema.org/draft-07/schema#',
  type: 'object',
  description: 'Project-specific system card configurations',
  properties: {
    projectName: {
      type: 'string',
      description: 'Name of your project',
      default: 'My Project',
    },
    gitStatus: {
      type: 'object',
      description: 'Git Status card configuration',
      properties: {
        enabled: { type: 'boolean', default: true },
        command: {
          type: 'string',
          description: 'Custom git status command',
          default: 'git status',
        },
        description: {
          type: 'string',
          description: 'Custom description',
          default: 'Quick check of git repository status',
        },
      },
    },
    buildProject: {
      type: 'object',
      description: 'Build Project card configuration',
      properties: {
        enabled: { type: 'boolean', default: true },
        command: {
          type: 'string',
          description: 'Custom build command',
          default: 'make build',
        },
        description: {
          type: 'string',
          description: 'Custom description',
          default: 'Build the project (frontend + backend)',
        },
        preCommands: {
          type: 'array',
          description: 'Commands to run before build',
          items: { type: 'string' },
          default: [],
        },
        postCommands: {
          type: 'array',
          description: 'Commands to run after build',
          items: { type: 'string' },
          default: [],
        },
      },
    },
    releaseManager: {
      type: 'object',
      description: 'Release Manager card configuration',
      properties: {
        enabled: { type: 'boolean', default: true },
        releaseStrategy: {
          type: 'string',
          enum: ['semver', 'calendar', 'custom'],
          description: 'Versioning strategy',
          default: 'semver',
        },
        releaseBranch: {
          type: 'string',
          description: 'Branch to push releases to',
          default: 'main',
        },
        createTags: { type: 'boolean', default: true },
        createGitHubRelease: { type: 'boolean', default: true },
        runTests: {
          type: 'boolean',
          description: 'Run tests before release',
          default: true,
        },
        testCommand: {
          type: 'string',
          description: 'Test command to run',
          default: 'make test',
        },
      },
    },
    customSystemCards: {
      type: 'array',
      description: 'Additional custom system cards for your project',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          name: { type: 'string' },
          description: { type: 'string' },
          command: { type: 'string' },
          colorTheme: {
            type: 'string',
            enum: ['blue', 'purple', 'orange', 'green'],
          },
          category: { type: 'string' },
        },
        required: ['id', 'name', 'command'],
      },
      default: [],
    },
  },
};

/**
 * Example configuration for a Node.js project
 */
export const EXAMPLE_CONFIG_NODE = {
  projectName: 'My Node.js App',
  gitStatus: {
    enabled: true,
    command: 'git status --short',
  },
  buildProject: {
    enabled: true,
    command: 'npm run build',
    preCommands: ['npm install'],
    postCommands: ['npm run test'],
  },
  releaseManager: {
    enabled: true,
    releaseStrategy: 'semver',
    testCommand: 'npm test',
    runTests: true,
  },
  customSystemCards: [
    {
      id: 'npm-start',
      name: 'Start Dev Server',
      description: 'Start the development server',
      command: 'npm run dev',
      colorTheme: 'green',
      category: 'system',
    },
  ],
};

/**
 * Example configuration for a Go project
 */
export const EXAMPLE_CONFIG_GO = {
  projectName: 'My Go Service',
  gitStatus: {
    enabled: true,
    command: 'git status --short',
  },
  buildProject: {
    enabled: true,
    command: 'go build -o app',
    preCommands: ['go mod tidy'],
    postCommands: ['./app --version'],
  },
  releaseManager: {
    enabled: true,
    releaseStrategy: 'semver',
    testCommand: 'go test ./...',
    runTests: true,
  },
  customSystemCards: [
    {
      id: 'go-test',
      name: 'Run Tests',
      description: 'Run Go tests with coverage',
      command: 'go test -v -cover ./...',
      colorTheme: 'blue',
      category: 'system',
    },
  ],
};

/**
 * Example configuration for a Python project
 */
export const EXAMPLE_CONFIG_PYTHON = {
  projectName: 'My Python App',
  gitStatus: {
    enabled: true,
    command: 'git status --short',
  },
  buildProject: {
    enabled: true,
    command: 'pip install -e . && python setup.py build',
    preCommands: ['python -m venv venv', 'source venv/bin/activate'],
    postCommands: ['pytest'],
  },
  releaseManager: {
    enabled: true,
    releaseStrategy: 'semver',
    testCommand: 'pytest -v',
    runTests: true,
  },
  customSystemCards: [
    {
      id: 'python-lint',
      name: 'Lint Code',
      description: 'Run pylint on the project',
      command: 'pylint src/',
      colorTheme: 'purple',
      category: 'system',
    },
  ],
};

/**
 * Load system card configuration from file
 * @returns {object} Merged configuration with defaults
 */
export async function loadSystemCardConfig() {
  try {
    const response = await fetch('/.forge-system-cards.json');
    if (response.ok) {
      const config = await response.json();
      return {
        ...getDefaultConfig(),
        ...config,
      };
    }
  } catch (err) {
    console.debug('No custom system card config found, using defaults');
  }
  return getDefaultConfig();
}

/**
 * Get default system card configuration
 */
export function getDefaultConfig() {
  return {
    projectName: 'Default Project',
    gitStatus: {
      enabled: true,
      command: 'git status',
      description: 'Quick check of git repository status',
    },
    buildProject: {
      enabled: true,
      command: 'make build',
      description: 'Build the project (frontend + backend)',
      preCommands: [],
      postCommands: [],
    },
    releaseManager: {
      enabled: true,
      releaseStrategy: 'semver',
      releaseBranch: 'main',
      createTags: true,
      createGitHubRelease: true,
      runTests: false,
      testCommand: 'make test',
    },
    customSystemCards: [],
  };
}

/**
 * Apply configuration to system cards
 * @param {array} systemCards - Default system cards
 * @param {object} config - Configuration object
 * @returns {array} Updated system cards with applied config
 */
export function applySystemCardConfig(systemCards, config) {
  return systemCards.map(card => {
    const configKey = card.projectConfigKey;
    if (!configKey || !config[configKey]) {
      return card;
    }

    const cardConfig = config[configKey];

    // Skip disabled cards
    if (cardConfig.enabled === false) {
      return null;
    }

    // Apply configuration
    return {
      ...card,
      ...(cardConfig.command && { command: cardConfig.command }),
      ...(cardConfig.description && { description: cardConfig.description }),
      ...cardConfig,
    };
  }).filter(Boolean);
}
