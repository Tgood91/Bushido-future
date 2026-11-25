// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice TESTNET stand-in for HONOR ("Bushido Honor", Monad 0x46D5…7A2e), which exists only
/// on Monad mainnet. Exposes the same read selectors DojoPassDNA uses (tradeCount, honorScores,
/// getVirtueScores). Writes go through `record`, an owner-only stand-in for the real controller-only
/// recordTrade, whose exact signature was never read, so its selector is deliberately not imitated.
contract TestHonor {
    address public owner;
    mapping(address => uint256) public tradeCount;
    mapping(address => uint256) public honorScores;
    mapping(address => uint8[5]) private scores_;

    error NotOwner();
    error InvalidVirtueScore();

    event TradeRecorded(address indexed trader, uint256 tradeCount, uint256 honorScore, uint8[5] virtues);

    constructor(address owner_) {
        owner = owner_;
    }

    /// @notice Record one trade: bumps the count and sets the trader's current standing and
    /// virtue scores (Gi, Yu, Jin, Rei, Makoto; each 0-10, like HONOR).
    function record(address trader, uint256 honorScore, uint8[5] calldata virtues) external {
        if (msg.sender != owner) revert NotOwner();
        for (uint256 i; i < 5; ++i) if (virtues[i] > 10) revert InvalidVirtueScore();
        uint256 n = ++tradeCount[trader];
        honorScores[trader] = honorScore;
        scores_[trader] = virtues;
        emit TradeRecorded(trader, n, honorScore, virtues);
    }

    function getVirtueScores(address trader) external view returns (uint256, uint256, uint256, uint256, uint256) {
        uint8[5] memory s = scores_[trader];
        return (s[0], s[1], s[2], s[3], s[4]);
    }
}
