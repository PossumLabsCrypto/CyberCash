# Security review report
**Security Researcher:** (Mario Poneder)https://gist.github.com/MarioPoneder/870f6b1f150d402bc73798f98dd95631
**Project:** [`PossumLabsCrypto/CyberCash`](https://github.com/PossumLabsCrypto/CyberCash)   
**Commit:** [0f428ca479d43405b3e63722b88e25293d05e158](https://github.com/PossumLabsCrypto/CyberCash/commit/0f428ca479d43405b3e63722b88e25293d05e158)   
**Start Date:** 2025-02-01

**Scope:**
* `src/CyberCash.sol` (nSLOC: 114, coverage: 100% lines / 100% statements / 100% branches / 100% functions)
* `src/Migrator.sol` (nSLOC: 65, coverage: 100% lines / 100% statements / 100% branches / 100% functions)

**Overview**
* **[M-01]** Failure to transfer to burn-exempt addresses
* **[L-01]** Misleading `totalRewards` and `totalSupply` before initialization
* **[I-01]** Potentially insuffcient burn-exempt addresses for trading

---

## **[M-01]** Failure to transfer to burn-exempt addresses

### Description

The `balanceOf` method of the `CyberCash` contract represents scaled amounts which also include rewards that are not minted to the user yet.  
However, the `transfer`/`transferFrom` method operates on pure underlying amounts which do not include any unminted amounts. 

In case of regular transfers, this is not an issue since any outstanding rewards are minted on transfer when burning the transfer fees. Therefore, the scaled amount will always match the underlying amount at the time of a transfer.  
However, there can be burn-exempt addresses such as the liquidity pool where no burning and therefore no minting is performed on token transfer.

Consequently, transfers to burn-exempt addresses can be subject to an `ERC20: transfer amount exceeds balance` error, especially in case the full balance is transferred.

### Recommendation

It is recommended to mint outstanding rewards on transfer irrespective of the burn-exemption status.

**Status:**  
✅ Resolved in commit [0e93e2f902a2f4e85154d31101e30f1dddb76db7](https://github.com/PossumLabsCrypto/CyberCash/commit/0e93e2f902a2f4e85154d31101e30f1dddb76db7)


## **[L-01]** Misleading `totalRewards` and `totalSupply` before initialization

### Description

The `initialize` method of the `CyberCash` contract is meant to kick off the reward accrual / token inflation by setting `lastMintTime = block.timestamp`.  
However, the contract also intends to act as a normal non-accruing ERC20 token in the phase before initialization.  

While the `userRewards` method will always return zero in this phase and therefore the `balanceOf` method will correctly reflect the underlying balance, the `totalRewards` and `totalSupply` methods are already showing inflated values.  
Although this inflation is re-started at initialization, the inflated values of `totalRewards` and `totalSupply` in the first phase might be misleading for users.

### Recommendation

It is recommended to have `totalRewards` return zero and have `totalSupply` reflect the correct underlying balance in the first phase.

**Status:**  
✅ Resolved in commit [c6ac27970a17fc4e2e55db18554c53b60c9bc104](https://github.com/PossumLabsCrypto/CyberCash/commit/c6ac27970a17fc4e2e55db18554c53b60c9bc104)


## **[I-01]** Potentially insuffcient burn-exempt addresses for trading

### Description

Currently, only the migrator contract and the liquidity pool are burn-exempt to facilitate tax-free migration and trading. Furthermore, the `CyberCash` contract offers no possibility to add more burn-exempt addresses at initialization or in the future.

However, token trading typically does not solely involve transfers to and from a pool, but tokens are often looped through a router contract too which would be unintentionally subject to transfer fees again.

### Recommendation

Is recommended to allow setting more burn-exempt addresses at initialization or add a method that allows to add more burn-exempt addresses in the future.

**Status:**  
✅ Resolved in commit [ced8939ce075535864cd68d8362fac78d390d311](https://github.com/PossumLabsCrypto/CyberCash/commit/ced8939ce075535864cd68d8362fac78d390d311)