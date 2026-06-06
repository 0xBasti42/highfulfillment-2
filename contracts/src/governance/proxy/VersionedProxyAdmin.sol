// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/*//////////////////////////////////////////////////////////////
//                       VersionedProxyAdmin
//------------------------------------------------------------
//  Singleton authority for the trustless, version-controlled
//  upgrade model implemented by VersionedProxy. Gates every
//  governance action on every VersionedProxy deployed by
//  HighPotential, covering both the timelocked upgrade path
//  (schedule + delay + execute) and the immediate-toggle path
//  (pause / unpause / freeze / metadata).
//
//  The admin owns the *process* of upgrades; the VersionedProxy
//  enforces the *shape* (append-only cuts, versioned names).
//  Together they guarantee that no function ever registered on a
//  proxy can be silently replaced or removed, every new function
//  is provably a monotonic successor of its family, and every
//  transition is subject to a public timelock window.
//
//  Authority chain:
//      multisig ──► Orchestrator ──► VersionedProxyAdmin ──► { VersionedProxy₁, … VersionedProxyₙ }
//
//  Every VersionedProxy's LibDiamond.versionedProxyAdmin is pinned
//  to this contract's address. Each external function that mutates
//  state takes the target proxy as its first parameter so one
//  deployed VersionedProxyAdmin can govern any number of proxies.
//
//  Versioned cut path
//  ------------------
//  Cuts enter the admin as VersionedFacetCut[], where each entry
//  carries the canonical human-readable signature of a function
//  (e.g. "deployV2(CreateParams)") rather than a pre-computed bytes4
//  selector. The admin parses the signature on-chain to enforce
//  the HighPotential versioning convention:
//
//      <familyName>V<version>(<argTypes>)
//
//  From the signature the admin derives:
//      * selector  = bytes4(keccak256(bytes(signature)))
//      * family    = keccak256(bytes(familyName))
//      * version   = <uint32>
//
//  The resulting triple is validated against the target proxy's
//  loupe + metadata registry (selector not already registered,
//  version strictly equal to latestInFamily + 1 or == 1 if first).
//  Only after all validations pass is the cut scheduled. At execute
//  time the same validation runs again as defence in depth, then the
//  derived standard FacetCut[] is forwarded to the proxy's
//  EIP-2535-compliant `diamondCut`, and the metadata is registered
//  atomically in the same transaction via setSelectorMetaBatch.
//
//  Timing model:
//      * Cuts (diamondCut)         — schedule + timelock + execute
//      * Pause   (pauseSelectors)  — immediate
//      * Unpause (unpauseSelectors)— immediate (policy: intentionally
//                                   symmetric since there is only one
//                                   executor role)
//      * Metadata / deprecation    — immediate
//      * Freeze                    — immediate (one-way)
//////////////////////////////////////////////////////////////*/

import { IDiamondCut } from "./interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "./interfaces/IDiamondLoupe.sol";
import { IDiamondLoupeExt } from "./interfaces/IDiamondLoupeExt.sol";
import { IGovernanceFacet } from "./interfaces/IGovernanceFacet.sol";
import { LibDiamond } from "./libraries/LibDiamond.sol";

