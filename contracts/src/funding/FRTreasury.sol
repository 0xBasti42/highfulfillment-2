1. calculates ePBR and FMV
2. commits scalars to beacons based on relative distance of mktPrice from FMV

ePBR = (crazy calc from AI chat)
FMV = mrk * FR

FR = (crazy calc that considers ((mCap/tCap || relativeUR*) && cmPBR/ctPBR) && converts into +/- multiplier we can apply to mrk)

*relativeUR = relative utilization rate.
What are the implications of comparing market health by utilization rate vs proportion of tcap?
- UR is locked circulating supply.
- mcap is (totalSupply x price).

mcap considers all tokens that have been bought from the pool using ETH. So if we're trying to peg an expected performance value
to mrk across all markets with a proportional multiplier (smoothed with SMA), mcap/tcap is probably most accurate for measuring
relative realtime liquidity of the actual AMMs. So we get two proportions:

1. mcap/tcap = market's proportion of tcap
2. cmPBR/ctPBR = cumulative market pbr / cumulative total pbr = market's proportion of PBR (prev EST).

So we need to find the optimal balance between these two, where the pools with biggest difference PrD = FMV - mrk get the most funding.

It's:

if ((mcap/tcap) > (cmPBR/ctPBR)) {
    - Funding rate is negative*
} else ((mcap/tcap) < (cmPBR/ctPBR)) {
    - Funding rate is positive*
} else (mcap/tcap == cmPBR/ctPBR) {
    - Funding rate is neutral (mkt == FMV)
}

*Funding rate distributes FRTreasury where distance from FMV is highest, but we discount OFFSIDE positions (e.g. if ((fr > 0) && (opn > fmv)) {countZero})

FR = (cmPBR/ctPBR) - (mcap/tcap)
-- Where market's proportion of tcap is higher than its proportion of PBR, it is overperforming so FR is negative.
-- Where market's proportion of tcap is lower than its proportion of PBR, it is underperforming so FR is positive.
-- If both are equal, FR is 0.

FMV = mrk * FR
-- mrk price multiplied by FundingRate to perpetually indicate whether a market is under/over priced.
-- 8 FMVs stored at a time, and 4 FMV blocks. FMV block = smoothed SMA value of 8 FMVs. Each subsequent datapoint replaces oldest FMV.

BCN = (FRT * 0.8) * (mPrD / tPrD)
-- mPrD = (FMV - mrk || mrk - FMV)
-- tPrD = sum(mPrD)
-- FRTreasury is distributed proportionally to all beacons based on their relative distance from FMV.

f = BCN * UPS
-- UPS = user position score = (uPL / mPL)
-- uPL = value of position at fmv - value of position at opn
-- Discount OFFSIDE positions (if ((fr > 0) && (opn > fmv)) {countZero})

Basically, the highest PNL positions then get highest funding in a given 60s period and the lowest PNL positions get the lowest. And. 
Positions always earn the aggregate of their 60s values, smoothed out over an 8-min period. Or.
All positions earn either 0 or (1 * uPL/mPL)

What about depegs?

- This should just increase the size of the payment for the depegged asset. And it's always relative to tcap. So it's a macro liquidity scan.

Remember:

Can always use Chainlink Functions for simpler data collection vs onchain loops & multicalls.