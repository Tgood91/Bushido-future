// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Live state of one pass, gathered by DojoPassDNA.tokenURI at read time.
struct PassState {
    uint256 tokenId;
    address holder;
    uint256 chainId;
    uint256 ageDays; // days since mint
    bool practitioner; // live registry flag
    bool honorWired; // HONOR readable on this chain
    uint256 trades; // HONOR tradeCount
    uint256 standing; // HONOR honorScores, clamped 0-100
    uint8[5] virtues; // HONOR scores 0-10: Gi, Yu, Jin, Rei, Makoto
}

interface IDojoPassRenderer {
    function tokenURI(PassState calldata p) external view returns (string memory);
}

/// @title Dojo Pass DNA renderer (fully on-chain)
/// @notice Builds ERC-721 metadata JSON and a layered SVG from live pass state.
/// Pure: same state, same output. Layers: chain background, rank frame,
/// 8 virtue armour pieces (4 tiers each). Meiyo, Chugi and Jisei, swap volume
/// and check-ins have no on-chain source yet and render as "Not yet recorded".
contract DojoPassRenderer is IDojoPassRenderer {
    using Strings for uint256;

    function tokenURI(PassState calldata p) external pure returns (string memory) {
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json(p))));
    }

    // ------------------------------------------------------------------ derived traits

    function rank(uint256 standing) public pure returns (string memory) {
        if (standing >= 90) return "Shogun";
        if (standing >= 75) return "Bushido Master";
        if (standing >= 60) return "Samurai";
        return "Tsurano";
    }

    /// @notice HONOR score 0-10 -> armour tier 0-4 (ceil(score / 2.5)).
    function tier(uint256 score) public pure returns (uint256) {
        uint256 t = (score * 2 + 4) / 5;
        return t > 4 ? 4 : t;
    }

    function chainName(uint256 id) public pure returns (string memory) {
        if (id == 8453) return "Base";
        if (id == 84532) return "Base Sepolia";
        if (id == 143) return "Monad";
        if (id == 10143) return "Monad Testnet";
        return string.concat("Chain ", id.toString());
    }

    // ------------------------------------------------------------------ JSON

    function json(PassState calldata p) public pure returns (string memory) {
        return string.concat(
            unicode'{"name":"Dojo Pass · ',
            _short(p.holder),
            '","description":"A living record of practice, rendered fully on-chain from live state. ',
            "This pass evolves with its holder's trades and virtues. Not yet recorded on-chain: swap volume; check-ins; ",
            p.honorWired ? "virtues Meiyo, Chugi, Jisei." : "trades and virtues on this chain.",
            '","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg(p))),
            '","attributes":',
            _attributes(p),
            "}"
        );
    }

    function _attributes(PassState calldata p) private pure returns (string memory) {
        return string.concat(
            "[",
            _str("Rank", rank(p.standing)),
            ",",
            _num("Standing", p.standing, 100),
            ",",
            _num("Pass Age (days)", p.ageDays, 0),
            ",",
            p.honorWired ? _num("Recorded Trades", p.trades, 0) : _str("Recorded Trades", "Not yet recorded"),
            ",",
            _str("Discipline Volume (USD)", "Not yet recorded"),
            ",",
            _str("Check-in Streak (days)", "Not yet recorded"),
            ",",
            _str("Total Check-ins", "Not yet recorded"),
            ",",
            _str("Home Chain", chainName(p.chainId)),
            ",",
            _str("Practitioner", p.practitioner ? "Yes" : "No"),
            _virtueAttributes(p),
            "]"
        );
    }

    function _virtueAttributes(PassState calldata p) private pure returns (string memory out) {
        for (uint256 i; i < 8; ++i) {
            string memory trait = string.concat(unicode"Virtue — ", _virtueName(i));
            out = string.concat(
                out,
                ",",
                (p.honorWired && i < 5) ? _num(trait, tier(p.virtues[i]), 4) : _str(trait, "Not yet recorded")
            );
        }
    }

    function _str(string memory k, string memory v) private pure returns (string memory) {
        return string.concat('{"trait_type":"', k, '","value":"', v, '"}');
    }

    function _num(string memory k, uint256 v, uint256 max) private pure returns (string memory) {
        return string.concat(
            '{"trait_type":"',
            k,
            '","value":',
            v.toString(),
            ',"display_type":"number"',
            max == 0 ? "" : string.concat(',"max_value":', max.toString()),
            "}"
        );
    }

    // ------------------------------------------------------------------ SVG

    function svg(PassState calldata p) public pure returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 840" width="600" height="840" font-family="Helvetica,Arial,sans-serif">',
            _background(p.chainId),
            _frame(p.standing),
            _header(p),
            '<g fill="rgba(255,255,255,0.14)"><circle cx="300" cy="214" r="26"/><path d="M254 300 Q300 236 346 300 Z"/></g>',
            _stats(p),
            '<line x1="52" y1="412" x2="548" y2="412" stroke="rgba(255,255,255,0.18)"/>',
            _armour(p),
            unicode'<text x="300" y="806" text-anchor="middle" font-size="11" fill="rgba(255,255,255,0.55)">A living record of practice · rendered on-chain</text></svg>'
        );
    }

    function _background(uint256 chainId) private pure returns (string memory) {
        (string memory top, string memory bottom) = (chainId == 8453 || chainId == 84532)
            ? ("#0052FF", "#001A52")
            : (chainId == 143 || chainId == 10143) ? ("#6E54FF", "#1A0F4D") : ("#1B2A4A", "#0A1020");
        string memory id = string.concat("dojo-bg-", chainId.toString());
        return string.concat(
            '<defs><linearGradient id="', id, '" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="', top,
            '"/><stop offset="1" stop-color="', bottom, '"/></linearGradient></defs><rect width="600" height="840" fill="url(#',
            id, ')"/>'
        );
    }

    function _frame(uint256 standing) private pure returns (string memory) {
        (string memory outer, string memory inner, string memory w) = standing >= 90
            ? ("#0B0B0B", "#D4AF37", "20") // Shogun: black and gold
            : standing >= 75
                ? ("#9AA6B2", "#E3E9EF", "18") // Bushido Master: steel
                : standing >= 60 ? ("#4A4F57", "#7C838C", "16") : ("#8B5A2B", "#B07A45", "14"); // iron : wood
        return string.concat(
            '<rect x="10" y="10" width="580" height="820" rx="18" fill="none" stroke="', outer, '" stroke-width="', w,
            '"/><rect x="26" y="26" width="548" height="788" rx="12" fill="none" stroke="', inner, '" stroke-width="3"/>'
        );
    }

    function _header(PassState calldata p) private pure returns (string memory) {
        return string.concat(
            '<text x="300" y="78" text-anchor="middle" font-size="16" letter-spacing="6" fill="rgba(255,255,255,0.75)">DOJO PASS</text>',
            '<text x="300" y="126" text-anchor="middle" font-size="40" font-weight="700" fill="#fff">',
            rank(p.standing),
            '</text><text x="300" y="152" text-anchor="middle" font-size="13" fill="rgba(255,255,255,0.7)">',
            _short(p.holder),
            unicode" · ",
            chainName(p.chainId),
            p.practitioner ? unicode" · Practitioner" : "",
            "</text>"
        );
    }

    function _stats(PassState calldata p) private pure returns (string memory) {
        return string.concat(
            _stat("pass age (days)", p.ageDays.toString(), "120"),
            _stat("recorded trades", p.honorWired ? p.trades.toString() : unicode"—", "240"),
            _stat("standing", p.standing.toString(), "360"),
            _stat("streak", unicode"—", "480")
        );
    }

    function _stat(string memory label, string memory value, string memory x) private pure returns (string memory) {
        return string.concat(
            '<text x="', x, '" y="366" text-anchor="middle" font-size="22" font-weight="700" fill="#fff">', value,
            '</text><text x="', x, '" y="386" text-anchor="middle" font-size="11" fill="rgba(255,255,255,0.65)">', label,
            "</text>"
        );
    }

    function _armour(PassState calldata p) private pure returns (string memory out) {
        for (uint256 i; i < 8; ++i) {
            bool recorded = p.honorWired && i < 5;
            uint256 lvl = recorded ? tier(p.virtues[i]) : 0;
            out = string.concat(out, _slot(i, lvl, recorded, 52 + (i % 4) * 128, 440 + (i / 4) * 140));
        }
    }

    function _slot(uint256 i, uint256 lvl, bool recorded, uint256 x, uint256 y) private pure returns (string memory) {
        return string.concat(
            '<g data-virtue="', _virtueName(i), '" data-tier="', lvl.toString(), '"><rect x="', x.toString(), '" y="',
            y.toString(), '" width="96" height="124" rx="10" fill="rgba(0,0,0,0.28)" stroke="rgba(255,255,255,0.12)"/>',
            _piece(i, lvl, x, y),
            _labels(i, recorded, x, y),
            _pips(lvl, x, y),
            "</g>"
        );
    }

    /// @dev The armour piece itself: fill opacity grows with tier, tier 4 gets a gold rim, tier 0 is a dashed outline.
    function _piece(uint256 i, uint256 lvl, uint256 x, uint256 y) private pure returns (string memory) {
        string memory color = _virtueColor(i);
        return string.concat(
            '<g transform="translate(', (x + 18).toString(), " ", (y + 10).toString(), ')"><path d="', _glyph(i),
            '" fill="', color, '" fill-opacity="', [string("0"), "0.35", "0.6", "0.85", "1"][lvl],
            '" stroke="', lvl == 0 ? "rgba(255,255,255,0.35)" : lvl == 4 ? "#D4AF37" : color,
            lvl == 0 ? '" stroke-width="1.5" stroke-dasharray="4 4"/></g>' : '" stroke-width="2.5"/></g>'
        );
    }

    function _labels(uint256 i, bool recorded, uint256 x, uint256 y) private pure returns (string memory) {
        string memory cx = (x + 48).toString();
        return string.concat(
            '<text x="', cx, '" y="', (y + 84).toString(), '" text-anchor="middle" font-size="15" fill="#fff">',
            _virtueKanji(i), " ", _virtueName(i), '</text><text x="', cx, '" y="', (y + 99).toString(),
            '" text-anchor="middle" font-size="10" fill="rgba(255,255,255,0.6)">',
            recorded ? _virtuePiece(i) : "not yet recorded", "</text>"
        );
    }

    function _pips(uint256 lvl, uint256 x, uint256 y) private pure returns (string memory out) {
        for (uint256 k = 1; k <= 4; ++k) {
            out = string.concat(
                out, '<circle cx="', (x + 18 + k * 12).toString(), '" cy="', (y + 112).toString(), '" r="4" fill="',
                k <= lvl ? "#D4AF37" : "none", '" stroke="rgba(255,255,255,0.5)"/>'
            );
        }
    }

    // ------------------------------------------------------------------ virtue tables

    function _virtueName(uint256 i) private pure returns (string memory) {
        return [string("Gi"), "Yu", "Jin", "Rei", "Makoto", "Meiyo", "Chugi", "Jisei"][i];
    }

    function _virtueKanji(uint256 i) private pure returns (string memory) {
        return [string(unicode"義"), unicode"勇", unicode"仁", unicode"礼", unicode"誠", unicode"名誉", unicode"忠義", unicode"自制"][i];
    }

    function _virtuePiece(uint256 i) private pure returns (string memory) {
        return [string("Gi uniform"), "Crest", "Sash", "Bow-wreath", "Mirror", "Banner", "Knot cord", "Sheath"][i];
    }

    function _virtueColor(uint256 i) private pure returns (string memory) {
        return [string("#E9E4D8"), "#E04A3A", "#3FA66B", "#D9A441", "#9EC9E8", "#C0392B", "#8E6BBF", "#2C2C2C"][i];
    }

    function _glyph(uint256 i) private pure returns (string memory) {
        return [
            string("M14 10 L46 10 L52 50 L8 50 Z M30 10 L22 30 M30 10 L38 30"),
            "M30 8 A22 22 0 1 1 29.9 8 Z M30 20 A4 4 0 1 1 29.9 20 Z M20 36 A4 4 0 1 1 19.9 36 Z M40 36 A4 4 0 1 1 39.9 36 Z",
            "M8 18 L18 10 L52 42 L42 50 Z",
            "M8 34 Q30 0 52 34 M12 40 Q30 14 48 40",
            "M30 6 A22 22 0 1 1 29.9 6 Z M20 18 L26 14",
            "M14 6 L14 54 M14 8 L48 8 L40 20 L48 32 L14 32",
            "M10 30 Q20 10 30 30 Q40 50 50 30 Q40 10 30 30 Q20 50 10 30 Z",
            "M10 46 L44 12 Q50 8 52 14 L18 52 Q12 54 10 46 Z"
        ][i];
    }

    /// @dev "0xabcd…1234"
    function _short(address a) private pure returns (string memory) {
        bytes memory h = bytes(Strings.toHexString(uint160(a), 20));
        bytes memory s = new bytes(10);
        for (uint256 i; i < 6; ++i) s[i] = h[i];
        for (uint256 i; i < 4; ++i) s[6 + i] = h[38 + i];
        return string.concat(string(_slice(s, 0, 6)), unicode"…", string(_slice(s, 6, 4)));
    }

    function _slice(bytes memory b, uint256 from, uint256 len) private pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint256 i; i < len; ++i) out[i] = b[from + i];
    }
}
