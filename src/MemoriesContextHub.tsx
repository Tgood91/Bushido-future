import React, { useState, useMemo, useEffect } from 'react';
import {
  Search,
  Brain,
  Tag,
  Filter,
  Check,
  Copy,
  ExternalLink,
  Shield,
  ArrowRight,
  Plus,
  X,
  TrendingUp,
  Layers,
  Coins,
  Flame,
  SlidersHorizontal,
  Eye,
  Trash2,
  Download,
  RefreshCw,
  Sparkles,
  ChevronRight
} from 'lucide-react';

export type MemoryCategory = 'tokens' | 'nfts' | 'positions' | 'learned_context';

export interface MemoryMetric {
  label: string;
  value: string;
  change?: string;
  isPositive?: boolean;
}

export interface StoredMemoryItem {
  id: string;
  title: string;
  symbol: string;
  category: MemoryCategory;
  address?: string;
  summary: string;
  learnedContext: string;
  virtueKey: 'gi' | 'yu' | 'jin' | 'rei' | 'makoto' | 'meiyo' | 'chugi' | 'jisei';
  virtueName: string;
  virtueKanji: string;
  virtueColor: string;
  confidence: number; // 0-100
  metrics: MemoryMetric[];
  tags: string[];
  learnedBlock: number;
  updatedAt: string;
  riskLevel: 'Minimal' | 'Guarded' | 'Moderate' | 'High';
  isCustom?: boolean;
}

