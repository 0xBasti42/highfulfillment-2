1. converts collateral into ETH or playerToken (with reduced fees), locks the amount, and tracks open positions
2. enables users to earn funding for every minute that their position was ONSIDE, proportionally to their total of 
   pTOKENUP/pTOKENDOWN supply (depends if mPrD was +/-)
3. stores owed funding in Positions struct and accumulates if unclaimed, like in PlayerVaults. min-by-min rate per 8-min block*.

*FMV = mrk * FR, taken every 60s. Block = sma(FMVs[]). Store four blocks (32 FMVs) per market only. Distribute FRTreasury to PositionManager
beacons proportionally, according to their relative distance from mrk (doesn't matter whether it's positive or negative). User balances of 
pTOKENUP and pTOKENDOWN are snapshotted upon receipt of ETH (min 60s cooldown) and they are provided ONSIDE/OFFSIDE funding for that 60s period,
proportionally to their share of the total pTOKENUP/pTOKENDOWN tokens that have been minted.

So all PositionManager beacons receive funding, even if there are no open positions. The FRTreasury just gets automatically committed to the
beacons based on the market's relative distance from FMV and based on trading volumes in the current 8-min window. Ergo: a moving average is
always taken during the 8-min distribution windows. Where each beacon's positions get proportional yield to the beacon's share every 60s, but
the total is only distributed at slot7, which averages out the distribution.

FRTreasury only ever distributes 80% of the ETH, which means that it should just get bigger over time. No. It just averages out the upside and
downside. Collects when trading volumes are rising, spends when trading volumes are falling. Just evens out the distributions.

1. snapshots TOKENUP/TOKENDOWN balances every 60s, and tracks uPNL against latest smoothedFMV
2. stores funding by-the-position
3. automatically pays funding to users when a position is closed

f = BCN * UPS
-- BCN = (FRT * 0.8) * (mPrD / tPrD) // most distance gets the highest proportion
-- UPS = uPL / mPL // most distance to FMV gets the highest proportion*

uPL = FMV - opn
mPL = 1 + sum(uPNL_adj)
-- Discount OFFSIDE positions (if ((direction == BUY) && (opn > fmv)) {countZero})
-- Splits beacon funding between all open positions, proportionally according to their share of marketPNL

*What are the implications of most distance getting highest proportion?
- BCN always earns.
- Positions earn either 0 or (1 * uPL/mPL)

- Positions with highest nominal PNL would get highest share of BCN.
- Nominal PNL factors in both distance from FMV and position size.
- uPL/mPL is proportional to total nominal PNL in the market.

So. FRTreasury gets distributed proportionally to the bps distance of each marketPrice from fairMarketValue.
And. BCN rewards get distributed proportionally to userPositionScore, which is usrProfit/mktProfit.

So users get paid yield in return for locking up capital, offering perpetual arbitrage between markets to rebalance relative
market caps according to real world performance levels.

Do we want that? What about for young players etc.? It would keep them cheaper and enable early investment opportunities at low prices.