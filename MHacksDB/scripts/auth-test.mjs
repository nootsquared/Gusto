import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from '../spacetimedb/node_modules/typescript/lib/typescript.js';
const source = readFileSync(new URL('../spacetimedb/src/auth.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext } }).outputText;
const { registeredClaims, authIssuer, authClient, authProject } = await import(
  `data:text/javascript;base64,${Buffer.from(compiled).toString('base64')}`);
const claims = { iss: authIssuer, aud: authClient, project_id: authProject, sub: 'user', exp: 2000, name: 'Test User' };
const token = value => `header.${Buffer.from(JSON.stringify(value)).toString('base64url')}.signature`;
assert.equal(registeredClaims(token(claims), 1000).name, 'Test User');
assert.equal(registeredClaims(token({ ...claims, aud: [authClient], name: '' }), 1000).name, 'Rescue member');
for (const changed of [{ iss: 'https://other.example' }, { aud: 'other-client' },
  { project_id: 'other-project' }, { exp: 999 }, { sub: '' }, { aud: [authClient, 'other-client'] }]) {
  assert.throws(() => registeredClaims(token({ ...claims, ...changed }), 1000));
}
assert.throws(() => registeredClaims('invalid', 1000));
console.log('PASS: registration rejects wrong issuer, project, audience, expiry and missing subject');
