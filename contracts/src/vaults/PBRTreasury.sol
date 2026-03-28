1. PBRTreasury calls PlayerVault to snapshot user stTOKEN balances for (s / S) at startTime

2. PBRTreasury fetches final points values from PlayerVault stores, 2hrs after final match is played (m / M_adj)
   which is when endTime has passed

3. Scalars can then be committed by calling PBRTreasury until batches / list is done

State machine:
- if (startTime < currentTime && currentTime > endTime) {
    snapshot stTOKEN balances by calling all playerVault addresses
}

- if (startTime < currentTime && endTime <= currentTime) {
    if (!pointsCollected) {
        collect points from all PlayerVault stores
        - can either do this with Chainlink Functions offchain runner
        - or by exposing just final points value on each vault and summing them up
    } else {
        commit scalars to PlayerVaults until completion
    }
}