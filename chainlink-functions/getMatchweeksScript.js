// =============================================================================
//  getMatchweeksScript.js
// -----------------------------------------------------------------------------
//  Chainlink Functions DON script for `Matchweeks.sol#scan`.
//
//  Pipeline:
//    1. Fetch the latest Premier League matchweek schedule from a data provider.
//    2. Format the upstream response into a normalized shape.
//    3. Read `currentSeason` and bulk-read all of that season's matchweeks via
//       two `eth_call`s (one bulk view replaces a 38-element JSON-RPC batch).
//    4. Diff fresh vs. stored values and keep only entries whose startTime
//       or endTime has changed.
//    5. Pack the changes into the wire format expected by the contract and
//       return as a Uint8Array.
//
//  Wire format returned to `Matchweeks._fulfillRequest` (17 bytes per entry):
//    [0]      uint8  matchweekNumber
//    [1..8]   uint64 startTime  (big-endian unix seconds)
//    [9..16]  uint64 endTime    (big-endian unix seconds)
// =============================================================================

// -----------------------------------------------------------------------------
//  Constants
// -----------------------------------------------------------------------------

// TODO: replace with the deployed Matchweeks contract address (same chain as the DON consumer).
const MATCHWEEKS_CONTRACT_ADDRESS = "0x0000000000000000000000000000000000000000";

// keccak256("getMatchweeksForSeason(uint16)")[0:4] — bulk season getter.
// TODO: precompute and replace this placeholder.
const GET_SEASON_SELECTOR = "0x00000000";

// keccak256("currentSeason()")[0:4] — auto-generated public state getter.
// TODO: precompute and replace this placeholder.
const CURRENT_SEASON_SELECTOR = "0x00000000";

// ABI tuple shape returned by `getMatchweeksForSeason`. Mirrors the on-chain
// `Matchweek` struct after the slot-packing reorder.
const MATCHWEEK_TUPLE = "tuple(uint16 seasonStartYear, uint8 matchweekNumber, uint8 status, uint256 startTime, uint256 endTime)";

// -----------------------------------------------------------------------------
//  1. Fetch latest matchweek schedule from the data provider
// -----------------------------------------------------------------------------

// TODO: replace with the actual Premier League fixtures/schedule API endpoint.
// API key (if needed) should be supplied via DON-hosted `secrets`.
const apiResponse = await Functions.makeHttpRequest({
    url: "https://api.example.com/premier-league/matchweeks",
    method: "GET",
    headers: {
        // TODO: e.g. "x-api-key": secrets.PL_API_KEY
    },
});

if (apiResponse.error) {
    throw Error("Upstream API request failed");
}

// -----------------------------------------------------------------------------
//  2. Normalize API response
// -----------------------------------------------------------------------------
//
//  Output shape: Array<{ matchweekNumber: number, startTime: number, endTime: number }>
//  - matchweekNumber: 1..38
//  - startTime/endTime: unix seconds (number, fits in uint64)
//
const latest = formatMatchweeks(apiResponse.data);

// -----------------------------------------------------------------------------
//  3. Read current season + bulk-read all matchweeks via JSON-RPC
// -----------------------------------------------------------------------------

// RPC URL is supplied via DON-hosted secrets so it can be rotated without redeploy.
const rpcUrl = secrets.RPC_URL;

// 3a. Fetch `currentSeason` from the contract so the script tracks season transitions
// without redeploy. The contract applies oracle updates against `currentSeason` too,
// so the script must read the same key the contract will use.
const seasonResponse = await Functions.makeHttpRequest({
    url: rpcUrl,
    method: "POST",
    headers: { "Content-Type": "application/json" },
    data: {
        jsonrpc: "2.0",
        id: 0,
        method: "eth_call",
        params: [
            { to: MATCHWEEKS_CONTRACT_ADDRESS, data: CURRENT_SEASON_SELECTOR },
            "latest",
        ],
    },
});

if (seasonResponse.error) {
    throw Error("currentSeason RPC call failed");
}

const currentSeason = Number(ethers.BigNumber.from(seasonResponse.data.result));

// 3b. Bulk-read all matchweeks for `currentSeason` in a single eth_call. This is
// substantially cheaper than a 38-element JSON-RPC batch — one HTTP envelope, one
// EVM simulation, ~3.7 KB response vs. ~10.5 KB across 38 envelopes.
const seasonCalldata = GET_SEASON_SELECTOR + ethers.utils.defaultAbiCoder.encode(["uint16"], [currentSeason]).slice(2);

const seasonRead = await Functions.makeHttpRequest({
    url: rpcUrl,
    method: "POST",
    headers: { "Content-Type": "application/json" },
    data: {
        jsonrpc: "2.0",
        id: 1,
        method: "eth_call",
        params: [
            { to: MATCHWEEKS_CONTRACT_ADDRESS, data: seasonCalldata },
            "latest",
        ],
    },
});

if (seasonRead.error) {
    throw Error("getMatchweeksForSeason RPC call failed");
}

const [storedMatchweeks] = ethers.utils.defaultAbiCoder.decode(
    [`${MATCHWEEK_TUPLE}[]`],
    seasonRead.data.result,
);

// -----------------------------------------------------------------------------
//  4. Diff fresh vs. stored
// -----------------------------------------------------------------------------

// `matchweekNumber === 0` means the slot has never been `add()`-ed by the orchestrator
// (shouldn't happen post-construction, but defensive). The contract's `_editTimes`
// silently skips those anyway, so we mirror that here to avoid wasted wire bytes.
const stored = new Map();
for (const m of storedMatchweeks) {
    const matchweekNumber = Number(m.matchweekNumber);
    if (matchweekNumber === 0) continue;
    stored.set(matchweekNumber, {
        startTime: Number(m.startTime),
        endTime: Number(m.endTime),
    });
}

const changes = [];
for (const m of latest) {
    const current = stored.get(m.matchweekNumber);
    if (!current) continue;
    if (current.startTime !== m.startTime || current.endTime !== m.endTime) {
        changes.push(m);
    }
}

// -----------------------------------------------------------------------------
//  5. Pack changes into the contract wire format
// -----------------------------------------------------------------------------

const buffer = new Uint8Array(changes.length * 17);
for (let i = 0; i < changes.length; i++) {
    const c = changes[i];
    const off = i * 17;
    buffer[off] = c.matchweekNumber & 0xff;
    writeUint64BE(buffer, off + 1, c.startTime);
    writeUint64BE(buffer, off + 9, c.endTime);
}

return buffer;

// -----------------------------------------------------------------------------
//  Helpers
// -----------------------------------------------------------------------------

function writeUint64BE(buf, offset, value) {
    let v = BigInt(value);
    for (let i = 7; i >= 0; i--) {
        buf[offset + i] = Number(v & 0xffn);
        v >>= 8n;
    }
}

// TODO: implement once the upstream API shape is finalized.
// Map the provider's matchweek schedule to:
//   [{ matchweekNumber, startTime, endTime }, ...]
// where startTime/endTime are unix seconds. Filter to entries belonging to
// `currentSeason` (the variable in scope above) so cross-season data from the
// upstream API never leaks into the diff.
function formatMatchweeks(_apiData) {
    return [];
}
