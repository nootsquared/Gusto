import {execFileSync} from 'node:child_process';
import {server,root} from './client.mjs';
const database=`rescue-test-${Date.now()}`;
const env={...process.env,RESCUE_DATABASE:database};
execFileSync('spacetime',['publish',database,'--server',server,'--module-path','./spacetimedb','--delete-data=never','--yes=skip-login'],{cwd:root,stdio:'inherit'});
for(const script of ['provision.mjs','integration-test.mjs'])execFileSync('node',[`${root}scripts/${script}`],{env,stdio:'inherit'});
execFileSync('node',[`${root}scripts/persistence-test.mjs`,'--save'],{env,stdio:'inherit'});
// Preserve the isolated database so restart/republish persistence can be inspected. Never clear shared data.
execFileSync('spacetime',['publish',database,'--server',server,'--module-path','./spacetimedb','--delete-data=never','--yes=skip-login'],{cwd:root,stdio:'inherit'});
execFileSync('node',[`${root}scripts/persistence-test.mjs`],{env,stdio:'inherit'});
console.log(`PASS: republish preserved the isolated database ${database}`);
