// Jest setup for Phase 12 test infrastructure. jest-expo mocks Expo's own
// native modules automatically; third-party native packages generally need
// their official mock wired up explicitly, which is what this file does.
jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);
