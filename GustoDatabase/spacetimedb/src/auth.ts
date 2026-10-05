export const authProject = 'project_034Zwg7HzgCGNFHV6q3NX5';
export const authClient = 'client_034Zwg7ImCF86DX87V53K8';
export const authIssuer = 'https://auth.spacetimedb.com/oidc';

// Call only after Maincloud verifies the signature, expiry and sender/token identity pair.
export function registeredClaims(token: string, epochSeconds: number) {
  const parts = token.split('.');
  if (parts.length !== 3) throw Error('unauthorized');
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  let bits = 0, value = 0;
  const bytes: number[] = [];
  for (const char of parts[1]) {
    const index = alphabet.indexOf(char);
    if (index < 0) throw Error('unauthorized');
    value = (value << 6) | index; bits += 6;
    if (bits >= 8) { bits -= 8; bytes.push((value >>> bits) & 255); }
  }
  const claims = JSON.parse(new TextDecoder().decode(new Uint8Array(bytes)));
  const audience = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (claims.iss !== authIssuer || claims.project_id !== authProject ||
      !audience.includes(authClient) || (audience.length > 1 && claims.azp !== authClient) ||
      typeof claims.sub !== 'string' || !claims.sub ||
      typeof claims.exp !== 'number' || claims.exp <= epochSeconds) throw Error('unauthorized');
  const name = typeof claims.name === 'string' ? claims.name.trim().slice(0, 100) : '';
  const picture = typeof claims.picture === 'string' && /^https:\/\/[^\s]+$/.test(claims.picture) && claims.picture.length <= 2000 ? claims.picture : '';
  return { name: name || 'Gusto member', picture };
}
