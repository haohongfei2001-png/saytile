// Inspect only the synthetic page in the fresh profile created by AXHostedTextEdit.
import {readFileSync} from 'node:fs';
const [portFile, documentURL, action, expected] = process.argv.slice(2);
const port = Number(readFileSync(portFile, 'utf8').split('\n')[0]);
if (!Number.isInteger(port) || port < 1 || port > 65535 || new URL(documentURL).protocol !== 'file:' ||
    !/\/Saytile-owned-[\da-f-]{36}\.html$/i.test(new URL(documentURL).pathname)) throw Error('Invalid fixture');
const origin = `127.0.0.1:${port}`;
const pages = await (await fetch(`http://${origin}/json/list`, {signal: AbortSignal.timeout(3000), redirect: 'error'})).json();
const matches = pages.filter(p => p.type === 'page' && p.url === documentURL);
if (matches.length !== 1) throw Error('Expected exactly one owned fixture page');
const endpoint = new URL(matches[0].webSocketDebuggerUrl);
if (endpoint.protocol !== 'ws:' || endpoint.host !== origin || !endpoint.pathname.startsWith('/devtools/page/')) throw Error('Unexpected debugger target');
const socket = new WebSocket(endpoint);
const timer = setTimeout(() => { console.error('Fixture DOM deadline'); process.exit(2); }, 4000);
try {
  await new Promise((ok, fail) => { socket.onopen = ok; socket.onerror = fail; });
  // Values and commands stay constrained to this document. No keyboard events, Return, or focus restoration.
  function check({documentURL, action, expected}) {
    if (location.href !== documentURL) throw Error('Document changed');
    const field = document.querySelector('#entry'), other = document.querySelector('#other');
    if (!(field instanceof HTMLTextAreaElement) || !(other instanceof HTMLTextAreaElement)) throw Error('Unknown draft');
    if (action !== 'state') {
      if (field !== document.activeElement || field.value !== expected || other.value !== 'OTHER') throw Error('Setup target changed');
      if (action === 'collapse') field.setSelectionRange(15, 15);
      else if (action === 'manualEdit') {
        field.setRangeText('EDITED', 0, 6, 'preserve');
        field.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText'}));
      } else if (action === 'switchTarget') other.focus();
      else throw Error('Unknown fixture action');
    }
    return {exact: field.value === expected, otherIntact: other.value === 'OTHER', focused: field === document.activeElement,
      otherFocused: other === document.activeElement, start: field.selectionStart, end: field.selectionEnd,
      sawFirst: window.sawFirst, sawAppendAfterFirst: window.sawAppendAfterFirst, enter: window.returnCount, submits: window.submitCount};
  }
  const expression = `(${check.toString()})(${JSON.stringify({documentURL, action, expected})})`;
  const witness = await new Promise((ok, fail) => {
    socket.onerror = fail;
    socket.onmessage = ({data}) => {
      const reply = JSON.parse(data);
      if (reply.id !== 1) return;
      if (reply.error || reply.result?.exceptionDetails) fail(Error('Owned DOM check failed'));
      else ok(reply.result.result.value);
    };
    socket.send(JSON.stringify({id: 1, method: 'Runtime.evaluate', params: {expression, returnByValue: true}}));
  });
  console.log(JSON.stringify(witness));
} finally { clearTimeout(timer); socket.close(); }
