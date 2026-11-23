// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title BushidoFeeVault
/// @notice Retains protocol fees (x402 job fees, execution fees, solver spread) in USDC and
///         compounds them into solver inventory. Self-solving and bridge filling unlock only
///         once retained capital crosses on-chain thresholds; any default drops the vault back
///         to ROUTING (external solvers only).
/// @dev    Accounting invariant: usdc.balanceOf(this) >= inventory + ops + reserve.
///         `outstanding` is capital currently lent to the solver for open fills.
contract BushidoFeeVault {
    // ------------------------------------------------------------------ types
    enum Phase {
        ROUTING, // route every intent to external solvers; retain fees only
        SELF_SOLVE, // fill same-chain intents from own inventory
        BRIDGE // fill cross-chain intents (fill on destination, repaid from origin)
    }

    enum Source {
        X402,
        EXECUTION,
        SOLVER_SPREAD
    }

    struct Fill {
        uint128 amount;
        uint64 drawnAt;
        bool crossChain;
        bool open;
    }

    // -------------------------------------------------------------- constants
    uint16 public constant BPS = 10_000;
    /// @notice Retention floor: at least this share of every fee goes to inventory.
    uint16 public constant MIN_INVENTORY_BPS = 5_000;
    uint16 public constant MIN_RESERVE_BPS = 500;

    // ------------------------------------------------------------------ state
    IERC20 public immutable usdc;

    address public owner;
    address public pendingOwner;
    address public solver;
    /// @notice Inventory bridge adapter (e.g. WarpInventoryBridge) allowed to move idle inventory out.
    address public rebalancer;
    mapping(address => bool) public isCollector;

    uint16 public inventoryBps;
    uint16 public reserveBps;
    uint16 public opsBps;

    uint256 public inventory; // idle solver capital
    uint256 public outstanding; // capital lent out on open fills
    uint256 public reserve; // first-loss buffer
    uint256 public ops; // withdrawable operating revenue

    uint256 public selfSolveThreshold;
    uint256 public bridgeThreshold;

    uint256 public maxFillSize;
    uint16 public maxUtilizationBps;
    uint256 public dailyFillCap;
    uint64 public sameChainTimeout;
    uint64 public crossChainTimeout;

    uint256 public dayStart;
    uint256 public filledToday;

    Phase public phase;
    mapping(bytes32 => Fill) public fills;
    mapping(Source => uint256) public totalCollected;
    uint256 public totalLosses;

    // ----------------------------------------------------------------- events
    event FeeCollected(Source indexed source, address indexed from, uint256 amount, uint256 toInventory, uint256 toReserve, uint256 toOps);
    event InventorySeeded(address indexed from, uint256 amount);
    event PhaseChanged(Phase from, Phase to, string reason);
    event FillDrawn(bytes32 indexed id, uint256 amount, bool crossChain);
    event FillSettled(bytes32 indexed id, uint256 drawn, uint256 returned, int256 pnl);
    event FillDefaulted(bytes32 indexed id, uint256 amount, uint256 coveredByReserve);
    event Withdrawn(string bucket, address indexed to, uint256 amount);
    event SplitUpdated(uint16 inventoryBps, uint16 reserveBps, uint16 opsBps);
    event RiskUpdated(uint256 maxFillSize, uint16 maxUtilizationBps, uint256 dailyFillCap, uint64 sameChainTimeout, uint64 crossChainTimeout);
    event ThresholdsUpdated(uint256 selfSolveThreshold, uint256 bridgeThreshold);
    event SolverUpdated(address solver);
    event RebalancerUpdated(address rebalancer);
    event InventorySent(address indexed rebalancer, uint256 amount, uint256 capitalAfter);
    event SurplusAbsorbed(address indexed caller, uint256 amount);
    event CollectorUpdated(address collector, bool allowed);
    event OwnershipTransferred(address indexed from, address indexed to);

    // ----------------------------------------------------------------- errors
    error NotOwner();
    error NotSolver();
    error NotRebalancer();
    error NotCollector();
    error ZeroAmount();
    error ZeroAddress();
    error BadSplit();
    error BadThresholds();
    error BadSource();
    error PhaseTooLow(Phase required, Phase current);
    error ThresholdNotMet(uint256 capital, uint256 required);
    error FillExists();
    error FillNotOpen();
    error FillTooLarge(uint256 amount, uint256 max);
    error DailyCapExceeded(uint256 wouldBe, uint256 cap);
    error UtilizationExceeded();
    error InsufficientInventory();
    error NotTimedOut();
    error MustBeRoutingAndFlat();
    error InsufficientBucket();
    error TransferFailed();

    // -------------------------------------------------------------- modifiers
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlySolver() {
        if (msg.sender != solver) revert NotSolver();
        _;
    }

    // ------------------------------------------------------------ constructor
    constructor(
        IERC20 _usdc,
        address _owner,
        uint256 _selfSolveThreshold,
        uint256 _bridgeThreshold,
        uint256 _maxFillSize
    ) {
        if (address(_usdc) == address(0) || _owner == address(0)) revert ZeroAddress();
        usdc = _usdc;
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);

        _setSplit(7_000, 1_000, 2_000);
        _setThresholds(_selfSolveThreshold, _bridgeThreshold);
        _setRisk(_maxFillSize, 8_000, _maxFillSize * 20, 15 minutes, 6 hours);
        dayStart = block.timestamp;
    }

    // ================================================================ views
    /// @notice Solver capital the vault owns: idle + lent out on open fills.
    function capital() public view returns (uint256) {
        return inventory + outstanding;
    }

    function nextThreshold() external view returns (uint256) {
        if (phase == Phase.ROUTING) return selfSolveThreshold;
        if (phase == Phase.SELF_SOLVE) return bridgeThreshold;
        return 0;
    }

    function accounted() external view returns (uint256) {
        return inventory + reserve + ops;
    }

    // ============================================================ fee intake
    /// @notice Pull a fee from an authorised collector (x402 payTo forwarder, router) and split it.
    function collectFee(Source source, uint256 amount) external {
        if (!isCollector[msg.sender]) revert NotCollector();
        if (source == Source.SOLVER_SPREAD) revert BadSource();
        if (amount == 0) revert ZeroAmount();
        _pull(msg.sender, amount);
        _split(source, msg.sender, amount);
    }

    /// @notice Anyone may add capital straight to inventory (e.g. founder seed) to graduate faster.
    function seedInventory(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _pull(msg.sender, amount);
        inventory += amount;
        emit InventorySeeded(msg.sender, amount);
    }

    // ============================================================ graduation
    /// @notice Permissionless: steps up one phase once retained capital meets the next threshold.
    function advancePhase() external {
        uint256 cap = capital();
        if (phase == Phase.ROUTING) {
            if (cap < selfSolveThreshold) revert ThresholdNotMet(cap, selfSolveThreshold);
            _setPhase(Phase.SELF_SOLVE, "self-solve threshold met");
        } else if (phase == Phase.SELF_SOLVE) {
            if (cap < bridgeThreshold) revert ThresholdNotMet(cap, bridgeThreshold);
            _setPhase(Phase.BRIDGE, "bridge threshold met");
        }
    }

    /// @notice Owner can only ever step the vault DOWN (safety veto); promotion is threshold-gated.
    function demote(Phase to) external onlyOwner {
        if (uint8(to) >= uint8(phase)) revert PhaseTooLow(to, phase);
        _setPhase(to, "owner veto");
    }

    // ================================================================ fills
    /// @notice Solver borrows inventory to fill an intent. Cross-chain fills require BRIDGE.
    function drawForFill(bytes32 id, uint256 amount, bool crossChain) external onlySolver {
        Phase required = crossChain ? Phase.BRIDGE : Phase.SELF_SOLVE;
        if (uint8(phase) < uint8(required)) revert PhaseTooLow(required, phase);
        if (amount == 0) revert ZeroAmount();
        if (fills[id].drawnAt != 0) revert FillExists();
        if (amount > maxFillSize) revert FillTooLarge(amount, maxFillSize);
        if (amount > inventory) revert InsufficientInventory();

        _rollDay();
        if (filledToday + amount > dailyFillCap) revert DailyCapExceeded(filledToday + amount, dailyFillCap);

        uint256 cap = capital();
        if ((outstanding + amount) * BPS > cap * maxUtilizationBps) revert UtilizationExceeded();

        filledToday += amount;
        inventory -= amount;
        outstanding += amount;
        fills[id] = Fill(uint128(amount), uint64(block.timestamp), crossChain, true);

        _push(solver, amount);
        emit FillDrawn(id, amount, crossChain);
    }

    /// @notice Solver repays principal plus spread. Spread is re-split like any fee (compounding).
    ///         A shortfall is covered from the reserve first.
    function settleFill(bytes32 id, uint256 returned) external onlySolver {
        Fill storage f = fills[id];
        if (!f.open) revert FillNotOpen();
        uint256 drawn = f.amount;
        f.open = false;
        outstanding -= drawn;

        if (returned > 0) _pull(msg.sender, returned);

        if (returned >= drawn) {
            inventory += drawn;
            uint256 profit = returned - drawn;
            if (profit > 0) _split(Source.SOLVER_SPREAD, msg.sender, profit);
            emit FillSettled(id, drawn, returned, int256(profit));
        } else {
            uint256 loss = drawn - returned;
            inventory += returned + _coverLoss(loss);
            emit FillSettled(id, drawn, returned, -int256(loss));
        }
    }

    /// @notice Anyone can write off a fill the solver failed to settle in time.
    ///         This forces the vault back to ROUTING.
    function markDefault(bytes32 id) external {
        Fill storage f = fills[id];
        if (!f.open) revert FillNotOpen();
        uint64 timeout = f.crossChain ? crossChainTimeout : sameChainTimeout;
        if (block.timestamp <= uint256(f.drawnAt) + timeout) revert NotTimedOut();

        uint256 drawn = f.amount;
        f.open = false;
        outstanding -= drawn;
        uint256 covered = _coverLoss(drawn);
        inventory += covered;

        emit FillDefaulted(id, drawn, covered);
        if (phase != Phase.ROUTING) _setPhase(Phase.ROUTING, "fill default");
    }

    // ============================================================ rebalancing
    /// @notice The rebalancer pulls idle inventory to ship it to this protocol's vault on another chain.
    ///         Can't push utilisation over the cap; if capital falls below the current phase's threshold the
    ///         vault demotes itself to the phase that capital still supports.
    function sendInventory(uint256 amount) external {
        if (msg.sender != rebalancer || rebalancer == address(0)) revert NotRebalancer();
        if (amount == 0) revert ZeroAmount();
        if (amount > inventory) revert InsufficientInventory();
        uint256 capAfter = capital() - amount;
        if (outstanding * BPS > capAfter * maxUtilizationBps) revert UtilizationExceeded();

        inventory -= amount;
        _push(rebalancer, amount);
        emit InventorySent(rebalancer, amount, capAfter);

        if (phase == Phase.BRIDGE && capAfter < bridgeThreshold) {
            _setPhase(capAfter >= selfSolveThreshold ? Phase.SELF_SOLVE : Phase.ROUTING, "capital rebalanced away");
        } else if (phase == Phase.SELF_SOLVE && capAfter < selfSolveThreshold) {
            _setPhase(Phase.ROUTING, "capital rebalanced away");
        }
    }

    /// @notice Credit tokens that arrived without going through collectFee/seedInventory/settleFill
    ///         (e.g. a bridge such as a Hyperlane warp route delivering rebalanced inventory) to inventory.
    ///         Permissionless: unaccounted tokens can only ever become solver inventory.
    function absorbSurplus() external returns (uint256 surplus) {
        uint256 bal = usdc.balanceOf(address(this));
        uint256 acc = inventory + reserve + ops;
        if (bal <= acc) return 0;
        surplus = bal - acc;
        inventory += surplus;
        emit SurplusAbsorbed(msg.sender, surplus);
    }

    // ============================================================ withdrawals
    function withdrawOps(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount > ops) revert InsufficientBucket();
        ops -= amount;
        _push(to, amount);
        emit Withdrawn("ops", to, amount);
    }

    /// @notice Retained inventory/reserve can only leave when the vault is in ROUTING with no open fills.
    function emergencyWithdraw(address to, uint256 inventoryAmount, uint256 reserveAmount) external onlyOwner {
        if (phase != Phase.ROUTING || outstanding != 0) revert MustBeRoutingAndFlat();
        if (to == address(0)) revert ZeroAddress();
        if (inventoryAmount > inventory || reserveAmount > reserve) revert InsufficientBucket();
        inventory -= inventoryAmount;
        reserve -= reserveAmount;
        _push(to, inventoryAmount + reserveAmount);
        emit Withdrawn("inventory", to, inventoryAmount);
        emit Withdrawn("reserve", to, reserveAmount);
    }

    // ================================================================ admin
    function setSplit(uint16 _inventoryBps, uint16 _reserveBps, uint16 _opsBps) external onlyOwner {
        _setSplit(_inventoryBps, _reserveBps, _opsBps);
    }

    function setThresholds(uint256 _selfSolve, uint256 _bridge) external onlyOwner {
        _setThresholds(_selfSolve, _bridge);
    }

    function setRisk(
        uint256 _maxFillSize,
        uint16 _maxUtilizationBps,
        uint256 _dailyFillCap,
        uint64 _sameChainTimeout,
        uint64 _crossChainTimeout
    ) external onlyOwner {
        _setRisk(_maxFillSize, _maxUtilizationBps, _dailyFillCap, _sameChainTimeout, _crossChainTimeout);
    }

    function setSolver(address _solver) external onlyOwner {
        if (outstanding != 0) revert MustBeRoutingAndFlat();
        solver = _solver;
        emit SolverUpdated(_solver);
    }

    function setRebalancer(address _rebalancer) external onlyOwner {
        rebalancer = _rebalancer;
        emit RebalancerUpdated(_rebalancer);
    }

    function setCollector(address collector, bool allowed) external onlyOwner {
        if (collector == address(0)) revert ZeroAddress();
        isCollector[collector] = allowed;
        emit CollectorUpdated(collector, allowed);
    }

    function transferOwnership(address to) external onlyOwner {
        pendingOwner = to;
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotOwner();
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    // ============================================================= internal
    function _split(Source source, address from, uint256 amount) internal {
        uint256 toInventory = (amount * inventoryBps) / BPS;
        uint256 toReserve = (amount * reserveBps) / BPS;
        uint256 toOps = amount - toInventory - toReserve; // rounding dust goes to ops
        inventory += toInventory;
        reserve += toReserve;
        ops += toOps;
        totalCollected[source] += amount;
        emit FeeCollected(source, from, amount, toInventory, toReserve, toOps);
    }

    function _coverLoss(uint256 loss) internal returns (uint256 covered) {
        covered = loss < reserve ? loss : reserve;
        reserve -= covered;
        totalLosses += loss - covered;
    }

    function _rollDay() internal {
        if (block.timestamp >= dayStart + 1 days) {
            dayStart = block.timestamp;
            filledToday = 0;
        }
    }

    function _setPhase(Phase to, string memory reason) internal {
        emit PhaseChanged(phase, to, reason);
        phase = to;
    }

    function _setSplit(uint16 inv, uint16 res, uint16 op) internal {
        if (uint256(inv) + res + op != BPS || inv < MIN_INVENTORY_BPS || res < MIN_RESERVE_BPS) revert BadSplit();
        inventoryBps = inv;
        reserveBps = res;
        opsBps = op;
        emit SplitUpdated(inv, res, op);
    }

    function _setThresholds(uint256 selfSolve, uint256 bridge) internal {
        if (selfSolve == 0 || bridge <= selfSolve) revert BadThresholds();
        selfSolveThreshold = selfSolve;
        bridgeThreshold = bridge;
        emit ThresholdsUpdated(selfSolve, bridge);
    }

    function _setRisk(uint256 maxFill, uint16 maxUtil, uint256 dailyCap, uint64 sameTo, uint64 crossTo) internal {
        if (maxFill == 0 || maxUtil == 0 || maxUtil > BPS || dailyCap < maxFill || sameTo == 0 || crossTo < sameTo) {
            revert BadThresholds();
        }
        maxFillSize = maxFill;
        maxUtilizationBps = maxUtil;
        dailyFillCap = dailyCap;
        sameChainTimeout = sameTo;
        crossChainTimeout = crossTo;
        emit RiskUpdated(maxFill, maxUtil, dailyCap, sameTo, crossTo);
    }

    function _pull(address from, uint256 amount) internal {
        if (!usdc.transferFrom(from, address(this), amount)) revert TransferFailed();
    }

    function _push(address to, uint256 amount) internal {
        if (amount == 0) return;
        if (!usdc.transfer(to, amount)) revert TransferFailed();
    }
}