// Initial Stored Memories and Learned Context
export const INITIAL_MEMORIES: StoredMemoryItem[] = [
  // --- TOKENS (10 Items) ---
  {
    id: 'mem_tok_eth',
    title: 'Ethereum (Base Native Gas & Settlement)',
    symbol: 'ETH',
    category: 'tokens',
    address: '0x0000000000000000000000000000000000000000',
    summary: 'Primary sovereign fuel and settlement token across Base Layer 2. Canonical gas asset with minimal slippage resilience.',
    learnedContext: 'Learned routing behavior: Arbitrage between KyberSwap and Aerodrome yields optimal quotes for sizes < 10 ETH. During sequencer congestion spikes, priority fee buffer of 0.001 gwei ensures inclusion without front-running. Highly loyal (Chugi) to Base L2 infrastructure.',
    virtueKey: 'chugi',
    virtueName: 'Loyalty',
    virtueKanji: '忠義',
    virtueColor: '#3B82F6',
    confidence: 99,
    metrics: [
      { label: 'Base Liquidity', value: '$1.42B' },
      { label: 'Avg Slippage', value: '0.01%' },
      { label: 'Block Finality', value: '2.0s' }
    ],
    tags: ['Native', 'Base L2', 'Gas Asset', 'Deep Liquidity', 'Chugi', 'Bluechip'],
    learnedBlock: 52180410,
    updatedAt: 'Block #52181200 • Just now',
    riskLevel: 'Minimal'
  },
  {
    id: 'mem_tok_usdc',
    title: 'USD Coin (Circle Native Base L2)',
    symbol: 'USDC',
    category: 'tokens',
    address: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
    summary: 'Native Circle stablecoin on Base. Primary quote currency with zero bridge risk and 1.00 USD peg stability.',
    learnedContext: 'Learned context: Righteous routing (Gi) requires pairing with WETH via Slipstream concentrated pools. Historical memory shows 0.0001% peg deviation over 180 days. Native burn/mint transfers via CCTP eliminate wrapping friction.',
    virtueKey: 'gi',
    virtueName: 'Righteousness',
    virtueKanji: '義',
    virtueColor: '#10B981',
    confidence: 98,
    metrics: [
      { label: 'Base Circulating', value: '$3.84B' },
      { label: 'Peg Stability', value: '$1.0001' },
      { label: 'Decimals', value: '6' }
    ],
    tags: ['Stablecoin', 'Native CCTP', 'Circle', 'Quote Asset', 'Gi', 'Zero Depeg'],
    learnedBlock: 52179800,
    updatedAt: 'Block #52181150 • 12m ago',
    riskLevel: 'Minimal'
  },
  {
    id: 'mem_tok_weth',
    title: 'Wrapped Ether (Canonical WETH9 on Base)',
    symbol: 'WETH',
    category: 'tokens',
    address: '0x4200000000000000000000000000000000000006',
    summary: 'Canonical ERC-20 wrapper for Ethereum on Base. Standard vehicle for Uniswap v3 & Aerodrome concentrated pool trades.',
    learnedContext: 'Learned context: Wrap/unwrap costs exactly zero extra fees when calling the pre-deployed Base system contract. Memory confirms direct 1:1 parity with zero slippage. Ideal for high-frequency routing algorithms.',
    virtueKey: 'makoto',
    virtueName: 'Sincerity',
    virtueKanji: '誠',
    virtueColor: '#059669',
    confidence: 97,
    metrics: [
      { label: 'Pool Share', value: '38.4%' },
      { label: 'Wrap Cost', value: '<$0.01' },
      { label: 'Decimals', value: '18' }
    ],
    tags: ['Wrapped', 'ERC-20', 'Concentrated DEX', 'Makoto', 'Core'],
    learnedBlock: 52178900,
    updatedAt: 'Block #52181000 • 35m ago',
    riskLevel: 'Minimal'
  },
  {
    id: 'mem_tok_aero',
    title: 'Aerodrome Finance (Base Ecosystem Engine)',
    symbol: 'AERO',
    category: 'tokens',
    address: '0x940181a94A35A4569E4529A3CDfB74e38FD98631',
    summary: 'The central liquidity hub and automated market maker of Base. Employs veAERO vote-lock mechanics and Slipstream pools.',
    learnedContext: 'Learned context: Slipstream concentrated liquidity pools feature dynamic fee tiers that reduce price impact for large trades. Weekly epoch shifts occur on Thursday 00:00 UTC, triggering predictable liquidity rebalancing patterns.',
    virtueKey: 'rei',
    virtueName: 'Respect',
    virtueKanji: '礼',
    virtueColor: '#8B5CF6',
    confidence: 94,
    metrics: [
      { label: 'TVL Share', value: '62.1%' },
      { label: 'Epoch APY', value: '34.2%' },
      { label: 'Slipstream Vol', value: '$84M/d' }
    ],
    tags: ['AMM', 've(3,3)', 'DEX Hub', 'Slipstream', 'Rei', 'Base Native'],
    learnedBlock: 52176400,
    updatedAt: 'Block #52180800 • 1h ago',
    riskLevel: 'Moderate'
  },
  {
    id: 'mem_tok_cbbtc',
    title: 'Coinbase Wrapped BTC (Institutional Collateral)',
    symbol: 'cbBTC',
    category: 'tokens',
    address: '0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf',
    summary: '1:1 Bitcoin backing held securely by Coinbase Custody on Base L2. Ultra high-conviction reserve asset.',
    learnedContext: 'Learned context: Heroic valor (Yu) applies when taking high-conviction swing positions in cbBTC. 8 decimals format requires careful unit normalization. Extremely resilient collateral in lending markets (Moonwell, Aave v3 Base).',
    virtueKey: 'yu',
    virtueName: 'Heroic Valor',
    virtueKanji: '勇',
    virtueColor: '#EF4444',
    confidence: 96,
    metrics: [
      { label: 'Backing Ratio', value: '100% Cold' },
      { label: 'Base TVL', value: '$720M' },
      { label: 'Decimals', value: '8' }
    ],
    tags: ['Bitcoin', 'Coinbase', 'Collateral', 'Institutional', 'Yu', 'Custody'],
    learnedBlock: 52174200,
    updatedAt: 'Block #52180400 • 2h ago',
    riskLevel: 'Minimal'
  },
  {
    id: 'mem_tok_eurc',
    title: 'Euro Coin (Circle Regulated Forex Stablecoin)',
    symbol: 'EURC',
    category: 'tokens',
    address: '0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42',
    summary: 'MiCA-compliant regulated Euro stablecoin issued directly on Base by Circle. Enables 24/7 on-chain foreign exchange.',
    learnedContext: 'Learned context: The EURC/USDC trading pair maintains steady 0.02% spreads on Base. High Jin (Benevolence) score due to frictionless cross-border remittances and zero regulatory ambiguity.',
    virtueKey: 'jin',
    virtueName: 'Benevolence',
    virtueKanji: '仁',
    virtueColor: '#EC4899',
    confidence: 93,
    metrics: [
      { label: 'Compliance', value: 'MiCA Full' },
      { label: 'FX Spread', value: '0.02%' },
      { label: 'Decimals', value: '6' }
    ],
    tags: ['Forex', 'Euro', 'Circle', 'MiCA', 'Jin', 'Cross-Border'],
    learnedBlock: 52172100,
    updatedAt: 'Block #52180100 • 3h ago',
    riskLevel: 'Minimal'
  },
  {
    id: 'mem_tok_virtual',
    title: 'Virtuals Protocol (Autonomous AI Agents Engine)',
    symbol: 'VIRTUAL',
    category: 'tokens',
    address: '0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b',
    summary: 'Co-ownership layer for decentralized autonomous AI agents on Base. High velocity momentum trading.',
    learnedContext: 'Learned context: Strict Self-Control (Jisei) is required. Agent token launches experience extreme 15m volume clusters. Slipstream routing with a strict 2.0% slippage ceiling prevents MEV sandwich exploitation.',
    virtueKey: 'jisei',
    virtueName: 'Self-Control',
    virtueKanji: '自制',
    virtueColor: '#F59E0B',
    confidence: 89,
    metrics: [
      { label: 'Agent Clusters', value: '420+' },
      { label: 'Volatile Beta', value: '2.4x' },
      { label: '24h Volume', value: '$14.2M' }
    ],
    tags: ['AI Agent', 'Co-Ownership', 'High Beta', 'Jisei', 'Momentum'],
    learnedBlock: 52169500,
    updatedAt: 'Block #52179800 • 4h ago',
    riskLevel: 'High'
  },
  {
    id: 'mem_tok_degen',
    title: 'Degen (Farcaster Social Layer-3 & Base Token)',
    symbol: 'DEGEN',
    category: 'tokens',
    address: '0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed',
    summary: 'The primary social tip asset on Farcaster and Base. Rapid retail adoption with dedicated L3 settlement chain.',
    learnedContext: 'Learned context: Social sentiment volume correlations: Farcaster active caster spikes directly precede Base DEX liquidity surges by ~12 minutes. Router must prioritize multi-split liquidity to avoid single-pool slippage.',
    virtueKey: 'meiyo',
    virtueName: 'Honor',
    virtueKanji: '名誉',
    virtueColor: '#D4AF37',
    confidence: 91,
    metrics: [
      { label: 'Farcaster Tips', value: '1.2M/mo' },
      { label: 'Holders', value: '162,000+' },
      { label: 'L3 Bridge Vol', value: '$4.1M/d' }
    ],
    tags: ['SocialFi', 'Farcaster', 'Meme-to-Utility', 'Meiyo', 'L3'],
    learnedBlock: 52165200,
    updatedAt: 'Block #52179100 • 6h ago',
    riskLevel: 'Moderate'
  },
  {
    id: 'mem_tok_brett',
    title: 'Brett (Base Cultural Mascot & High-Cap Meme)',
    symbol: 'BRETT',
    category: 'tokens',
    address: '0x532f27101965dd16442E59d40670FaF5eBB142E4',
    summary: 'Highest market cap meme community token on Base. Heavy DEX volume and deep multi-pool liquidity.',
    learnedContext: 'Learned context: Deep pools on SushiSwap and Aerodrome allow trades up to $25k with <0.3% price impact. However, MEV bots target public mempools; always route through MEV-shielded routers.',
    virtueKey: 'yu',
    virtueName: 'Heroic Valor',
    virtueKanji: '勇',
    virtueColor: '#EF4444',
    confidence: 88,
    metrics: [
      { label: 'Market Cap', value: '$850M' },
      { label: 'Base Ranking', value: '#1 Meme' },
      { label: 'Liquidity Depth', value: '$18M' }
    ],
    tags: ['Meme', 'Community', 'High Volume', 'Yu', 'Aerodrome'],
    learnedBlock: 52160100,
    updatedAt: 'Block #52178200 • 9h ago',
    riskLevel: 'Moderate'
  },
  {
    id: 'mem_tok_toshi',
    title: 'Toshi (The Cat of Base & Community Pioneer)',
    symbol: 'TOSHI',
    category: 'tokens',
    address: '0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4',
    summary: 'Named after Satoshi Nakamoto’s cat and Brian Armstrong’s cat. Founding meme of the Base ecosystem with community tools.',
    learnedContext: 'Learned context: Verified contract bytecode with renounced ownership. Consistent liquidity backing across Uniswap v3 and Aerodrome. High Sincerity (Makoto) score for transparent on-chain history.',
    virtueKey: 'makoto',
    virtueName: 'Sincerity',
    virtueKanji: '誠',
    virtueColor: '#059669',
    confidence: 90,
    metrics: [
      { label: 'Renounced', value: '100% Yes' },
      { label: 'Community Holders', value: '98,400' },
      { label: 'Base Native', value: 'Genesis' }
    ],
    tags: ['Meme', 'Genesis', 'Renounced', 'Makoto', 'Community'],
    learnedBlock: 52155000,
    updatedAt: 'Block #52177000 • 12h ago',
    riskLevel: 'Moderate'
  },

  // --- NFTS (6 Items) ---
  {
    id: 'mem_nft_basegods',
    title: 'Base Gods (Cultural PFP Collection on Base)',
    symbol: 'BASE-GODS',
    category: 'nfts',
    address: '0x0C2337d451296D855EbFCEf515C74495Eb6Fe759',
    summary: 'Flagship cultural avatar collection on Base. Depicts crypto-theological iconography deeply embedded in Base ethos.',
    learnedContext: 'Learned context: Floor price demonstrates high resistance against market drawdowns. Staking or holding grants +5 Bushido Honor bonus in the Dojo. Trait analysis shows "Golden Halo" traits command a 3.4x premium in secondary liquidity.',
    virtueKey: 'meiyo',
    virtueName: 'Honor',
    virtueKanji: '名誉',
    virtueColor: '#D4AF37',
    confidence: 95,
    metrics: [
      { label: 'Floor Price', value: '1.38 ETH' },
      { label: 'Total Supply', value: '5,000' },
      { label: 'Honor Boost', value: '+5 Honor' }
    ],
    tags: ['NFT', 'PFP', 'Base Culture', 'Honor Multiplier', 'Meiyo', 'Staking'],
    learnedBlock: 52171000,
    updatedAt: 'Block #52180900 • 45m ago',
    riskLevel: 'Guarded'
  },
  {
    id: 'mem_nft_basedpunks',
    title: 'Based Punks (Genesis 3,333 Avatar Inscriptions)',
    symbol: 'BASED-PUNKS',
    category: 'nfts',
    address: '0x497eDE63b211B0aE83D04C2046ff6412140F0055',
    summary: 'Historic early generative punk avatars minted directly on Base Mainnet. Diamond-hand holder distribution.',
    learnedContext: 'Learned context: High holder concentration: 82% of holders haven’t transferred in >120 days. Samurai Helmet traits align with protocol virtue grading. Very low velocity creates rapid supply crunches upon volume surges.',
    virtueKey: 'chugi',
    virtueName: 'Loyalty',
    virtueKanji: '忠義',
    virtueColor: '#3B82F6',
    confidence: 93,
    metrics: [
      { label: 'Floor Price', value: '0.45 ETH' },
      { label: 'Supply', value: '3,333' },
      { label: 'Diamond Hands', value: '82%' }
    ],
    tags: ['NFT', 'Punks', 'Genesis', 'Diamond Hands', 'Chugi', 'Low Velocity'],
    learnedBlock: 52168000,
    updatedAt: 'Block #52180200 • 2h ago',
    riskLevel: 'Guarded'
  },
  {
    id: 'mem_nft_frogs',
    title: 'Tiny Based Frogs (100% On-Chain Dynamic SVGs)',
    symbol: 'FROGS',
    category: 'nfts',
    address: '0x4d5Ff672323a7c64a7536dD69c8C4fe1Aea8B06C',
    summary: 'Pioneering on-chain dynamic generative frogs stored directly in contract bytecode without IPFS dependencies.',
    learnedContext: 'Learned context: Fully immutable on-chain SVGs. Contract bytecode has survived multiple L2 hardforks without degradation. Demonstrates pure Righteousness (Gi) in decentralization and permanent provenance.',
    virtueKey: 'gi',
    virtueName: 'Righteousness',
    virtueKanji: '義',
    virtueColor: '#10B981',
    confidence: 96,
    metrics: [
      { label: 'On-Chain Code', value: '100% Bytecode' },
      { label: 'Floor Price', value: '0.22 ETH' },
      { label: 'Zero IPFS Risk', value: 'Verified' }
    ],
    tags: ['NFT', '100% Onchain', 'Dynamic SVG', 'Gi', 'Zero IPFS', 'Permanent'],
    learnedBlock: 52164000,
    updatedAt: 'Block #52179600 • 5h ago',
    riskLevel: 'Minimal'
  },
  {
    id: 'mem_nft_gaias',
    title: 'Onchain Gaias (Generative Eco-Art & Carbon Offset)',
    symbol: 'GAIAS',
    category: 'nfts',
    address: '0x1C5320579eE327291a134766E413B90B5524B514',
    summary: 'Generative art collection on Base with programmatic carbon-offsetting triggers integrated into secondary sales.',
    learnedContext: 'Learned context: Embodies Benevolence (Jin). Smart contract redirects 2% of creator fees to verified Toucan Protocol carbon credits on-chain. Respected by institutional impact funds exploring Base L2.',
    virtueKey: 'jin',
    virtueName: 'Benevolence',
    virtueKanji: '仁',
    virtueColor: '#EC4899',
    confidence: 91,
    metrics: [
      { label: 'Carbon Offset', value: '420 Tons CO2' },
      { label: 'Floor Price', value: '0.18 ETH' },
      { label: 'Jin Alignment', value: '9.8 / 10' }
    ],
    tags: ['NFT', 'Generative Art', 'Carbon Offset', 'Jin', 'ESG Onchain'],
    learnedBlock: 52159000,
    updatedAt: 'Block #52178900 • 7h ago',
    riskLevel: 'Minimal'
  },
  {
    id: 'mem_nft_ronin',
    title: 'Bushido Ronin Access Pass (Genesis Protocol Relic)',
    symbol: 'BUSHIDO-RONIN',
    category: 'nfts',
    address: '0x71C8A90226bF28742A9b910A38eDF09B1925bA43',
    summary: 'The ceremonial membership NFT for Bushido Trading Protocol. Unlocks developer-grade failover routing & MEV priority lanes.',
    learnedContext: 'Learned context: Pass holders enjoy automated zero protocol fee trades across all 6 failover routers. Qualified directly for instant Shogun mastery rank. Transfer triggers ceremonial sign-in prompt reset.',
    virtueKey: 'meiyo',
    virtueName: 'Honor',
    virtueKanji: '名誉',
    virtueColor: '#D4AF37',
    confidence: 99,
    metrics: [
      { label: 'Protocol Perks', value: '0% Routing Fee' },
      { label: 'Priority RPC', value: 'Dedicated Lane' },
      { label: 'Supply Cap', value: '888' }
    ],
    tags: ['NFT', 'Protocol Pass', 'Zero Fee', 'Shogun', 'Meiyo', 'MEV Priority'],
    learnedBlock: 52179000,
    updatedAt: 'Block #52181100 • 20m ago',
    riskLevel: 'Minimal'
  },
  {
    id: 'mem_nft_cyber_samurai',
    title: 'Cyber Samurai Relics (Utility & Trait Leveling)',
    symbol: 'SAMURAI-RELIC',
    category: 'nfts',
    address: '0xB893d56F3e89648Fa2443a9602e4DEe54911739c',
    summary: 'Interactive utility relics that level up dynamically on-chain based on the trader’s virtue trade journal volume.',
    learnedContext: 'Learned context: Dynamic metadata queries Base RPC block events. Higher honor scores unlock visual katana glowing animations in metadata SVG. Memory shows 94% retention rate during bear volatility.',
    virtueKey: 'rei',
    virtueName: 'Respect',
    virtueKanji: '礼',
    virtueColor: '#8B5CF6',
    confidence: 92,
    metrics: [
      { label: 'Dynamic SVG', value: 'Live Metadata' },
      { label: 'Floor Price', value: '0.35 ETH' },
      { label: 'Level Max', value: 'Tier 8' }
    ],
    tags: ['NFT', 'Dynamic Metadata', 'Gamified DeFi', 'Rei', 'Leveling'],
    learnedBlock: 52162000,
    updatedAt: 'Block #52179400 • 6h ago',
    riskLevel: 'Guarded'
  },

  // --- POSITIONS (6 Items) ---
  {
    id: 'mem_pos_usdc_weth_lp',
    title: 'USDC / WETH Concentrated Slipstream LP (Aerodrome)',
    symbol: 'USDC-WETH-LP',
    category: 'positions',
    address: '0x6cDcb1C4A4D1C3C6d054b27AC5B77e89eAFb971d',
    summary: 'Active concentrated liquidity range [2,450 - 2,950 USDC/ETH] capturing high swap fees on Base.',
    learnedContext: 'Learned context: Position conviction is high. Fee APY averages 26.4% in current volatility regime. Impermanent loss buffer remains safely above 3.8%. Auto-rebalancing trigger set if ETH crosses 2,900.',
    virtueKey: 'gi',
    virtueName: 'Righteousness',
    virtueKanji: '義',
    virtueColor: '#10B981',
    confidence: 97,
    metrics: [
      { label: 'Active Range', value: '$2,450 - $2,950' },
      { label: 'Fee APY', value: '26.4%' },
      { label: 'Capital Efficiency', value: '18.2x' }
    ],
    tags: ['Position', 'LP', 'Aerodrome', 'Slipstream', 'Concentrated', 'Gi'],
    learnedBlock: 52178000,
    updatedAt: 'Block #52181050 • 28m ago',
    riskLevel: 'Moderate'
  },
  {
    id: 'mem_pos_cbbtc_eth_swing',
    title: 'cbBTC / ETH Strategic Ratio Swing Position',
    symbol: 'cbBTC-ETH-POS',
    category: 'positions',
    address: '0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf',
    summary: 'Macro ratio position targeting Bitcoin outperformance against Ethereum during L2 institutional expansion.',
    learnedContext: 'Learned context: Opened at 0.038 cbBTC per ETH. Trailing stop-loss disciplined under Jisei (Self-Control) at 0.036. Take-profit tiered at 0.043. Zero leverage eliminates on-chain liquidation vectors.',
    virtueKey: 'jisei',
    virtueName: 'Self-Control',
    virtueKanji: '自制',
    virtueColor: '#F59E0B',
    confidence: 95,
    metrics: [
      { label: 'Entry Ratio', value: '0.0385' },
      { label: 'Target', value: '0.0430' },
      { label: 'Current PnL', value: '+7.4%' }
    ],
    tags: ['Position', 'Ratio Swing', 'cbBTC', 'ETH', 'Jisei', 'Unleveraged'],
    learnedBlock: 52175000,
    updatedAt: 'Block #52180700 • 1h ago',
    riskLevel: 'Guarded'
  },
  {
    id: 'mem_pos_aero_usdc_vamm',
    title: 'AERO / USDC Volatile Yield Pool (Aerodrome vAMM)',
    symbol: 'AERO-USDC-LP',
    category: 'positions',
    address: '0x2223F9FE624688164Cbf095d6B1eEb239C0933C4',
    summary: 'Full-range automated market maker pool providing core liquidity to Base DEX ecosystem.',
    learnedContext: 'Learned context: Yield memory: Weekly epoch flips on Thursday demand harvesting before 23:59 UTC to compound into veAERO locks. High trading volume provides steady 48.2% reward emissions.',
    virtueKey: 'chugi',
    virtueName: 'Loyalty',
    virtueKanji: '忠義',
    virtueColor: '#3B82F6',
    confidence: 91,
    metrics: [
      { label: 'Reward APY', value: '48.2%' },
      { label: 'Pool Type', value: 'vAMM Stable/Vol' },
      { label: 'Harvest Cadence', value: 'Weekly' }
    ],
    tags: ['Position', 'Yield Farm', 'AERO', 'USDC', 'Chugi', 'Emissions'],
    learnedBlock: 52173000,
    updatedAt: 'Block #52180300 • 3h ago',
    riskLevel: 'Moderate'
  },
  {
    id: 'mem_pos_cbeth_collateral',
    title: 'cbETH / ETH Staked Collateral Lending Facility',
    symbol: 'cbETH-COLLATERAL',
    category: 'positions',
    address: '0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22',
    summary: 'Coinbase Liquid Staked ETH held as collateral on Moonwell Base. Low-risk yield generating reserve.',
    learnedContext: 'Learned context: Collateral health factor monitored at 2.45. Borrow rate for USDC is 4.1% while staking APY delivers 3.3%. Net borrowing cost < 1.0% with zero peg de-correlation observed.',
    virtueKey: 'makoto',
    virtueName: 'Sincerity',
    virtueKanji: '誠',
    virtueColor: '#059669',
    confidence: 98,
    metrics: [
      { label: 'Health Factor', value: '2.45 (Safe)' },
      { label: 'Staking APR', value: '3.3%' },
      { label: 'Liquidation Buffer', value: '>45%' }
    ],
    tags: ['Position', 'Lending', 'cbETH', 'Collateral', 'Makoto', 'Safe'],
    learnedBlock: 52170000,
    updatedAt: 'Block #52179900 • 4h ago',
    riskLevel: 'Minimal'
  },
  {
    id: 'mem_pos_virtual_momentum',
    title: 'VIRTUAL / WETH High-Beta Agent Momentum Position',
    symbol: 'VIRTUAL-POS',
    category: 'positions',
    address: '0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b',
    summary: 'Tactical breakout trade capitalizing on agent ecosystem volume expansion.',
    learnedContext: 'Learned context: Heroic valor (Yu) conviction trade. Sized at 5% of trading capital to enforce risk discipline. Breakeven stop moved up after initial +18% impulse.',
    virtueKey: 'yu',
    virtueName: 'Heroic Valor',
    virtueKanji: '勇',
    virtueColor: '#EF4444',
    confidence: 87,
    metrics: [
      { label: 'Allocation', value: '5.0% Portfolio' },
      { label: 'Stop Loss', value: '$1.08 Hard' },
      { label: 'Current Gain', value: '+14.6%' }
    ],
    tags: ['Position', 'Tactical', 'AI Agent', 'Yu', 'Momentum', 'Stop Protection'],
    learnedBlock: 52167000,
    updatedAt: 'Block #52179300 • 6h ago',
    riskLevel: 'High'
  },
  {
    id: 'mem_pos_eurc_usdc_forex',
    title: 'EURC / USDC Delta-Neutral Stable Exchange Position',
    symbol: 'EURC-USDC-LP',
    category: 'positions',
    address: '0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42',
    summary: 'Ultra-tight concentrated stable pair earning zero-impermanent-loss FX swapping fees.',
    learnedContext: 'Learned context: Narrow range [1.06 - 1.12]. Respect (Rei) for protocol architecture: zero liquidation risk, predictable 9.2% annual fee yield, ideal haven during market downturns.',
    virtueKey: 'rei',
    virtueName: 'Respect',
    virtueKanji: '礼',
    virtueColor: '#8B5CF6',
    confidence: 96,
    metrics: [
      { label: 'IL Risk', value: '0.00%' },
      { label: 'Forex APY', value: '9.2%' },
      { label: 'Range', value: '1.06 - 1.12' }
    ],
    tags: ['Position', 'Stable FX', 'Zero IL', 'Rei', 'Delta-Neutral'],
    learnedBlock: 52163000,
    updatedAt: 'Block #52178700 • 8h ago',
    riskLevel: 'Minimal'
  },

  // --- LEARNED CONTEXT & AGENT INSIGHTS (3 Items) ---
  {
    id: 'mem_ctx_mev_protection',
    title: 'MEV Sandwich Vulnerability & Multi-Path Split Route',
    symbol: 'MEV-CTX',
    category: 'learned_context',
    address: '0x1111111254EEB25477B68fb85Ed929f73A960582',
    summary: 'Learned execution heuristics protecting users from sandwich bots and front-running on Base.',
    learnedContext: 'Learned context: High-frequency bots monitor Base mempool transactions with slippage > 0.5%. Splitting order flow across Aerodrome (60%) and Uniswap v3 (40%) drops effective price impact below sandwich threshold profitability. Verified in over 1,400 simulation passes.',
    virtueKey: 'gi',
    virtueName: 'Righteousness',
    virtueKanji: '義',
    virtueColor: '#10B981',
    confidence: 99,
    metrics: [
      { label: 'Bot Immunity', value: '99.4%' },
      { label: 'Avg Alpha Saved', value: '$18.40/tx' },
      { label: 'Split Ratio', value: '60/40 Dynamic' }
    ],
    tags: ['Learned Context', 'MEV Shield', 'Routing', 'Gi', 'Anti-Sandwich', 'Execution'],
    learnedBlock: 52179200,
    updatedAt: 'Block #52181180 • 10m ago',
    riskLevel: 'Minimal'
  },
  {
    id: 'mem_ctx_latency_failover',
    title: 'Base L2 RPC Round-Trip Latency & Failover Matrix',
    symbol: 'RPC-MATRIX',
    category: 'learned_context',
    address: '0x49048044D57e1C92A77f79988d21Fa8fAF74E97e',
    summary: 'Historical telemetry data on Base node providers: QuickNode, Alchemy, Base Public, Infura.',
    learnedContext: 'Learned context: Developer access Base RPC delivers 38ms median ping vs 114ms on generic public nodes. Under network gas re-pricing (EIP-4844 blobs), local failover matrix switches in <200ms without user intervention.',
    virtueKey: 'makoto',
    virtueName: 'Sincerity',
    virtueKanji: '誠',
    virtueColor: '#059669',
    confidence: 98,
    metrics: [
      { label: 'Median Ping', value: '38ms' },
      { label: 'Failover Speed', value: '<200ms' },
      { label: 'Uptime', value: '99.98%' }
    ],
    tags: ['Learned Context', 'RPC Latency', 'Failover Matrix', 'Makoto', 'Infrastructure'],
    learnedBlock: 52177500,
    updatedAt: 'Block #52180950 • 40m ago',
    riskLevel: 'Minimal'
  },
  {
    id: 'mem_ctx_moral_scoring',
    title: 'The Eight Bushido Virtues Moral Scoring Engine',
    symbol: 'BUSHIDO-AI',
    category: 'learned_context',
    address: '0x327Df1E6de0A59F31ba48d066371B3673c9fAbfB',
    summary: 'Continuous deterministic scoring engine aligning liquidity execution with Bushido ethical principles.',
    learnedContext: 'Learned context: Every trade evaluates pool preservation (Jin), route integrity (Gi), sizing discipline (Jisei), and contract sincerity (Makoto). Cumulative honor progression unlocks higher tier ceremonies and protocol perks.',
    virtueKey: 'meiyo',
    virtueName: 'Honor',
    virtueKanji: '名誉',
    virtueColor: '#D4AF37',
    confidence: 100,
    metrics: [
      { label: 'Virtues Audited', value: '8 of 8' },
      { label: 'Deterministic', value: '100% Math' },
      { label: 'Shogun Target', value: '90+ Honor' }
    ],
    tags: ['Learned Context', 'Moral Compass', 'Honor Scoring', 'Meiyo', 'Philosophy', 'AI Agent'],
    learnedBlock: 52180000,
    updatedAt: 'Block #52181190 • 5m ago',
    riskLevel: 'Minimal'
  }
];

