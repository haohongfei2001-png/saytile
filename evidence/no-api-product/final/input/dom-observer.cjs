// Evidence-only observer: preserve the unchanged headless test flow and hash its owned probe.
const fs = require('node:fs');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const {syncBuiltinESMExports} = require('node:module');
const path = require('node:path');
const realSpawn = cp.spawn;
const binary = path.resolve(process.env.SAYTILE_INPUT_SCRATCH,'dom-coordinator-probe');
const output = path.resolve(process.env.SAYTILE_INPUT_EVIDENCE_DIRECTORY,'dom-binary-identity.json');
const rows = [];
function digest() {return crypto.createHash('sha256').update(fs.readFileSync(binary)).digest('hex');}
cp.spawn = function(command, ...args) {
  let row;
  if (path.resolve(command) === binary) {
    row = {path:binary,sha256_before:digest(),utc:new Date().toISOString()}; rows.push(row);
  }
  const child = realSpawn.call(this,command,...args);
  if (row) child.once('close',()=>{row.sha256_after=digest();row.unchanged=row.sha256_before===row.sha256_after;});
  return child;
};
syncBuiltinESMExports();
process.once('exit',()=>{fs.writeFileSync(output,JSON.stringify(rows,null,2)+'\n');});
