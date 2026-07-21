import fs from 'node:fs';

const app = JSON.parse(fs.readFileSync(new URL('../app.json', import.meta.url)));
const eas = JSON.parse(fs.readFileSync(new URL('../eas.json', import.meta.url)));

if (app.expo?.extra?.apiUrl) throw new Error('app.json must not contain a mutable API origin');

for (const profileName of ['preview', 'production']) {
  const env = eas.build?.[profileName]?.env ?? {};
  const origin = env.EXPO_PUBLIC_API_URL;
  if (typeof origin !== 'string' || !origin.startsWith('https://') || origin.includes('localhost') || origin.includes('10.0.2.2')) {
    throw new Error(`${profileName} must define a real HTTPS EXPO_PUBLIC_API_URL`);
  }
  if (env.EXPO_PUBLIC_ENABLE_DEMO_DATA !== 'false') {
    throw new Error(`${profileName} must disable demo data`);
  }
}

console.log('Production frontend configuration is fail-closed.');
