// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/// @title UpgradeAuthority
/// @notice Governance guard that enforces APPEND-ONLY diamond upgrades with a timelock.
/// @dev
///   Flow: governor -> schedule(cut) -> wait `minDelay` -> anyone calls execute(cut).
///   Guardian may cancel a pending proposal at any time.
///
///   All cuts are pre-validated so that:
///     1. Every FacetCut.action must be Add (no Replace, no Remove).
///     2. No proposed selector is already registered on the diamond (early check via loupe).
///     3. The optional `_init` target is on an allow-list, or zero.
///
///   Because we only ever Add, historical selectors (e.g. `sendV1`, `sendV2`) remain
///   permanently routable. Users pin by calling the selector they trust.

interface IDiamondCut {
    enum FacetCutAction { Add, Replace, Remove }

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external;
}

interface IDiamondLoupe {
    function facetAddress(bytes4 _functionSelector) external view returns (address);
}

contract UpgradeAuthority {
    // --------------------------------------------
    //  Config
    // --------------------------------------------

    uint256 public constant MIN_DELAY_BOUND = 6 hours;
    uint256 public constant MAX_DELAY_BOUND = 30 days;

    address public immutable diamond;

    address public governor;
    address public guardian;
    uint256 public minDelay;

    mapping(address init => bool allowed) public initAllowlist;

    // --------------------------------------------
    //  Queue
    // --------------------------------------------

    struct Proposal {
        uint64 earliestExecution;
        bool executed;
        bool cancelled;
    }

    mapping(bytes32 id => Proposal) public proposals;

    // --------------------------------------------
    //  Events / Errors
    // --------------------------------------------

    event Scheduled(bytes32 indexed id, uint64 earliestExecution, address indexed proposer);
    event Executed(bytes32 indexed id);
    event Cancelled(bytes32 indexed id);
    event DelayUpdated(uint256 newDelay);
    event GovernorUpdated(address indexed newGovernor);
    event GuardianUpdated(address indexed newGuardian);
    event InitAllowlistUpdated(address indexed init, bool allowed);

    error NotGovernor();
    error NotGuardianOrGovernor();
    error NotAddOnly(uint256 cutIndex, IDiamondCut.FacetCutAction action);
    error SelectorAlreadyRegistered(bytes4 selector, address existingFacet);
    error EmptySelectors(uint256 cutIndex);
    error ZeroFacet(uint256 cutIndex);
    error InitNotAllowed(address init);
    error ProposalMissing();
    error ProposalNotReady();
    error ProposalAlreadyScheduled();
    error ProposalAlreadyExecuted();
    error ProposalAlreadyCancelled();
    error DelayOutOfBounds();
    error ZeroAddress();

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    constructor(address _diamond, address _governor, address _guardian, uint256 _minDelay) {
        if (_diamond == address(0) || _governor == address(0)) revert ZeroAddress();
        if (_minDelay < MIN_DELAY_BOUND || _minDelay > MAX_DELAY_BOUND) revert DelayOutOfBounds();

        diamond = _diamond;
        governor = _governor;
        guardian = _guardian;
        minDelay = _minDelay;
    }

    // --------------------------------------------
    //  Modifiers
    // --------------------------------------------

    modifier onlyGovernor() {
        if (msg.sender != governor) revert NotGovernor();
        _;
    }

    modifier onlyGuardianOrGovernor() {
        if (msg.sender != guardian && msg.sender != governor) revert NotGuardianOrGovernor();
        _;
    }

    // --------------------------------------------
    //  Proposal lifecycle
    // --------------------------------------------

    function hashProposal(
        IDiamondCut.FacetCut[] calldata cuts,
        address init,
        bytes calldata initData,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(cuts, init, initData, salt));
    }

    function schedule(
        IDiamondCut.FacetCut[] calldata cuts,
        address init,
        bytes calldata initData,
        bytes32 salt
    ) external onlyGovernor returns (bytes32 id) {
        _validateAppendOnly(cuts);
        if (init != address(0) && !initAllowlist[init]) revert InitNotAllowed(init);

        id = hashProposal(cuts, init, initData, salt);
        if (proposals[id].earliestExecution != 0) revert ProposalAlreadyScheduled();

        uint64 eta = uint64(block.timestamp + minDelay);
        proposals[id] = Proposal({ earliestExecution: eta, executed: false, cancelled: false });

        emit Scheduled(id, eta, msg.sender);
    }

    function execute(
        IDiamondCut.FacetCut[] calldata cuts,
        address init,
        bytes calldata initData,
        bytes32 salt
    ) external {
        bytes32 id = hashProposal(cuts, init, initData, salt);
        Proposal storage p = proposals[id];

        if (p.earliestExecution == 0) revert ProposalMissing();
        if (p.cancelled) revert ProposalAlreadyCancelled();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp < p.earliestExecution) revert ProposalNotReady();

        // Defence-in-depth: re-run the pre-checks at execution time. Should never
        // revert for a well-formed proposal since this contract is the only cut
        // authority, but cheap insurance if that assumption is ever broken.
        _validateAppendOnly(cuts);

        p.executed = true;
        IDiamondCut(diamond).diamondCut(cuts, init, initData);

        emit Executed(id);
    }

    function cancel(bytes32 id) external onlyGuardianOrGovernor {
        Proposal storage p = proposals[id];
        if (p.earliestExecution == 0) revert ProposalMissing();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (p.cancelled) revert ProposalAlreadyCancelled();

        p.cancelled = true;
        emit Cancelled(id);
    }

    // --------------------------------------------
    //  Validation
    // --------------------------------------------

    function _validateAppendOnly(IDiamondCut.FacetCut[] calldata cuts) internal view {
        IDiamondLoupe loupe = IDiamondLoupe(diamond);

        uint256 len = cuts.length;
        for (uint256 i; i < len; ++i) {
            IDiamondCut.FacetCut calldata c = cuts[i];

            if (c.action != IDiamondCut.FacetCutAction.Add) revert NotAddOnly(i, c.action);
            if (c.facetAddress == address(0)) revert ZeroFacet(i);

            uint256 selLen = c.functionSelectors.length;
            if (selLen == 0) revert EmptySelectors(i);

            for (uint256 j; j < selLen; ++j) {
                bytes4 sel = c.functionSelectors[j];
                address existing = loupe.facetAddress(sel);
                if (existing != address(0)) revert SelectorAlreadyRegistered(sel, existing);
            }
        }
    }

    // --------------------------------------------
    //  Admin (governor-only; governor is expected to be a DAO timelock itself)
    // --------------------------------------------

    function setDelay(uint256 newDelay) external onlyGovernor {
        if (newDelay < MIN_DELAY_BOUND || newDelay > MAX_DELAY_BOUND) revert DelayOutOfBounds();
        minDelay = newDelay;
        emit DelayUpdated(newDelay);
    }

    function setGovernor(address newGovernor) external onlyGovernor {
        if (newGovernor == address(0)) revert ZeroAddress();
        governor = newGovernor;
        emit GovernorUpdated(newGovernor);
    }

    function setGuardian(address newGuardian) external onlyGovernor {
        guardian = newGuardian;
        emit GuardianUpdated(newGuardian);
    }

    function setInitAllowlist(address init, bool allowed) external onlyGovernor {
        initAllowlist[init] = allowed;
        emit InitAllowlistUpdated(init, allowed);
    }
}