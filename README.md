## CyberCash

**CyberCash is a digital currency that pays its users.**

*Contract Address (Arbitrum One):* 0x7938FdfB552000C6A033FE5787F06010cb75F04B

CyberCash is built on three core mechanisms:

-   **Dual burn on transfer**: Every transfer reduces CASH supply and increases its price.
-   **Fixed inflation**: The supply of CyberCash expands by a fixed amount each second.
-   **Passive Income**: Users receive their share of the inflation as passive income depending on their activity.


## Dual burn on transfer
When user A sends 1000 CASH to user B, 5 CASH are burned (0.5%) and user B receives 995 CASH.
At the same time, additional 2 CASH (0.2%) are burned from the liquidity pool.
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
The transaction burn when sending CASH is tracked for every address.
Users receive their proportional share of the inflation depending on their proportional amount of burned tokens.
This passive income continues in perpetuity.
If users become inactive, their relative share of the inflation reduces over time because others continue to burn more tokens while transacting.
This incentivizes real and sustained usage of the currency.


## Transferable burn score
The burn score can be transfered between any address.
However, the transfer must be initiated by the address owning the burn score directly (no transferFrom).
The intention of the burn score is that it is user owned and not treated as a transferable commodity.
Enabling a one-sided transfer logic allows users to move their burn score between wallets without accidentally losing control over it via approvals & transferFrom.

