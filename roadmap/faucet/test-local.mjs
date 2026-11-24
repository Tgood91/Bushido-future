// Local test: two anvil chains (as Ethereum Sepolia and Base Sepolia) with a freshly generated random wallet,
// then the faucet server against them. No real keys involved. Run: npm test  (needs anvil on PATH)
import { spawn } from 'node:child_process';
import { ethers } from 'ethers';

const ORIGIN = 'http://test.local';
const PORT = 8790;
const procs = [];
const fail = (m) => { console.error('FAIL:', m); cleanup(); process.exit(1); };
const ok = (c, m) => (c ? console.log('  ✔', m) : fail(m));
function cleanup() { for (const p of procs) p.kill('SIGTERM'); }

function startAnvil(port, chainId, mnemonicArgs) {
  return new Promise((resolve, reject) => {
    const p = spawn('anvil', ['--port', String(port), '--chain-id', String(chainId), ...mnemonicArgs]);
    procs.push(p);
    let out = '';
    p.stdout.on('data', (d) => {
      out += d;
      if (out.includes('Listening on')) {
        const key = out.match(/Private Keys[\s\S]*?\(0\)\s+(0x[0-9a-fA-F]{64})/)[1];
        const mnemonic = out.match(/Mnemonic:\s+([a-z ]+)\n/)[1].trim();
        resolve({ key, mnemonic, rpc: `http://127.0.0.1:${port}` });
      }
    });
    p.on('error', reject);
  });
}

const a = await startAnvil(8551, 11155111, ['--mnemonic-random']);
const b = await startAnvil(8552, 84532, ['--mnemonic', a.mnemonic]);
const server = spawn('node', ['server.mjs'], {
  env: { ...process.env, FAUCET_PRIVATE_KEY: a.key, RPC_SEPOLIA: a.rpc, RPC_BASE_SEPOLIA: b.rpc, PORT: String(PORT),
    ALLOWED_ORIGIN: ORIGIN, DAILY_CAP_ETH: '0.25', MAX_RECIPIENT_ETH_SEPOLIA: '5', MAX_RECIPIENT_ETH_BASE_SEPOLIA: 'off' }, // 5 drips per chain per day for the test
});
procs.push(server);
await new Promise((r) => server.stdout.on('data', (d) => String(d).includes('faucet on') && r()));

const base = `http://127.0.0.1:${PORT}`;
const pa = new ethers.JsonRpcProvider(a.rpc);
const pb = new ethers.JsonRpcProvider(b.rpc);
const drip = (address, ip, origin = ORIGIN) => fetch(`${base}/drip`, {
  method: 'POST', headers: { 'content-type': 'application/json', origin, 'x-forwarded-for': ip }, body: JSON.stringify({ address }),
}).then(async (r) => ({ code: r.status, cors: r.headers.get('access-control-allow-origin'), body: await r.json() }));
const fresh = () => ethers.Wallet.createRandom().address;

try {
  const st = await (await fetch(`${base}/status`)).json();
  ok(st.configured && st.chains.sepolia.balance === '10000.0' && st.chains['base-sepolia'].balance === '10000.0', 'status: configured, faucet funded on both chains');

  ok((await drip(fresh(), '1.1.1.1', 'https://evil.example')).code === 403, 'other origins are refused');
  ok((await drip('0x1234', '1.1.1.2')).code === 400, 'invalid address refused');

  const u1 = fresh();
  const r1 = await drip(u1, '1.1.1.3');
  ok(r1.code === 200 && r1.body.results.every((x) => x.status === 200 && x.tx), 'one tap drips on both chains');
  ok(r1.cors === ORIGIN, 'CORS header returned for the allowed origin');
  ok(ethers.formatEther(await pa.getBalance(u1)) === '0.05' && ethers.formatEther(await pb.getBalance(u1)) === '0.05', 'recipient got 0.05 ETH on Sepolia and Base Sepolia');

  ok((await drip(u1, '1.1.1.4')).code === 429, 'same address again within 24 h → 429');
  ok((await drip(fresh(), '1.1.1.3')).code === 429, 'same IP, new address within 24 h → 429');

  const par = await Promise.all([fresh(), fresh(), fresh()].map((u, i) => drip(u, `2.2.2.${i}`)));
  ok(par.every((r) => r.code === 200 && r.body.results.every((x) => x.status === 200)), '3 simultaneous drips all succeed (no nonce collisions)');

  const rich = fresh(); // 6 ETH on Sepolia (over its 5 ETH limit), 9 ETH on Base Sepolia (limit off)
  await pa.send('anvil_setBalance', [rich, ethers.toBeHex(ethers.parseEther('6'))]);
  await pb.send('anvil_setBalance', [rich, ethers.toBeHex(ethers.parseEther('9'))]);
  const rr = await drip(rich, '3.3.3.3');
  const rs = rr.body.results.find((x) => /already holds ≥ 5\.0 ETH on Ethereum Sepolia/.test(x.error || ''));
  const rb = rr.body.results.find((x) => x.chain === 'base-sepolia' && x.status === 200);
  ok(rs && rb && rr.body.results.length === 2, 'per-chain limits: refused on Sepolia (holds ≥ 5 ETH), dripped on Base Sepolia (limit off)');
  const under = fresh(); // 3.6 ETH on Sepolia is under the 5 ETH limit
  await pa.send('anvil_setBalance', [under, ethers.toBeHex(ethers.parseEther('3.6'))]);
  const ru = await drip(under, '3.3.3.4');
  ok(ru.body.results.find((x) => x.chain === 'sepolia')?.status === 200, 'wallet holding 3.6 ETH still gets a Sepolia drip');

  // 5 drips per chain so far (Sepolia: r1, 3 parallel, 3.6 ETH wallet; Base Sepolia: r1, 3 parallel, rich wallet)
  const r6 = await drip(fresh(), '5.5.5.5');
  ok(r6.code === 429 && r6.body.results.every((x) => /daily cap/.test(x.error)), 'daily cap stops further drips');

  const st2 = await (await fetch(`${base}/status`)).json();
  ok(st2.chains.sepolia.sentToday === '0.25', 'status reports 0.25 ETH sent today on Sepolia');
  console.log('FAUCET TESTS PASSED');
} catch (e) {
  fail(e.message);
}
cleanup();
