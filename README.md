## CyberCash

**CyberCash is a digital currency that pays rewards for using it.**

CyberCash consists of three mechanisms:

-   **Dual burn on transfer**: Every transfer reduces CASH supply and increases its price.
-   **Fixed inflation**: The supply of CyberCash expands by a fixed amount each second.
-   **Passive Income**: Users receive their share of the inflation as passive income depending on their activity.


## Dual burn on transfer
When user A sends 1000 CASH to user B, 10 CASH are burned (1%) and user B receives 990 CASH.
At the same time, additional 5 CASH (0.5%) are burned from the liquidity pool.
Reducing the CASH reserve inside the liquidity pool automatically increases the price of CASH relative to the paired asset.
This is due to the constant product formula used for pricing in Automated Market Makers such as Uniswap.

As a result, every transaction between users increases the price of CASH irrespective of market activity.
Transfers to and from the liquidity pool are exempt from any burn to avoid additional slippage and complexities of routing middleware.


## Fixed inflation
A fixed amount of new CASH can be minted every second.
Per year (365 days) a total of 1 billion new CASH is created and distributed.
The starting supply is 10 billion CASH.

## Universal Passive Income (UPI)
The newly minted tokens from inflation accrue to CASH users.
The 1% transaction burn when sending CASH is tracked for every address.
Users receive their proportional share of the inflation depending on their proportional amount of burned tokens.
This passive income continues in perpetuity.
If users become inactive, their relative share of the inflation reduces over time because others continue to burn more tokens while transacting.
This incentivizes real and sustained usage of the currency.


