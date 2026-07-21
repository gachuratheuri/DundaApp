// Flat ESLint config (ESLint v9+). Uses the unified `typescript-eslint` tooling.
const tseslint = require('typescript-eslint');
const reactHooks = require('eslint-plugin-react-hooks');

module.exports = tseslint.config(
  {
    ignores: [
      'node_modules/**',
      'dist/**',
      'web-build/**',
      '.expo/**',
      'expo-env.d.ts',
      'babel.config.js',
      'metro.config.js',
      'eslint.config.js',
    ],
  },
  ...tseslint.configs.recommended,
  {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: {
      parserOptions: { ecmaFeatures: { jsx: true }, sourceType: 'module' },
    },
    plugins: { 'react-hooks': reactHooks },
    rules: {
      // React Hooks correctness — high value for RN. Deps array is advisory.
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',

      // RN/Expo codebases lean on `any` at native boundaries; keep as a warning.
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-unused-vars': [
        'warn',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      // RN statically requires image/asset modules via require().
      '@typescript-eslint/no-require-imports': 'off',
      // ts suppressions occur at native/3rd-party boundaries; flag, don't block.
      '@typescript-eslint/ban-ts-comment': 'warn',
      // Forward-referenced vars (read in a closure before assignment) need `let`.
      'prefer-const': ['error', { ignoreReadBeforeAssign: true }],
    },
  },
);