// Helper: Highlight matching terms cleanly with gold accent
export function HighlightMatch({ text, query }: { text: string; query: string }) {
  if (!query || !query.trim() || !text) {
    return <span>{text}</span>;
  }

  const trimmedQuery = query.trim();
  // Escape regex special chars
  const escaped = trimmedQuery.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  // Match any individual word tokens if multiple words provided
  const tokens = escaped.split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return <span>{text}</span>;

  const pattern = new RegExp(`(${tokens.join('|')})`, 'gi');
  const parts = text.split(pattern);

  return (
    <span>
      {parts.map((part, i) => {
        const isMatch = tokens.some(t => part.toLowerCase() === t.toLowerCase());
        if (isMatch) {
          return (
            <mark
              key={i}
              style={{
                backgroundColor: '#FEF3C7',
                color: '#92400E',
                fontWeight: 600,
                padding: '0 2px',
                borderRadius: '3px',
                borderBottom: '1.5px solid #D4AF37'
              }}
            >
              {part}
            </mark>
          );
        }
        return <span key={i}>{part}</span>;
      })}
    </span>
  );
}

interface MemoriesContextHubProps {
  onSelectTokenForTrade?: (symbol: string) => void;
  onNavigateToDojo?: () => void;
}

export function MemoriesContextHub({
  onSelectTokenForTrade,
  onNavigateToDojo
}: MemoriesContextHubProps) {
  // Stored memories state (persisted to localStorage)
  const [memories, setMemories] = useState<StoredMemoryItem[]>(() => {
    try {
      const stored = localStorage.getItem('bushido_memories_v2');
      if (stored) {
        const parsed = JSON.parse(stored);
        if (Array.isArray(parsed) && parsed.length > 0) return parsed;
      }
    } catch {}
    return INITIAL_MEMORIES;
  });

  // Search & Filter State
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [selectedVirtue, setSelectedVirtue] = useState<string>('all');
  const [selectedRisk, setSelectedRisk] = useState<string>('all');
  const [sortBy, setSortBy] = useState<'relevance' | 'confidence' | 'newest' | 'symbol'>('relevance');

  // Detail Modal State
  const [inspectedMemory, setInspectedMemory] = useState<StoredMemoryItem | null>(null);

  // Add Memory Modal State
  const [addModalOpen, setAddModalOpen] = useState(false);
  const [newTitle, setNewTitle] = useState('');
  const [newSymbol, setNewSymbol] = useState('');
  const [newCategory, setNewCategory] = useState<MemoryCategory>('tokens');
  const [newAddress, setNewAddress] = useState('');
  const [newSummary, setNewSummary] = useState('');
  const [newContext, setNewContext] = useState('');
  const [newVirtue, setNewVirtue] = useState<'gi' | 'yu' | 'jin' | 'rei' | 'makoto' | 'meiyo' | 'chugi' | 'jisei'>('gi');
  const [newTags, setNewTags] = useState('');
  const [newConfidence, setNewConfidence] = useState(95);

  const [copiedId, setCopiedId] = useState<string | null>(null);

  // Save to localStorage when memories update
  useEffect(() => {
    try {
      localStorage.setItem('bushido_memories_v2', JSON.stringify(memories));
    } catch {}
  }, [memories]);

  // Copy helper
  const handleCopy = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 1800);
  };

  // Reset to default memories
  const handleResetDefaults = () => {
    if (window.confirm('Reset stored memories to default system knowledge?')) {
      setMemories(INITIAL_MEMORIES);
      localStorage.removeItem('bushido_memories_v2');
    }
  };

  // Export JSON backup
  const handleExport = () => {
    const dataStr = 'data:text/json;charset=utf-8,' + encodeURIComponent(JSON.stringify(memories, null, 2));
    const downloadAnchor = document.createElement('a');
    downloadAnchor.setAttribute('href', dataStr);
    downloadAnchor.setAttribute('download', `bushido_memories_backup_${Date.now()}.json`);
    document.body.appendChild(downloadAnchor);
    downloadAnchor.click();
    downloadAnchor.remove();
  };

  // Add new custom memory
  const handleCreateMemory = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newTitle.trim() || !newSymbol.trim()) return;

    const virtueMap: Record<string, { name: string; kanji: string; color: string }> = {
      gi: { name: 'Righteousness', kanji: '義', color: '#10B981' },
      yu: { name: 'Heroic Valor', kanji: '勇', color: '#EF4444' },
      jin: { name: 'Benevolence', kanji: '仁', color: '#EC4899' },
      rei: { name: 'Respect', kanji: '礼', color: '#8B5CF6' },
      makoto: { name: 'Sincerity', kanji: '誠', color: '#059669' },
      meiyo: { name: 'Honor', kanji: '名誉', color: '#D4AF37' },
      chugi: { name: 'Loyalty', kanji: '忠義', color: '#3B82F6' },
      jisei: { name: 'Self-Control', kanji: '自制', color: '#F59E0B' }
    };

    const vInfo = virtueMap[newVirtue] || virtueMap.gi;
    const parsedTags = newTags
      .split(',')
      .map(t => t.trim())
      .filter(Boolean);

    const newItem: StoredMemoryItem = {
      id: `mem_user_${Date.now()}`,
      title: newTitle.trim(),
      symbol: newSymbol.trim().toUpperCase(),
      category: newCategory,
      address: newAddress.trim() || undefined,
      summary: newSummary.trim() || 'Custom contextual memory recorded by trader.',
      learnedContext: newContext.trim() || 'Observed execution patterns and virtue notes recorded during session.',
      virtueKey: newVirtue,
      virtueName: vInfo.name,
      virtueKanji: vInfo.kanji,
      virtueColor: vInfo.color,
      confidence: newConfidence,
      metrics: [
        { label: 'Type', value: newCategory.toUpperCase() },
        { label: 'User Record', value: 'Verified' },
        { label: 'Status', value: 'Active' }
      ],
      tags: parsedTags.length > 0 ? parsedTags : ['Custom', 'User Note', newCategory],
      learnedBlock: 52181210,
      updatedAt: 'Block #52181210 • Just recorded',
      riskLevel: 'Guarded',
      isCustom: true
    };

    setMemories(prev => [newItem, ...prev]);
    setAddModalOpen(false);
    // Reset form
    setNewTitle('');
    setNewSymbol('');
    setNewAddress('');
    setNewSummary('');
    setNewContext('');
    setNewTags('');
    setNewConfidence(95);
  };

  // Delete memory
  const handleDeleteMemory = (id: string) => {
    if (window.confirm('Delete this stored memory item?')) {
      setMemories(prev => prev.filter(m => m.id !== id));
      if (inspectedMemory?.id === id) {
        setInspectedMemory(null);
      }
    }
  };

  // Calculate matching relevance score
  const calculateRelevance = (item: StoredMemoryItem, query: string): number => {
    if (!query.trim()) return 100;
    const q = query.toLowerCase().trim();
    const tokens = q.split(/\s+/).filter(Boolean);

    let score = 0;
    const symbolLower = item.symbol.toLowerCase();
    const titleLower = item.title.toLowerCase();
    const summaryLower = item.summary.toLowerCase();
    const contextLower = item.learnedContext.toLowerCase();
    const addressLower = (item.address || '').toLowerCase();
    const virtueNameLower = item.virtueName.toLowerCase();
    const virtueKanji = item.virtueKanji;
    const tagsLower = item.tags.map(t => t.toLowerCase()).join(' ');

    for (const t of tokens) {
      if (symbolLower === t) score += 120;
      else if (symbolLower.startsWith(t)) score += 80;
      else if (symbolLower.includes(t)) score += 50;

      if (titleLower.includes(t)) score += 40;
      if (tagsLower.includes(t)) score += 35;
      if (addressLower.includes(t)) score += 60;
      if (virtueNameLower.includes(t) || virtueKanji.includes(t)) score += 30;
      if (summaryLower.includes(t)) score += 20;
      if (contextLower.includes(t)) score += 15;
    }

    return score;
  };

  // Filter & Sort Memories
  const filteredMemories = useMemo(() => {
    const q = searchQuery.toLowerCase().trim();

    return memories
      .filter(item => {
        // Category filter
        if (selectedCategory !== 'all' && item.category !== selectedCategory) {
          return false;
        }

        // Virtue filter
        if (selectedVirtue !== 'all' && item.virtueKey !== selectedVirtue) {
          return false;
        }

        // Risk filter
        if (selectedRisk !== 'all' && item.riskLevel.toLowerCase() !== selectedRisk.toLowerCase()) {
          return false;
        }

        // Keyword search query filter
        if (q) {
          const score = calculateRelevance(item, q);
          if (score === 0) return false;
        }

        return true;
      })
      .sort((a, b) => {
        if (sortBy === 'relevance' && q) {
          const scoreA = calculateRelevance(a, q);
          const scoreB = calculateRelevance(b, q);
          return scoreB - scoreA;
        }
        if (sortBy === 'confidence') {
          return b.confidence - a.confidence;
        }
        if (sortBy === 'newest') {
          return b.learnedBlock - a.learnedBlock;
        }
        if (sortBy === 'symbol') {
          return a.symbol.localeCompare(b.symbol);
        }
        return b.learnedBlock - a.learnedBlock;
      });
  }, [memories, searchQuery, selectedCategory, selectedVirtue, selectedRisk, sortBy]);

  // Counts for Category Tabs
  const counts = useMemo(() => {
    return {
      all: memories.length,
      tokens: memories.filter(m => m.category === 'tokens').length,
      nfts: memories.filter(m => m.category === 'nfts').length,
      positions: memories.filter(m => m.category === 'positions').length,
      learned_context: memories.filter(m => m.category === 'learned_context').length
    };
  }, [memories]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
      
      {/* Header Banner */}
      <div style={{
        border: '1px solid #E7E0D8',
        borderRadius: '8px',
        padding: '24px 28px',
        backgroundColor: '#FDFBF7',
        backgroundImage: 'radial-gradient(#E8E0D5 0.75px, transparent 0.75px)',
        backgroundSize: '16px 16px',
        boxShadow: '0 2px 8px rgba(43, 37, 32, 0.03)'
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '16px' }}>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '6px' }}>
              <div style={{
                backgroundColor: '#FFFBEB',
                border: '1px solid #FCD34D',
                padding: '4px 8px',
                borderRadius: '4px',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}>
                <Brain size={14} color="#D4AF37" />
                <span style={{ fontSize: '11px', fontWeight: 600, color: '#92400E', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  Agent Cognitive Memory Store
                </span>
              </div>
              <span style={{ fontSize: '11px', color: '#786F66' }}>
                Base Mainnet • Block #{52181200}
              </span>
            </div>
            <h2 style={{
              fontSize: '24px',
              fontWeight: 400,
              letterSpacing: '0.6px',
              color: '#2B2520',
              fontFamily: 'Georgia, serif',
              margin: '0 0 6px 0'
            }}>
              Stored Memories & Learned Context (記憶と文脈)
            </h2>
            <p style={{ fontSize: '13px', color: '#6B6159', margin: 0, maxWidth: '780px', lineHeight: 1.5 }}>
              Neural and on-chain heuristic database tracking verified token liquidity dynamics, NFT trait velocity, active LP positions, and moral routing memories across Base L2. Filter and search with instant matching highlighting.
            </p>
          </div>

          <div style={{ display: 'flex', gap: '10px', alignItems: 'center', flexWrap: 'wrap' }}>
            <button
              onClick={() => setAddModalOpen(true)}
              style={{
                padding: '9px 16px',
                fontSize: '12px',
                fontWeight: 600,
                backgroundColor: '#D4AF37',
                color: '#1C1917',
                border: '1px solid #B89628',
                borderRadius: '6px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
                boxShadow: '0 1px 3px rgba(0,0,0,0.08)'
              }}
            >
              <Plus size={14} />
              Add Memory / Context
            </button>

            <button
              onClick={handleExport}
              title="Export memories as JSON"
              style={{
                padding: '9px 14px',
                fontSize: '12px',
                fontWeight: 500,
                backgroundColor: '#FFFFFF',
                color: '#2B2520',
                border: '1px solid #D6CEBE',
                borderRadius: '6px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}
            >
              <Download size={13} color="#786F66" />
              Export
            </button>

            <button
              onClick={handleResetDefaults}
              title="Reset knowledge to system default"
              style={{
                padding: '9px 12px',
                fontSize: '12px',
                fontWeight: 500,
                backgroundColor: '#FFFFFF',
                color: '#786F66',
                border: '1px solid #D6CEBE',
                borderRadius: '6px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '4px'
              }}
            >
              <RefreshCw size={13} />
            </button>
          </div>
        </div>

        {/* Quick Summary Badges */}
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
          gap: '12px',
          marginTop: '20px',
          paddingTop: '18px',
          borderTop: '1px dashed #E7E0D8'
        }}>
          <div style={{ backgroundColor: '#FFFFFF', border: '1px solid #EAE3D9', borderRadius: '6px', padding: '10px 14px' }}>
            <span style={{ fontSize: '10px', textTransform: 'uppercase', color: '#8A8077', letterSpacing: '0.4px' }}>Active Memories</span>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: '6px', marginTop: '2px' }}>
              <span style={{ fontSize: '20px', fontWeight: 600, color: '#2B2520', fontFamily: 'Georgia, serif' }}>{memories.length}</span>
              <span style={{ fontSize: '10px', color: '#10B981' }}>Verified</span>
            </div>
          </div>

          <div style={{ backgroundColor: '#FFFFFF', border: '1px solid #EAE3D9', borderRadius: '6px', padding: '10px 14px' }}>
            <span style={{ fontSize: '10px', textTransform: 'uppercase', color: '#8A8077', letterSpacing: '0.4px' }}>Token Records</span>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: '6px', marginTop: '2px' }}>
              <span style={{ fontSize: '20px', fontWeight: 600, color: '#2563EB', fontFamily: 'Georgia, serif' }}>{counts.tokens}</span>
              <span style={{ fontSize: '10px', color: '#786F66' }}>Base DEXs</span>
            </div>
          </div>

          <div style={{ backgroundColor: '#FFFFFF', border: '1px solid #EAE3D9', borderRadius: '6px', padding: '10px 14px' }}>
            <span style={{ fontSize: '10px', textTransform: 'uppercase', color: '#8A8077', letterSpacing: '0.4px' }}>NFT Collections</span>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: '6px', marginTop: '2px' }}>
              <span style={{ fontSize: '20px', fontWeight: 600, color: '#8B5CF6', fontFamily: 'Georgia, serif' }}>{counts.nfts}</span>
              <span style={{ fontSize: '10px', color: '#786F66' }}>Trait Intel</span>
            </div>
          </div>

          <div style={{ backgroundColor: '#FFFFFF', border: '1px solid #EAE3D9', borderRadius: '6px', padding: '10px 14px' }}>
            <span style={{ fontSize: '10px', textTransform: 'uppercase', color: '#8A8077', letterSpacing: '0.4px' }}>LP & Positions</span>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: '6px', marginTop: '2px' }}>
              <span style={{ fontSize: '20px', fontWeight: 600, color: '#10B981', fontFamily: 'Georgia, serif' }}>{counts.positions}</span>
              <span style={{ fontSize: '10px', color: '#786F66' }}>Slipstream/vAMM</span>
            </div>
          </div>

          <div style={{ backgroundColor: '#FFFFFF', border: '1px solid #EAE3D9', borderRadius: '6px', padding: '10px 14px' }}>
            <span style={{ fontSize: '10px', textTransform: 'uppercase', color: '#8A8077', letterSpacing: '0.4px' }}>Learned Context</span>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: '6px', marginTop: '2px' }}>
              <span style={{ fontSize: '20px', fontWeight: 600, color: '#D4AF37', fontFamily: 'Georgia, serif' }}>{counts.learned_context}</span>
              <span style={{ fontSize: '10px', color: '#786F66' }}>Routing Heuristics</span>
            </div>
          </div>
        </div>
      </div>

      {/* Main Search & Filter Control Bar */}
      <div style={{
        border: '1px solid #E7E0D8',
        borderRadius: '8px',
        padding: '20px 24px',
        backgroundColor: '#FFFFFF',
        boxShadow: '0 1px 4px rgba(0,0,0,0.03)'
      }}>
        {/* Search Input Bar with Matching Counter */}
        <div style={{ position: 'relative', marginBottom: '16px' }}>
          <div style={{
            position: 'absolute',
            left: '14px',
            top: '50%',
            transform: 'translateY(-50%)',
            display: 'flex',
            alignItems: 'center',
            color: '#8A8077',
            pointerEvents: 'none'
          }}>
            <Search size={18} />
          </div>
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search stored memories, learned context, tokens (ETH, USDC, AERO), NFTs, LP positions, contract addresses..."
            style={{
              width: '100%',
              padding: '13px 44px 13px 42px',
              fontSize: '14px',
              border: '2px solid #E2D9CC',
              borderRadius: '8px',
              backgroundColor: '#FAF8F5',
              color: '#2B2520',
              fontFamily: 'inherit',
              outline: 'none',
              boxSizing: 'border-box',
              transition: 'border-color 0.2s, background-color 0.2s'
            }}
            onFocus={(e) => {
              e.currentTarget.style.borderColor = '#D4AF37';
              e.currentTarget.style.backgroundColor = '#FFFFFF';
            }}
            onBlur={(e) => {
              e.currentTarget.style.borderColor = '#E2D9CC';
              e.currentTarget.style.backgroundColor = '#FAF8F5';
            }}
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery('')}
              style={{
                position: 'absolute',
                right: '12px',
                top: '50%',
                transform: 'translateY(-50%)',
                background: 'none',
                border: 'none',
                color: '#8A8077',
                cursor: 'pointer',
                padding: '4px',
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center'
              }}
              title="Clear search query"
            >
              <X size={16} />
            </button>
          )}
        </div>

        {/* Category Filter Tabs */}
        <div style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          flexWrap: 'wrap',
          gap: '12px',
          paddingBottom: '16px',
          borderBottom: '1px solid #F0ECE4'
        }}>
          <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap', alignItems: 'center' }}>
            <span style={{ fontSize: '11px', color: '#786F66', fontWeight: 600, marginRight: '4px' }}>
              Category:
            </span>
            <button
              onClick={() => setSelectedCategory('all')}
              style={{
                padding: '6px 12px',
                fontSize: '12px',
                fontWeight: selectedCategory === 'all' ? 600 : 400,
                backgroundColor: selectedCategory === 'all' ? '#2B2520' : '#F5F2EB',
                color: selectedCategory === 'all' ? '#FFFFFF' : '#6B6159',
                border: 'none',
                borderRadius: '6px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}
            >
              All Records <span style={{ opacity: 0.7, fontSize: '10px' }}>({counts.all})</span>
            </button>

            <button
              onClick={() => setSelectedCategory('tokens')}
              style={{
                padding: '6px 12px',
                fontSize: '12px',
                fontWeight: selectedCategory === 'tokens' ? 600 : 400,
                backgroundColor: selectedCategory === 'tokens' ? '#2563EB' : '#EFF6FF',
                color: selectedCategory === 'tokens' ? '#FFFFFF' : '#1E40AF',
                border: selectedCategory === 'tokens' ? 'none' : '1px solid #DBEAFE',
                borderRadius: '6px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}
            >
              <Coins size={12} />
              Tokens <span style={{ opacity: 0.8, fontSize: '10px' }}>({counts.tokens})</span>
            </button>

            <button
              onClick={() => setSelectedCategory('nfts')}
              style={{
                padding: '6px 12px',
                fontSize: '12px',
                fontWeight: selectedCategory === 'nfts' ? 600 : 400,
                backgroundColor: selectedCategory === 'nfts' ? '#7C3AED' : '#F5F3FF',
                color: selectedCategory === 'nfts' ? '#FFFFFF' : '#6D28D9',
                border: selectedCategory === 'nfts' ? 'none' : '1px solid #EDE9FE',
                borderRadius: '6px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}
            >
              <Sparkles size={12} />
              NFTs <span style={{ opacity: 0.8, fontSize: '10px' }}>({counts.nfts})</span>
            </button>

            <button
              onClick={() => setSelectedCategory('positions')}
              style={{
                padding: '6px 12px',
                fontSize: '12px',
                fontWeight: selectedCategory === 'positions' ? 600 : 400,
                backgroundColor: selectedCategory === 'positions' ? '#059669' : '#ECFDF5',
                color: selectedCategory === 'positions' ? '#FFFFFF' : '#047857',
                border: selectedCategory === 'positions' ? 'none' : '1px solid #D1FAE5',
                borderRadius: '6px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}
            >
              <Layers size={12} />
              Positions & LP <span style={{ opacity: 0.8, fontSize: '10px' }}>({counts.positions})</span>
            </button>

            <button
              onClick={() => setSelectedCategory('learned_context')}
              style={{
                padding: '6px 12px',
                fontSize: '12px',
                fontWeight: selectedCategory === 'learned_context' ? 600 : 400,
                backgroundColor: selectedCategory === 'learned_context' ? '#D4AF37' : '#FFFBEB',
                color: selectedCategory === 'learned_context' ? '#1C1917' : '#92400E',
                border: selectedCategory === 'learned_context' ? 'none' : '1px solid #FDE68A',
                borderRadius: '6px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}
            >
              <Brain size={12} />
              Learned Context <span style={{ opacity: 0.8, fontSize: '10px' }}>({counts.learned_context})</span>
            </button>
          </div>

          {/* Sort By Selector */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <span style={{ fontSize: '11px', color: '#786F66' }}>Sort:</span>
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as any)}
              style={{
                padding: '5px 10px',
                fontSize: '12px',
                border: '1px solid #D6CEBE',
                borderRadius: '5px',
                backgroundColor: '#FFFFFF',
                color: '#2B2520',
                cursor: 'pointer',
                outline: 'none'
              }}
            >
              <option value="relevance">Best Relevance</option>
              <option value="confidence">Highest Confidence</option>
              <option value="newest">Latest Learned</option>
              <option value="symbol">Symbol / Name A-Z</option>
            </select>
          </div>
        </div>

        {/* Virtue and Risk Secondary Filters */}
        <div style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          flexWrap: 'wrap',
          gap: '12px',
          marginTop: '14px'
        }}>
          {/* Virtue Chips */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
            <span style={{ fontSize: '11px', color: '#786F66', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '4px' }}>
              <Shield size={12} color="#D4AF37" />
              Virtue Alignment:
            </span>
            {[
              { key: 'all', label: 'All Virtues' },
              { key: 'gi', label: 'Gi (義)' },
              { key: 'yu', label: 'Yu (勇)' },
              { key: 'jin', label: 'Jin (仁)' },
              { key: 'rei', label: 'Rei (礼)' },
              { key: 'makoto', label: 'Makoto (誠)' },
              { key: 'meiyo', label: 'Meiyo (名誉)' },
              { key: 'chugi', label: 'Chugi (忠義)' },
              { key: 'jisei', label: 'Jisei (自制)' }
            ].map(v => (
              <button
                key={v.key}
                onClick={() => setSelectedVirtue(v.key)}
                style={{
                  fontSize: '11px',
                  padding: '3px 8px',
                  borderRadius: '4px',
                  border: selectedVirtue === v.key ? '1px solid #D4AF37' : '1px solid #E5DFD5',
                  backgroundColor: selectedVirtue === v.key ? '#FFFDF5' : '#FFFFFF',
                  color: selectedVirtue === v.key ? '#92400E' : '#6B6159',
                  fontWeight: selectedVirtue === v.key ? 600 : 400,
                  cursor: 'pointer'
                }}
              >
                {v.label}
              </button>
            ))}
          </div>

          {/* Quick Query Shortcuts */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
            <span style={{ fontSize: '11px', color: '#8A8077' }}>Popular:</span>
            {['USDC', 'cbBTC', 'Aerodrome', 'Base Gods', 'Slipstream', 'MEV'].map(keyword => (
              <button
                key={keyword}
                onClick={() => setSearchQuery(keyword)}
                style={{
                  fontSize: '10px',
                  padding: '2px 7px',
                  borderRadius: '3px',
                  border: '1px solid #E5DFD5',
                  backgroundColor: '#FAF8F5',
                  color: '#6B6159',
                  cursor: 'pointer'
                }}
              >
                {keyword}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Active Search & Result Count Status Bar */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0 4px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <span style={{ fontSize: '13px', color: '#2B2520', fontWeight: 500 }}>
            Found <strong>{filteredMemories.length}</strong> matching {filteredMemories.length === 1 ? 'record' : 'records'}
          </span>
          {searchQuery && (
            <span style={{
              fontSize: '11px',
              backgroundColor: '#FEF3C7',
              color: '#92400E',
              padding: '2px 8px',
              borderRadius: '4px',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '4px'
            }}>
              Query: <strong>"{searchQuery}"</strong>
              <button
                onClick={() => setSearchQuery('')}
                style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#92400E', padding: 0 }}
              >
                ×
              </button>
            </span>
          )}
          {selectedCategory !== 'all' && (
            <span style={{
              fontSize: '11px',
              backgroundColor: '#EFEAE3',
              color: '#6B6159',
              padding: '2px 8px',
              borderRadius: '4px'
            }}>
              Category: {selectedCategory}
            </span>
          )}
          {selectedVirtue !== 'all' && (
            <span style={{
              fontSize: '11px',
              backgroundColor: '#FFFBEB',
              color: '#B45309',
              padding: '2px 8px',
              borderRadius: '4px'
            }}>
              Virtue: {selectedVirtue.toUpperCase()}
            </span>
          )}
        </div>

        {(searchQuery || selectedCategory !== 'all' || selectedVirtue !== 'all') && (
          <button
            onClick={() => {
              setSearchQuery('');
              setSelectedCategory('all');
              setSelectedVirtue('all');
            }}
            style={{
              fontSize: '11px',
              color: '#B91C1C',
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              textDecoration: 'underline'
            }}
          >
            Reset all filters
          </button>
        )}
      </div>

      {/* Results Grid with Highlighted Search Terms */}
      {filteredMemories.length > 0 ? (
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill, minmax(350px, 1fr))',
          gap: '16px'
        }}>
          {filteredMemories.map(item => {
            const isToken = item.category === 'tokens';
            const isNft = item.category === 'nfts';
            const isPosition = item.category === 'positions';

            const badgeBg = isToken ? '#EFF6FF' : isNft ? '#F5F3FF' : isPosition ? '#ECFDF5' : '#FFFBEB';
            const badgeColor = isToken ? '#1E40AF' : isNft ? '#6D28D9' : isPosition ? '#047857' : '#92400E';
            const badgeBorder = isToken ? '#BFDBFE' : isNft ? '#DDD6FE' : isPosition ? '#A7F3D0' : '#FDE68A';

            return (
              <div
                key={item.id}
                style={{
                  border: '1px solid #E7E0D8',
                  borderRadius: '8px',
                  backgroundColor: '#FFFFFF',
                  padding: '18px',
                  display: 'flex',
                  flexDirection: 'column',
                  justifyContent: 'space-between',
                  boxShadow: '0 1px 3px rgba(0,0,0,0.02)',
                  transition: 'transform 0.15s, box-shadow 0.15s, border-color 0.15s',
                  cursor: 'pointer',
                  position: 'relative'
                }}
                onClick={() => setInspectedMemory(item)}
                onMouseEnter={(e) => {
                  e.currentTarget.style.borderColor = '#D4AF37';
                  e.currentTarget.style.boxShadow = '0 4px 12px rgba(212, 175, 55, 0.12)';
                  e.currentTarget.style.transform = 'translateY(-2px)';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.borderColor = '#E7E0D8';
                  e.currentTarget.style.boxShadow = '0 1px 3px rgba(0,0,0,0.02)';
                  e.currentTarget.style.transform = 'translateY(0)';
                }}
              >
                <div>
                  {/* Top Row: Symbol, Category Badge, Confidence */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <span style={{
                        fontSize: '14px',
                        fontFamily: 'monospace',
                        fontWeight: 700,
                        color: '#1C1917',
                        backgroundColor: '#FAF8F5',
                        padding: '3px 8px',
                        borderRadius: '4px',
                        border: '1px solid #E5DFD5'
                      }}>
                        <HighlightMatch text={item.symbol} query={searchQuery} />
                      </span>

                      <span style={{
                        fontSize: '10px',
                        fontWeight: 600,
                        backgroundColor: badgeBg,
                        color: badgeColor,
                        border: `1px solid ${badgeBorder}`,
                        padding: '2px 7px',
                        borderRadius: '4px',
                        textTransform: 'uppercase',
                        letterSpacing: '0.4px'
                      }}>
                        {item.category.replace('_', ' ')}
                      </span>

                      {item.isCustom && (
                        <span style={{
                          fontSize: '10px',
                          backgroundColor: '#FFF1F2',
                          color: '#BE123C',
                          border: '1px solid #FECDD3',
                          padding: '2px 6px',
                          borderRadius: '4px',
                          fontWeight: 600
                        }}>
                          User
                        </span>
                      )}
                    </div>

                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <span style={{
                        fontSize: '11px',
                        fontFamily: 'monospace',
                        color: item.confidence >= 95 ? '#059669' : item.confidence >= 90 ? '#D4AF37' : '#B45309',
                        fontWeight: 600
                      }}>
                        {item.confidence}% Conf.
                      </span>
                      <div
                        style={{
                          width: '8px',
                          height: '8px',
                          borderRadius: '50%',
                          backgroundColor: item.virtueColor
                        }}
                        title={`Virtue: ${item.virtueName} (${item.virtueKanji})`}
                      />
                    </div>
                  </div>

                  {/* Title with Match Highlighting */}
                  <h3 style={{
                    fontSize: '15px',
                    fontWeight: 600,
                    color: '#2B2520',
                    margin: '0 0 6px 0',
                    lineHeight: 1.3
                  }}>
                    <HighlightMatch text={item.title} query={searchQuery} />
                  </h3>

                  {/* Contract Address if available */}
                  {item.address && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '8px' }}>
                      <span style={{ fontSize: '10px', color: '#8A8077', fontFamily: 'monospace' }}>
                        Base: <HighlightMatch text={item.address.slice(0, 10) + '...' + item.address.slice(-6)} query={searchQuery} />
                      </span>
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          handleCopy(item.address!, item.id);
                        }}
                        style={{
                          background: 'none',
                          border: 'none',
                          cursor: 'pointer',
                          color: copiedId === item.id ? '#10B981' : '#A8A29E',
                          padding: 0
                        }}
                        title="Copy contract address"
                      >
                        {copiedId === item.id ? <Check size={11} /> : <Copy size={11} />}
                      </button>
                    </div>
                  )}

                  {/* Summary */}
                  <p style={{
                    fontSize: '12px',
                    color: '#6B6159',
                    margin: '0 0 12px 0',
                    lineHeight: 1.45
                  }}>
                    <HighlightMatch text={item.summary} query={searchQuery} />
                  </p>

                  {/* Learned Context Preview Box */}
                  <div style={{
                    backgroundColor: '#FAF8F5',
                    border: '1px solid #EFEAE3',
                    borderLeft: `3px solid ${item.virtueColor}`,
                    borderRadius: '4px',
                    padding: '8px 10px',
                    marginBottom: '12px',
                    fontSize: '11px',
                    color: '#44403C',
                    lineHeight: 1.4
                  }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '4px', marginBottom: '3px', color: item.virtueColor, fontWeight: 600 }}>
                      <Brain size={11} />
                      <span>Learned Context ({item.virtueName} • {item.virtueKanji}):</span>
                    </div>
                    <div>
                      <HighlightMatch
                        text={item.learnedContext.length > 140 ? item.learnedContext.slice(0, 140) + '...' : item.learnedContext}
                        query={searchQuery}
                      />
                    </div>
                  </div>

                  {/* Key Metrics Strip */}
                  <div style={{
                    display: 'grid',
                    gridTemplateColumns: `repeat(${item.metrics.length}, 1fr)`,
                    gap: '6px',
                    padding: '8px 10px',
                    backgroundColor: '#FFFFFF',
                    border: '1px solid #EFEAE3',
                    borderRadius: '5px',
                    marginBottom: '12px'
                  }}>
                    {item.metrics.map((m, idx) => (
                      <div key={idx} style={{ textAlign: 'center' }}>
                        <span style={{ fontSize: '9px', textTransform: 'uppercase', color: '#8A8077', display: 'block' }}>
                          {m.label}
                        </span>
                        <span style={{ fontSize: '11px', fontWeight: 600, color: '#2B2520', fontFamily: 'monospace' }}>
                          {m.value}
                        </span>
                      </div>
                    ))}
                  </div>

                  {/* Matching Tags */}
                  <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap', marginBottom: '12px' }}>
                    {item.tags.map(t => (
                      <span
                        key={t}
                        style={{
                          fontSize: '10px',
                          backgroundColor: '#F5F2EB',
                          color: '#786F66',
                          padding: '2px 6px',
                          borderRadius: '3px'
                        }}
                      >
                        #<HighlightMatch text={t} query={searchQuery} />
                      </span>
                    ))}
                  </div>
                </div>

                {/* Card Footer Actions */}
                <div style={{
                  paddingTop: '10px',
                  borderTop: '1px dashed #EAE3D9',
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center'
                }}>
                  <span style={{ fontSize: '10px', color: '#8A8077' }}>
                    {item.updatedAt}
                  </span>

                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    {isToken && onSelectTokenForTrade && (
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          onSelectTokenForTrade(item.symbol);
                          if (onNavigateToDojo) onNavigateToDojo();
                        }}
                        style={{
                          padding: '4px 8px',
                          fontSize: '11px',
                          fontWeight: 600,
                          backgroundColor: '#D4AF37',
                          color: '#1C1917',
                          border: 'none',
                          borderRadius: '4px',
                          cursor: 'pointer',
                          display: 'flex',
                          alignItems: 'center',
                          gap: '4px'
                        }}
                      >
                        Trade
                        <ArrowRight size={10} />
                      </button>
                    )}

                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        setInspectedMemory(item);
                      }}
                      style={{
                        padding: '4px 8px',
                        fontSize: '11px',
                        fontWeight: 500,
                        backgroundColor: '#FAF8F5',
                        color: '#2B2520',
                        border: '1px solid #D6CEBE',
                        borderRadius: '4px',
                        cursor: 'pointer',
                        display: 'flex',
                        alignItems: 'center',
                        gap: '4px'
                      }}
                    >
                      <Eye size={11} />
                      Details
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        /* Empty State */
        <div style={{
          border: '1px dashed #D6CEBE',
          borderRadius: '8px',
          padding: '48px 24px',
          textAlign: 'center',
          backgroundColor: '#FDFBF7'
        }}>
          <Brain size={32} color="#D4AF37" style={{ margin: '0 auto 12px auto' }} />
          <h3 style={{ fontSize: '16px', fontWeight: 500, color: '#2B2520', margin: '0 0 6px 0', fontFamily: 'Georgia, serif' }}>
            No memories or learned context matched "{searchQuery}"
          </h3>
          <p style={{ fontSize: '12px', color: '#786F66', margin: '0 0 16px 0', maxWidth: '420px', marginLeft: 'auto', marginRight: 'auto' }}>
            Try searching for broader keywords like "ETH", "USDC", "Base Gods", "Aerodrome", "LP", or reset the category filters.
          </p>
          <div style={{ display: 'flex', justifyContent: 'center', gap: '8px' }}>
            <button
              onClick={() => {
                setSearchQuery('');
                setSelectedCategory('all');
                setSelectedVirtue('all');
              }}
              style={{
                padding: '8px 16px',
                fontSize: '12px',
                fontWeight: 600,
                backgroundColor: '#2B2520',
                color: '#FFFFFF',
                border: 'none',
                borderRadius: '4px',
                cursor: 'pointer'
              }}
            >
              Clear Search Query
            </button>
            <button
              onClick={() => setAddModalOpen(true)}
              style={{
                padding: '8px 16px',
                fontSize: '12px',
                fontWeight: 600,
                backgroundColor: '#D4AF37',
                color: '#1C1917',
                border: 'none',
                borderRadius: '4px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}
            >
              <Plus size={14} />
              Add as New Memory
            </button>
          </div>
        </div>
      )}

      {/* Inspect Memory Detail Modal */}
      {inspectedMemory && (
        <div style={{
          position: 'fixed',
          inset: 0,
          backgroundColor: 'rgba(28, 25, 23, 0.65)',
          backdropFilter: 'blur(3px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '20px',
          zIndex: 9999
        }}
        onClick={() => setInspectedMemory(null)}
        >
          <div style={{
            backgroundColor: '#FFFFFF',
            border: '1px solid #D4AF37',
            borderRadius: '10px',
            maxWidth: '680px',
            width: '100%',
            maxHeight: '85vh',
            overflowY: 'auto',
            padding: '28px',
            boxShadow: '0 20px 40px rgba(0,0,0,0.25)',
            boxSizing: 'border-box'
          }}
          onClick={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '16px' }}>
              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '6px' }}>
                  <span style={{
                    fontSize: '16px',
                    fontFamily: 'monospace',
                    fontWeight: 700,
                    color: '#1C1917',
                    backgroundColor: '#FAF8F5',
                    padding: '2px 8px',
                    borderRadius: '4px',
                    border: '1px solid #E5DFD5'
                  }}>
                    {inspectedMemory.symbol}
                  </span>
                  <span style={{
                    fontSize: '11px',
                    fontWeight: 600,
                    backgroundColor: '#EFEAE3',
                    color: '#6B6159',
                    padding: '2px 8px',
                    borderRadius: '4px',
                    textTransform: 'uppercase'
                  }}>
                    {inspectedMemory.category.replace('_', ' ')}
                  </span>
                  <span style={{
                    fontSize: '11px',
                    color: inspectedMemory.virtueColor,
                    fontWeight: 600,
                    display: 'flex',
                    alignItems: 'center',
                    gap: '4px'
                  }}>
                    <Shield size={12} color={inspectedMemory.virtueColor} />
                    {inspectedMemory.virtueName} ({inspectedMemory.virtueKanji})
                  </span>
                </div>
                <h2 style={{ fontSize: '20px', fontWeight: 600, color: '#2B2520', margin: 0, fontFamily: 'Georgia, serif' }}>
                  {inspectedMemory.title}
                </h2>
              </div>
              <button
                onClick={() => setInspectedMemory(null)}
                style={{
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  color: '#786F66',
                  padding: '4px'
                }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Address bar */}
            {inspectedMemory.address && (
              <div style={{
                backgroundColor: '#FAF8F5',
                border: '1px solid #EAE3D9',
                borderRadius: '6px',
                padding: '10px 14px',
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                marginBottom: '18px'
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', overflow: 'hidden' }}>
                  <span style={{ fontSize: '11px', color: '#8A8077', fontWeight: 600 }}>Contract:</span>
                  <span style={{ fontSize: '12px', fontFamily: 'monospace', color: '#2B2520', textOverflow: 'ellipsis', overflow: 'hidden' }}>
                    {inspectedMemory.address}
                  </span>
                </div>
                <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                  <button
                    onClick={() => handleCopy(inspectedMemory.address!, 'modal_addr')}
                    style={{
                      background: 'none',
                      border: 'none',
                      cursor: 'pointer',
                      color: copiedId === 'modal_addr' ? '#10B981' : '#786F66',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '4px',
                      fontSize: '11px'
                    }}
                  >
                    {copiedId === 'modal_addr' ? <Check size={12} /> : <Copy size={12} />}
                    {copiedId === 'modal_addr' ? 'Copied' : 'Copy'}
                  </button>
                  <a
                    href={`https://basescan.org/address/${inspectedMemory.address}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    style={{
                      color: '#2563EB',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '3px',
                      fontSize: '11px',
                      textDecoration: 'none'
                    }}
                  >
                    BaseScan
                    <ExternalLink size={11} />
                  </a>
                </div>
              </div>
            )}

            {/* Summary */}
            <div style={{ marginBottom: '18px' }}>
              <h4 style={{ fontSize: '12px', textTransform: 'uppercase', color: '#8A8077', letterSpacing: '0.4px', margin: '0 0 6px 0' }}>
                Executive Summary
              </h4>
              <p style={{ fontSize: '13px', color: '#44403C', lineHeight: 1.5, margin: 0 }}>
                {inspectedMemory.summary}
              </p>
            </div>

            {/* Full Learned Context */}
            <div style={{
              backgroundColor: '#FFFDF5',
              border: `1px solid ${inspectedMemory.virtueColor}44`,
              borderLeft: `4px solid ${inspectedMemory.virtueColor}`,
              borderRadius: '6px',
              padding: '14px 16px',
              marginBottom: '20px'
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '8px' }}>
                <Brain size={15} color={inspectedMemory.virtueColor} />
                <h4 style={{ fontSize: '13px', fontWeight: 600, color: '#2B2520', margin: 0 }}>
                  Stored Neural & Heuristic Learnings
                </h4>
              </div>
              <p style={{ fontSize: '12px', color: '#2B2520', lineHeight: 1.6, margin: 0 }}>
                {inspectedMemory.learnedContext}
              </p>
            </div>

            {/* Metrics Breakdown */}
            <div style={{ marginBottom: '20px' }}>
              <h4 style={{ fontSize: '12px', textTransform: 'uppercase', color: '#8A8077', letterSpacing: '0.4px', margin: '0 0 8px 0' }}>
                Verified On-Chain Parameters
              </h4>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: '10px' }}>
                {inspectedMemory.metrics.map((m, idx) => (
                  <div key={idx} style={{
                    backgroundColor: '#FAF8F5',
                    border: '1px solid #EAE3D9',
                    borderRadius: '6px',
                    padding: '10px 12px'
                  }}>
                    <span style={{ fontSize: '10px', textTransform: 'uppercase', color: '#8A8077', display: 'block' }}>
                      {m.label}
                    </span>
                    <span style={{ fontSize: '14px', fontWeight: 600, color: '#2B2520', fontFamily: 'monospace' }}>
                      {m.value}
                    </span>
                  </div>
                ))}
                <div style={{
                  backgroundColor: '#FAF8F5',
                  border: '1px solid #EAE3D9',
                  borderRadius: '6px',
                  padding: '10px 12px'
                }}>
                  <span style={{ fontSize: '10px', textTransform: 'uppercase', color: '#8A8077', display: 'block' }}>
                    Learned Block
                  </span>
                  <span style={{ fontSize: '14px', fontWeight: 600, color: '#2B2520', fontFamily: 'monospace' }}>
                    #{inspectedMemory.learnedBlock.toLocaleString()}
                  </span>
                </div>
              </div>
            </div>

            {/* Tags */}
            <div style={{ marginBottom: '24px' }}>
              <h4 style={{ fontSize: '12px', textTransform: 'uppercase', color: '#8A8077', letterSpacing: '0.4px', margin: '0 0 6px 0' }}>
                Associated Metadata Tags
              </h4>
              <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
                {inspectedMemory.tags.map(t => (
                  <span
                    key={t}
                    style={{
                      fontSize: '11px',
                      backgroundColor: '#EFEAE3',
                      color: '#44403C',
                      padding: '3px 8px',
                      borderRadius: '4px'
                    }}
                  >
                    #{t}
                  </span>
                ))}
              </div>
            </div>

            {/* Actions */}
            <div style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              paddingTop: '16px',
              borderTop: '1px solid #EAE3D9'
            }}>
              <div>
                {inspectedMemory.isCustom && (
                  <button
                    onClick={() => handleDeleteMemory(inspectedMemory.id)}
                    style={{
                      padding: '8px 12px',
                      fontSize: '11px',
                      color: '#DC2626',
                      backgroundColor: '#FEF2F2',
                      border: '1px solid #FCA5A5',
                      borderRadius: '5px',
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '4px'
                    }}
                  >
                    <Trash2 size={12} />
                    Delete Memory
                  </button>
                )}
              </div>

              <div style={{ display: 'flex', gap: '10px' }}>
                {inspectedMemory.category === 'tokens' && onSelectTokenForTrade && (
                  <button
                    onClick={() => {
                      onSelectTokenForTrade(inspectedMemory.symbol);
                      setInspectedMemory(null);
                      if (onNavigateToDojo) onNavigateToDojo();
                    }}
                    style={{
                      padding: '10px 18px',
                      fontSize: '12px',
                      fontWeight: 600,
                      backgroundColor: '#D4AF37',
                      color: '#1C1917',
                      border: 'none',
                      borderRadius: '5px',
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '6px'
                    }}
                  >
                    Trade {inspectedMemory.symbol} in Dojo
                    <ArrowRight size={13} />
                  </button>
                )}

                <button
                  onClick={() => setInspectedMemory(null)}
                  style={{
                    padding: '10px 16px',
                    fontSize: '12px',
                    fontWeight: 500,
                    backgroundColor: '#FAF8F5',
                    color: '#2B2520',
                    border: '1px solid #D6CEBE',
                    borderRadius: '5px',
                    cursor: 'pointer'
                  }}
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Add New Custom Memory Modal */}
      {addModalOpen && (
        <div style={{
          position: 'fixed',
          inset: 0,
          backgroundColor: 'rgba(28, 25, 23, 0.65)',
          backdropFilter: 'blur(3px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '20px',
          zIndex: 9999
        }}
        onClick={() => setAddModalOpen(false)}
        >
          <div style={{
            backgroundColor: '#FFFFFF',
            border: '1px solid #D4AF37',
            borderRadius: '10px',
            maxWidth: '600px',
            width: '100%',
            maxHeight: '90vh',
            overflowY: 'auto',
            padding: '28px',
            boxShadow: '0 20px 40px rgba(0,0,0,0.25)',
            boxSizing: 'border-box'
          }}
          onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '18px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Brain size={18} color="#D4AF37" />
                <h3 style={{ fontSize: '18px', fontWeight: 600, color: '#2B2520', margin: 0, fontFamily: 'Georgia, serif' }}>
                  Record New Memory / Learned Context
                </h3>
              </div>
              <button
                onClick={() => setAddModalOpen(false)}
                style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#786F66' }}
              >
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleCreateMemory} style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
              {/* Category & Symbol */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div>
                  <label style={{ fontSize: '11px', color: '#6B6159', textTransform: 'uppercase', display: 'block', marginBottom: '4px' }}>
                    Category *
                  </label>
                  <select
                    value={newCategory}
                    onChange={(e) => setNewCategory(e.target.value as any)}
                    style={{
                      width: '100%',
                      padding: '8px 10px',
                      fontSize: '13px',
                      border: '1px solid #D6CEBE',
                      borderRadius: '5px',
                      backgroundColor: '#FFFFFF',
                      boxSizing: 'border-box'
                    }}
                  >
                    <option value="tokens">Tokens (Base ERC-20)</option>
                    <option value="nfts">NFT Collections</option>
                    <option value="positions">Positions & LP Pools</option>
                    <option value="learned_context">Learned Context & Insights</option>
                  </select>
                </div>

                <div>
                  <label style={{ fontSize: '11px', color: '#6B6159', textTransform: 'uppercase', display: 'block', marginBottom: '4px' }}>
                    Symbol / Ticker *
                  </label>
                  <input
                    type="text"
                    required
                    placeholder="e.g. AERO, BASED-PUNKS"
                    value={newSymbol}
                    onChange={(e) => setNewSymbol(e.target.value.toUpperCase())}
                    style={{
                      width: '100%',
                      padding: '8px 10px',
                      fontSize: '13px',
                      border: '1px solid #D6CEBE',
                      borderRadius: '5px',
                      fontFamily: 'monospace',
                      boxSizing: 'border-box'
                    }}
                  />
                </div>
              </div>

              {/* Title */}
              <div>
                <label style={{ fontSize: '11px', color: '#6B6159', textTransform: 'uppercase', display: 'block', marginBottom: '4px' }}>
                  Title / Name *
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Aerodrome Slipstream Concentrated Pool Insight"
                  value={newTitle}
                  onChange={(e) => setNewTitle(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '8px 10px',
                    fontSize: '13px',
                    border: '1px solid #D6CEBE',
                    borderRadius: '5px',
                    boxSizing: 'border-box'
                  }}
                />
              </div>

              {/* Contract Address */}
              <div>
                <label style={{ fontSize: '11px', color: '#6B6159', textTransform: 'uppercase', display: 'block', marginBottom: '4px' }}>
                  Base Contract Address (Optional)
                </label>
                <input
                  type="text"
                  placeholder="0x..."
                  value={newAddress}
                  onChange={(e) => setNewAddress(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '8px 10px',
                    fontSize: '13px',
                    border: '1px solid #D6CEBE',
                    borderRadius: '5px',
                    fontFamily: 'monospace',
                    boxSizing: 'border-box'
                  }}
                />
              </div>

              {/* Summary */}
              <div>
                <label style={{ fontSize: '11px', color: '#6B6159', textTransform: 'uppercase', display: 'block', marginBottom: '4px' }}>
                  Concise Summary *
                </label>
                <input
                  type="text"
                  required
                  placeholder="Brief high-level description of this asset or position..."
                  value={newSummary}
                  onChange={(e) => setNewSummary(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '8px 10px',
                    fontSize: '13px',
                    border: '1px solid #D6CEBE',
                    borderRadius: '5px',
                    boxSizing: 'border-box'
                  }}
                />
              </div>

              {/* Detailed Learned Context */}
              <div>
                <label style={{ fontSize: '11px', color: '#6B6159', textTransform: 'uppercase', display: 'block', marginBottom: '4px' }}>
                  Learned Context & Heuristic Observations *
                </label>
                <textarea
                  required
                  rows={3}
                  placeholder="Document specific learned market behavior, slippage tolerances, liquidity depth observations, or optimal execution rules..."
                  value={newContext}
                  onChange={(e) => setNewContext(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '8px 10px',
                    fontSize: '13px',
                    border: '1px solid #D6CEBE',
                    borderRadius: '5px',
                    boxSizing: 'border-box',
                    fontFamily: 'inherit',
                    resize: 'vertical'
                  }}
                />
              </div>

              {/* Virtue & Confidence */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div>
                  <label style={{ fontSize: '11px', color: '#6B6159', textTransform: 'uppercase', display: 'block', marginBottom: '4px' }}>
                    Dominant Bushido Virtue
                  </label>
                  <select
                    value={newVirtue}
                    onChange={(e) => setNewVirtue(e.target.value as any)}
                    style={{
                      width: '100%',
                      padding: '8px 10px',
                      fontSize: '13px',
                      border: '1px solid #D6CEBE',
                      borderRadius: '5px',
                      backgroundColor: '#FFFFFF',
                      boxSizing: 'border-box'
                    }}
                  >
                    <option value="gi">Gi (義) • Righteousness</option>
                    <option value="yu">Yu (勇) • Heroic Valor</option>
                    <option value="jin">Jin (仁) • Benevolence</option>
                    <option value="rei">Rei (礼) • Respect</option>
                    <option value="makoto">Makoto (誠) • Sincerity</option>
                    <option value="meiyo">Meiyo (名誉) • Honor</option>
                    <option value="chugi">Chugi (忠義) • Loyalty</option>
                    <option value="jisei">Jisei (自制) • Self-Control</option>
                  </select>
                </div>

                <div>
                  <label style={{ fontSize: '11px', color: '#6B6159', textTransform: 'uppercase', display: 'block', marginBottom: '4px' }}>
                    Confidence Score: {newConfidence}%
                  </label>
                  <input
                    type="range"
                    min="50"
                    max="100"
                    value={newConfidence}
                    onChange={(e) => setNewConfidence(parseInt(e.target.value))}
                    style={{ width: '100%', marginTop: '8px' }}
                  />
                </div>
              </div>

              {/* Tags */}
              <div>
                <label style={{ fontSize: '11px', color: '#6B6159', textTransform: 'uppercase', display: 'block', marginBottom: '4px' }}>
                  Tags (Comma separated)
                </label>
                <input
                  type="text"
                  placeholder="e.g. Base L2, Slipstream, High Yield, Stop Loss"
                  value={newTags}
                  onChange={(e) => setNewTags(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '8px 10px',
                    fontSize: '13px',
                    border: '1px solid #D6CEBE',
                    borderRadius: '5px',
                    boxSizing: 'border-box'
                  }}
                />
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px', marginTop: '12px' }}>
                <button
                  type="button"
                  onClick={() => setAddModalOpen(false)}
                  style={{
                    padding: '10px 16px',
                    fontSize: '12px',
                    backgroundColor: '#FAF8F5',
                    color: '#2B2520',
                    border: '1px solid #D6CEBE',
                    borderRadius: '5px',
                    cursor: 'pointer'
                  }}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  style={{
                    padding: '10px 18px',
                    fontSize: '12px',
                    fontWeight: 600,
                    backgroundColor: '#D4AF37',
                    color: '#1C1917',
                    border: 'none',
                    borderRadius: '5px',
                    cursor: 'pointer'
                  }}
                >
                  Save Stored Memory
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

    </div>
  );
}