contract VersionedProxyAdmin {
    // --------------------------------------------
    //  Versioned cut types (HP-specific)
    // --------------------------------------------

    /// @dev A single selector-to-be-added, identified by its canonical
    ///      human-readable signature. The corresponding bytes4 selector and
    ///      (family, version) are derived on-chain by the timelock.
    struct VersionedSelector {
        string signature; // e.g. "deployV2(CreateParams)"
    }

    struct VersionedFacetCut {
        address facetAddress;
        VersionedSelector[] selectors;
    }

    // --------------------------------------------
    //  Config
    // --------------------------------------------

    uint256 public constant MIN_DELAY_BOUND = 6 hours;
    uint256 public constant MAX_DELAY_BOUND = 30 days;

    /// @notice Sole account that may schedule, execute, and trigger immediate
    ///         actions. In production, the Orchestrator contract.
    address public immutable executor;

    /// @notice Minimum delay, in seconds, between `schedule` and `execute`
    ///         for a cut. Applies uniformly across every governed versionedProxy.
    uint256 public minDelay;

    // --------------------------------------------
    //  Queue
    // --------------------------------------------

    struct Proposal {
        uint64 earliestExecution; // 0 => not scheduled
        bool executed;
        bool cancelled;
        address versionedProxy;          // target versionedProxy; retained for the Cancelled event
    }

    mapping(bytes32 id => Proposal) public proposals;

    // --------------------------------------------
    //  Events
    // --------------------------------------------

    event Scheduled(address indexed versionedProxy, bytes32 indexed id, uint64 earliestExecution);
    event Executed(address indexed versionedProxy, bytes32 indexed id);
    event Cancelled(address indexed versionedProxy, bytes32 indexed id);
    event DelayUpdated(uint256 newDelay);

    event Paused(address indexed versionedProxy, bytes4[] selectors);
    event Unpaused(address indexed versionedProxy, bytes4[] selectors);
    event Frozen(address indexed versionedProxy);
    event MetaSet(
        address indexed versionedProxy,
        bytes4 indexed selector,
        bytes32 indexed family,
        uint32 version
    );
    event DeprecationSet(address indexed versionedProxy, bytes4 indexed selector, bool deprecated);

    // --------------------------------------------
    //  Errors
    // --------------------------------------------

    error NotExecutor(address caller);
    error ZeroAddress();
    error DelayOutOfBounds();

    // Cut validation errors
    error EmptyCutArray();
    error EmptySelectors(uint256 cutIndex);
    error ZeroFacet(uint256 cutIndex);
    error SelectorAlreadyRegistered(bytes4 selector, address existingFacet);
    error FirstVersionMustBeOne(bytes32 family, uint32 got);
    error VersionNotMonotonic(bytes32 family, uint32 got, uint32 expected);

    // Signature-parser errors (paths through _parseSignature)
    error EmptySignature(uint256 cutIndex, uint256 selectorIndex);
    error MissingOpenParen(uint256 cutIndex, uint256 selectorIndex);
    error MissingVersionDigits(uint256 cutIndex, uint256 selectorIndex);
    error MissingVSuffix(uint256 cutIndex, uint256 selectorIndex);
    error LeadingZeroInVersion(uint256 cutIndex, uint256 selectorIndex);
    error EmptyFamilyName(uint256 cutIndex, uint256 selectorIndex);
    error InvalidVersionZero(uint256 cutIndex, uint256 selectorIndex);

    // Proposal-lifecycle errors
    error ProposalAlreadyScheduled();
    error ProposalMissing();
    error ProposalNotReady();
    error ProposalAlreadyExecuted();
    error ProposalAlreadyCancelled();

    error ArrayLengthMismatch();

    // --------------------------------------------
    //  Initialisation
    // --------------------------------------------

    constructor(address _executor, uint256 _minDelay) {
        if (_executor == address(0)) revert ZeroAddress();
        if (_minDelay < MIN_DELAY_BOUND || _minDelay > MAX_DELAY_BOUND) revert DelayOutOfBounds();

        executor = _executor;
        minDelay = _minDelay;
    }

    // Ownable.sol might be better. Just set the owner as the multisig.
    // Orchestrator is best kept for market deployments, migrations, and discontinuations.
    // VersionedProxyAdmin then has additional protections in place for versioning and other admin actions.
    modifier onlyExecutor() {
        if (msg.sender != executor) revert NotExecutor(msg.sender);
        _;
    }

    // --------------------------------------------
    //  Cut lifecycle (timelocked)
    // --------------------------------------------

    /// @notice Deterministic identifier for a queued versioned cut. The
    ///         versionedProxy address is mixed into the hash so that the same
    ///         cut payload targeted at different proxies yields different
    ///         ids. The signature strings are part of the encoded payload,
    ///         so any change to a function name invalidates the prior id.
    function hashProposal(
        address versionedProxy,
        VersionedFacetCut[] calldata cuts,
        address init,
        bytes calldata initData,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(versionedProxy, cuts, init, initData, salt));
    }

    /// @notice Queue an append-only versioned cut against a specific versionedProxy.
    ///         Each signature is parsed, verified to match the required
    ///         `<family>V<version>(...)` shape, and checked against the
    ///         target versionedProxy's existing selector map and metadata registry.
    function schedule(
        address versionedProxy,
        VersionedFacetCut[] calldata cuts,
        address init,
        bytes calldata initData,
        bytes32 salt
    ) external onlyExecutor returns (bytes32 id) {
        if (versionedProxy == address(0)) revert ZeroAddress();
        _validateAndParse(versionedProxy, cuts);

        id = hashProposal(versionedProxy, cuts, init, initData, salt);
        Proposal storage p = proposals[id];
        if (p.earliestExecution != 0) revert ProposalAlreadyScheduled();

        // casting to 'uint64' is safe because block.timestamp + MAX_DELAY_BOUND (30 days)
        // is many orders of magnitude below 2^64 for the foreseeable future.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 eta = uint64(block.timestamp + minDelay);
        proposals[id] = Proposal({
            earliestExecution: eta,
            executed: false,
            cancelled: false,
            versionedProxy: versionedProxy
        });

        emit Scheduled(versionedProxy, id, eta);
    }

    /// @notice Execute a previously-queued versioned cut once the delay has
    ///         elapsed. The cut is re-validated, the standard EIP-2535 cut
    ///         shape is reconstructed from the parsed signatures, and both
    ///         `diamondCut` and `setSelectorMetaBatch` are called in the
    ///         same transaction so selectors and their metadata are
    ///         registered atomically.
    function execute(
        address versionedProxy,
        VersionedFacetCut[] calldata cuts,
        address init,
        bytes calldata initData,
        bytes32 salt
    ) external onlyExecutor {
        bytes32 id = hashProposal(versionedProxy, cuts, init, initData, salt);
        Proposal storage p = proposals[id];

        if (p.earliestExecution == 0) revert ProposalMissing();
        if (p.cancelled) revert ProposalAlreadyCancelled();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp < p.earliestExecution) revert ProposalNotReady();

        (
            IDiamondCut.FacetCut[] memory standardCuts,
            bytes4[] memory allSelectors,
            bytes32[] memory allFamilies,
            uint32[] memory allVersions
        ) = _validateAndParse(versionedProxy, cuts);

        p.executed = true;

        // 1) Register selectors via the standard EIP-2535 cut.
        IDiamondCut(versionedProxy).diamondCut(standardCuts, init, initData);

        // 2) Register version metadata for each newly-added selector. Any
        //    revert here (e.g. LibDiamond's monotonicity check fails) unwinds
        //    the whole transaction, rolling back the cut as well.
        IGovernanceFacet(versionedProxy).setSelectorMetaBatch(allSelectors, allFamilies, allVersions);

        emit Executed(versionedProxy, id);
    }

    /// @notice Cancel a pending cut before it is executed. The target versionedProxy
    ///         is recovered from the stored proposal so off-chain consumers
    ///         can filter cancellations by versionedProxy.
    function cancel(bytes32 id) external onlyExecutor {
        Proposal storage p = proposals[id];
        if (p.earliestExecution == 0) revert ProposalMissing();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (p.cancelled) revert ProposalAlreadyCancelled();

        p.cancelled = true;
        emit Cancelled(p.versionedProxy, id);
    }

    // --------------------------------------------
    //  Pause / unpause (immediate)
    // --------------------------------------------

    function pauseSelectors(address versionedProxy, bytes4[] calldata selectors) external onlyExecutor {
        if (versionedProxy == address(0)) revert ZeroAddress();
        IGovernanceFacet(versionedProxy).pauseSelectors(selectors);
        emit Paused(versionedProxy, selectors);
    }

    function unpauseSelectors(address versionedProxy, bytes4[] calldata selectors) external onlyExecutor {
        if (versionedProxy == address(0)) revert ZeroAddress();
        IGovernanceFacet(versionedProxy).unpauseSelectors(selectors);
        emit Unpaused(versionedProxy, selectors);
    }

    // --------------------------------------------
    //  Freeze (one-way, immediate)
    // --------------------------------------------

    function freeze(address versionedProxy) external onlyExecutor {
        if (versionedProxy == address(0)) revert ZeroAddress();
        IGovernanceFacet(versionedProxy).freeze();
        emit Frozen(versionedProxy);
    }

    // --------------------------------------------
    //  Metadata / deprecation (immediate)
    // --------------------------------------------

    function setSelectorDeprecated(
        address versionedProxy,
        bytes4 selector,
        bool deprecated
    ) external onlyExecutor {
        if (versionedProxy == address(0)) revert ZeroAddress();
        IGovernanceFacet(versionedProxy).setSelectorDeprecated(selector, deprecated);
        emit DeprecationSet(versionedProxy, selector, deprecated);
    }

    // --------------------------------------------
    //  Admin (executor-only)
    // --------------------------------------------

    function setMinDelay(uint256 newDelay) external onlyExecutor {
        if (newDelay < MIN_DELAY_BOUND || newDelay > MAX_DELAY_BOUND) revert DelayOutOfBounds();
        minDelay = newDelay;
        emit DelayUpdated(newDelay);
    }

    // --------------------------------------------
    //  Signature parsing + validation
    // --------------------------------------------

    /// @dev Parses and validates every signature in `cuts` against the target
    ///      versionedProxy's current state. Returns the derived EIP-2535 FacetCut[]
    ///      plus flat arrays of (selector, family, version) ready to be
    ///      forwarded to the versionedProxy's `setSelectorMetaBatch`.
    ///
    ///      Invariants enforced:
    ///        * `cuts.length >= 1`, each cut has a non-zero facet and at least
    ///          one selector.
    ///        * Each signature matches `<familyName>V<version>(...)` with
    ///          `familyName` non-empty, `version >= 1`, no leading zeros.
    ///        * The derived selector is not already registered on the versionedProxy.
    ///        * The derived version is `1` if the family is fresh, or
    ///          `latestInFamily(family).version + 1` otherwise, taking into
    ///          account any prior entries processed within this same cut.
    function _validateAndParse(
        address versionedProxy,
        VersionedFacetCut[] calldata cuts
    )
        internal
        view
        returns (
            IDiamondCut.FacetCut[] memory standardCuts,
            bytes4[] memory allSelectors,
            bytes32[] memory allFamilies,
            uint32[] memory allVersions
        )
    {
        uint256 cutsLen = cuts.length;
        if (cutsLen == 0) revert EmptyCutArray();

        IDiamondLoupe loupe = IDiamondLoupe(versionedProxy);
        IDiamondLoupeExt loupeExt = IDiamondLoupeExt(versionedProxy);

        // First pass: count total selectors for output-array sizing.
        uint256 totalSelectors;
        for (uint256 i; i < cutsLen; ) {
            VersionedFacetCut calldata c = cuts[i];
            if (c.facetAddress == address(0)) revert ZeroFacet(i);
            uint256 selLen = c.selectors.length;
            if (selLen == 0) revert EmptySelectors(i);
            totalSelectors += selLen;
            unchecked { ++i; }
        }

        standardCuts = new IDiamondCut.FacetCut[](cutsLen);
        allSelectors = new bytes4[](totalSelectors);
        allFamilies = new bytes32[](totalSelectors);
        allVersions = new uint32[](totalSelectors);

        uint256 flatIdx;
        for (uint256 i; i < cutsLen; ) {
            VersionedFacetCut calldata c = cuts[i];
            uint256 selLen = c.selectors.length;

            bytes4[] memory facetSelectors = new bytes4[](selLen);

            for (uint256 j; j < selLen; ) {
                (bytes4 selector, bytes32 family, uint32 version) = _parseSignature(
                    c.selectors[j].signature,
                    i,
                    j
                );

                // Not already enqueued earlier in this same batch. (The
                // versionedProxy hasn't seen any of these selectors yet at schedule
                // time; the loupe check below would only catch collisions
                // against *previously* registered selectors.)
                for (uint256 k; k < flatIdx; ) {
                    if (allSelectors[k] == selector) {
                        revert SelectorAlreadyRegistered(selector, c.facetAddress);
                    }
                    unchecked { ++k; }
                }

                // Not already registered on-chain.
                address existing = loupe.facetAddress(selector);
                if (existing != address(0)) revert SelectorAlreadyRegistered(selector, existing);

                // Monotonic version check. Covers both on-chain prior state
                // AND earlier entries within this same cut (in which case
                // the latest recorded will be in allSelectors/allVersions).
                uint32 expected = _expectedNextVersion(
                    loupeExt,
                    family,
                    allFamilies,
                    allVersions,
                    flatIdx
                );
                if (expected == 1) {
                    if (version != 1) revert FirstVersionMustBeOne(family, version);
                } else if (version != expected) {
                    revert VersionNotMonotonic(family, version, expected);
                }

                facetSelectors[j] = selector;
                allSelectors[flatIdx] = selector;
                allFamilies[flatIdx] = family;
                allVersions[flatIdx] = version;

                unchecked {
                    ++flatIdx;
                    ++j;
                }
            }

            standardCuts[i] = IDiamondCut.FacetCut({
                facetAddress: c.facetAddress,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: facetSelectors
            });

            unchecked { ++i; }
        }
    }

    /// @dev Determines the expected next version for `family`, considering
    ///      (a) the target versionedProxy's on-chain latestInFamily record, and
    ///      (b) any same-family entries already processed earlier in the
    ///      current cut (scanning backwards through allFamilies/allVersions).
    ///      Returns 1 if no prior record exists anywhere.
    function _expectedNextVersion(
        IDiamondLoupeExt loupeExt,
        bytes32 family,
        bytes32[] memory allFamilies,
        uint32[] memory allVersions,
        uint256 flatIdx
    ) internal view returns (uint32) {
        // Search within the current batch first, scanning backwards so that
        // a V1+V2+V3 sequence in a single cut is accepted.
        for (uint256 k = flatIdx; k > 0; ) {
            unchecked { --k; }
            if (allFamilies[k] == family) {
                return allVersions[k] + 1;
            }
        }
        // Otherwise consult the versionedProxy's persistent metadata.
        bytes4 latestSel = loupeExt.latestInFamily(family);
        if (latestSel == bytes4(0)) return 1;
        return loupeExt.selectorMeta(latestSel).version + 1;
    }

    /// @dev Parses a canonical function signature of the shape
    ///      `<familyName>V<version>(<argTypes>)` into its triple
    ///      `(selector, family, version)`. Reverts with a precise cause
    ///      when the signature does not match the required shape.
    ///
    ///      `cutIndex` and `selIndex` are forwarded into parse errors so
    ///      callers can locate the offending entry in a batch.
    function _parseSignature(
        string calldata signature,
        uint256 cutIndex,
        uint256 selIndex
    ) internal pure returns (bytes4 selector, bytes32 family, uint32 version) {
        bytes memory s = bytes(signature);
        uint256 sLen = s.length;
        if (sLen == 0) revert EmptySignature(cutIndex, selIndex);

        // 1. Find the first '('.
        uint256 parenPos = type(uint256).max;
        for (uint256 i; i < sLen; ) {
            if (uint8(s[i]) == 0x28) {
                parenPos = i;
                break;
            }
            unchecked { ++i; }
        }
        if (parenPos == type(uint256).max) revert MissingOpenParen(cutIndex, selIndex);

        // 2. Walk back from '(' to find the digit run.
        uint256 digitStart = parenPos;
        while (digitStart > 0) {
            uint8 b = uint8(s[digitStart - 1]);
            if (b < 0x30 || b > 0x39) break;
            unchecked { --digitStart; }
        }
        if (digitStart == parenPos) revert MissingVersionDigits(cutIndex, selIndex);

        // 3. Forbid leading zeros in multi-digit versions (deployV01 ≠ deployV1).
        if (parenPos - digitStart > 1 && uint8(s[digitStart]) == 0x30) {
            revert LeadingZeroInVersion(cutIndex, selIndex);
        }

        // 4. Parse digits into uint32.
        uint32 v;
        for (uint256 i = digitStart; i < parenPos; ) {
            v = v * 10 + uint32(uint8(s[i]) - 48);
            unchecked { ++i; }
        }
        if (v == 0) revert InvalidVersionZero(cutIndex, selIndex);
        version = v;

        // 5. Byte immediately before the digits must be 'V' (0x56).
        if (digitStart == 0 || uint8(s[digitStart - 1]) != 0x56) {
            revert MissingVSuffix(cutIndex, selIndex);
        }

        // 6. Family name = everything before the 'V'; must be non-empty.
        uint256 familyLen = digitStart - 1;
        if (familyLen == 0) revert EmptyFamilyName(cutIndex, selIndex);

        // 7. Hash the family-name slice in place (no extra memory allocation).
        bytes32 fHash;
        assembly ("memory-safe") {
            fHash := keccak256(add(s, 0x20), familyLen)
        }
        family = fHash;

        // 8. Selector is the first four bytes of keccak256 over the full signature.
        selector = bytes4(keccak256(s));
    }
}
