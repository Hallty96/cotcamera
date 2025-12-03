// eslint.config.cjs — ESLint v9 flat config
const tseslint = require('typescript-eslint');
const globals = require('globals');

/** @type {import('eslint').Linter.FlatConfig[]} */
module.exports = [
  // Ignore build output
  { ignores: ['lib/**', 'generated/**'] },

  // JS/CJS/MJS files: NO TS plugin here, so TS rules won't run on config files
  {
    files: ['**/*.js', '**/*.cjs', '**/*.mjs'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: { ...globals.node, ...globals.es2021 },
    },
    rules: {
      // add general JS rules if you like
    },
  },

  // TypeScript files: parser + plugin + recommended rules
  {
    files: ['**/*.ts'],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { sourceType: 'module' }, // no project tsconfig required
      ecmaVersion: 'latest',
    },
    plugins: {
      '@typescript-eslint': tseslint.plugin,
    },
    rules: {
      ...tseslint.configs.recommended.rules,
    },
  },

  // (Optional safety) Explicitly allow require() in this config file
  {
    files: ['eslint.config.cjs'],
    rules: {
      '@typescript-eslint/no-require-imports': 'off',
    },
  },
];
