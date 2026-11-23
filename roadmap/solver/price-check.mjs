// Checks that each testnet market's live price is tied to the real mainnet price.
// For every chain in ../testnet/chains.json with a `market`, reads the testnet Chainlink feed the market prices
// from and the matching mainnet Chainlink feed (`market.mainnetReference`), then reports the gap.
//   node price-check.mjs                # exit 1 if any gap > 1% or any testnet feed is older than its maxStaleness
//   MAX_GAP_BPS=50 node price-check.mjs # tighter threshold (0.5%)
import { readFileSync } from 'node:fs';
import { ethers } from 'ethers';

const CHAINS = JSON.parse(readFileSync(new URL('../testnet/chains.json', import.meta.url))).chains;
const MAX_GAP_BPS = BigInt(process.env.MAX_GAP_BPS || 100);
const ABI = [
  'function latestRoundData() view returns (uint80,int256,uint256,uint256,uint80)',
  'function decimals() view returns (uint8)',
];

async function read(rpc, chainId, addr) {
  const f = new ethers.Contract(addr, ABI, new ethers.JsonRpcProvider(rpc, chainId, { staticNetwork: true }));
  const [[, answer, , updatedAt], dec] = await Promise.all([f.latestRoundData(), f.decimals()]);
  const ageSec = Date.now() / 1000 - Number(updatedAt);
  return { price: answer, dec: Number(dec), ageSec, ageMin: Math.round(ageSec / 60) };
}

const fmt = (x, dec) => Number(ethers.formatUnits(x, dec)).toLocaleString('en-US', { maximumFractionDigits: 4 });
let bad = 0;
for (const c of Object.values(CHAINS)) {
  const m = c.market;
  if (!m || !m.mainnetReference) continue;
  const ref = m.mainnetReference;
  try {
    const [t, r] = await Promise.all([read(c.rpc, c.id, c.chainlink[m.feed]), read(ref.rpc, ref.chainId, ref.feed)]);
    const tp = t.price * 10n ** BigInt(18 - t.dec);
    const rp = r.price * 10n ** BigInt(18 - r.dec);
    const gapBps = ((tp > rp ? tp - rp : rp - tp) * 10_000n) / rp;
    const stale = t.ageSec > m.maxStaleness;
    const ok = gapBps <= MAX_GAP_BPS && !stale;
    if (!ok) bad++;
    console.log(
      [
        ok ? 'OK  ' : 'FAIL',
        m.symbol.padEnd(6),
        c.name.padEnd(17),
        ('$' + fmt(t.price, t.dec)).padEnd(11),
        ('(' + t.ageMin + ' min)').padEnd(10),
        'vs ' + ref.chain + ' mainnet',
        ('$' + fmt(r.price, r.dec)).padEnd(11),
        ('(' + r.ageMin + ' min)').padEnd(10),
        'gap ' + (Number(gapBps) / 100).toFixed(2) + '%',
        stale ? 'STALE testnet feed' : '',
      ].join(' '),
    );
  } catch (e) {
    bad++;
    console.log('FAIL', m.symbol, c.name + ':', e.shortMessage || e.message);
  }
}
const limit = Number(MAX_GAP_BPS) / 100 + '%';
if (bad) {
  console.log('\n' + bad + ' market(s) not tied to mainnet within ' + limit);
  process.exit(1);
}
console.log('\nAll testnet markets within ' + limit + ' of mainnet.');
