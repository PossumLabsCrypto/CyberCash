// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

error InsufficientBurnScore();
error NotInitialized();
error NotOwner();
error ProhibitedAddress();
error ZeroAddress();
error ZeroAmount();

contract CyberCash is ERC20, ERC20Permit {
    constructor(string memory name, string memory symbol, address _owner) ERC20(name, symbol) ERC20Permit(name) {
        if (_owner == address(0)) revert ZeroAddress();

        owner = _owner;
        lastMintTime = block.timestamp;
        _mint(owner, INITIAL_SUPPLY);

        // Set exemptions for DEX router contracts
        // Uniswap
        exemptedAddresses[0x4C60051384bd2d3C01bfc845Cf5F4b44bcbE9de5] = true; //  UniversalRouter
        exemptedAddresses[0xeC8B0F7Ffe3ae75d7FfAb09429e3675bb63503e4] = true; //  UniversalRouterV1_2
        exemptedAddresses[0x5E325eDA8064b456f4781070C0738d849c824258] = true; //  UniversalRouterV1_2_V2Support

        exemptedAddresses[0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32] = true; //  V4 PoolManager
        exemptedAddresses[0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869] = true; //  V4 PositionManager

        // Odos
        exemptedAddresses[0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13] = true; // Smart Order Routing
        exemptedAddresses[0x7432657cDda02226ac2aAc9d8f552Ee9613B064e] = true; // Limit Order Contracts

        // Paraswap
        exemptedAddresses[0x6A000F20005980200259B80c5102003040001068] = true; // Augustus v6.2

        // Kyberswap
        exemptedAddresses[0x6131B5fae19EA4f9D964eAc0408E4408b66337b5] = true; // MetaAggregationRouterV2
        exemptedAddresses[0xcab2FA2eeab7065B45CBcF6E3936dDE2506b4f6C] = true; // DSLOProtocol
        exemptedAddresses[0x227B0c196eA8db17A665EA6824D972A64202E936] = true; // LimitOrderProtocol

        // 0x
        exemptedAddresses[0xDef1C0ded9bec7F1a1670819833240f027b25EfF] = true; // ExchangeProxy
        exemptedAddresses[0xdB6f1920A889355780aF7570773609Bd8Cb1f498] = true; // ExchangeProxy Flash Wallet

        // 1Inch
        exemptedAddresses[0x1111111254EEB25477B68fb85Ed929f73A960582] = true; // Aggregation Router V5

        // Cow.fi
        exemptedAddresses[0x9008D19f58AAbD9eD0D60971565AA8510560ab41] = true; // GPv2 Settlement

        // OpenOcean - TBD
    }

    // ============================================
    // ==              VARIABLES                 ==
    // ============================================
    address public owner;
    address public liquidityPool;

    uint256 private constant INITIAL_SUPPLY = 1e28; // 10 billion
    uint256 private constant RESERVE_BUFFER = 1e9; // Token reserve in the LP that cannot be burned
    uint256 private constant REWARD_PRECISION = 1e18;

    uint256 public constant MINT_PER_SECOND = 31709791983764586504; // 1 bn tokens p.a. (365 days)
    uint256 public constant BURN_ON_TRANSFER = 5; // 0.5%
    uint256 public constant BURN_FROM_LP = 2; // 0.2%
    uint256 public constant BURN_PRECISION = 1000;

    mapping(address specialAddress => bool exempted) private exemptedAddresses; // addresses that don't cause burns (from & to)

    uint256 public rewardsPerTokenBurned; // scaled up by REWARD_PRECISION
    mapping(address user => uint256 rewards) private userRewardsPerTokenBurned; // scaled up by REWARD_PRECISION

    uint256 public lastMintTime;
    uint256 public pendingMints;

    uint256 public totalBurned = 1;
    mapping(address user => uint256 burned) public burnScore;

    // ============================================
    // ==                EVENTS                  ==
    // ============================================
    event RewardsClaimed(address indexed user, uint256 amount);
    event BurnedTokensFromLP(uint256 amount);

    // ============================================
    // ==            NEW FUNCTIONS               ==
    // ============================================
    ///@notice Set the address of the liquidity pool and migrator. Revoke owner.
    function initialize(address _poolAddress, address _migratorAddress) public {
        if (msg.sender != owner) revert NotOwner();
        if (_poolAddress == address(0)) revert ZeroAddress();
        if (_migratorAddress == address(0)) revert ZeroAddress();

        // Enable tax free transfers involving the LP and migrator
        exemptedAddresses[_poolAddress] = true;
        exemptedAddresses[_migratorAddress] = true;

        // Set the LP address
        liquidityPool = _poolAddress;

        // Reset the starting point of inflation to reduce overestimation of supply
        lastMintTime = block.timestamp;

        // Revoke the owner
        owner = address(0);
    }

    ///@notice Calculate the mintable rewards of the system since the last claim (transaction)
    function totalRewards() private view returns (uint256 mintable) {
        if (owner == address(0)) mintable = MINT_PER_SECOND * (block.timestamp - lastMintTime);
    }

    ///@notice Calculate the pending rewards of a user
    function userRewards(address _user) private view returns (uint256 rewards) {
        uint256 addedRewards = totalRewards();
        uint256 simulatedRewardsPerTokenBurned = rewardsPerTokenBurned + (addedRewards * REWARD_PRECISION) / totalBurned;

        rewards =
            (burnScore[_user] * (simulatedRewardsPerTokenBurned - userRewardsPerTokenBurned[_user])) / REWARD_PRECISION;
    }

    ///@notice Allow users to transfer burnScore between addresses except
    ///@dev Prevent sending burnScore to the LP and migrator (exempted addresses)
    function transferBurnScore(address _to, uint256 _amount) external {
        address from = _msgSender();
        uint256 balance = burnScore[from];

        if (_to == address(0)) revert ZeroAddress();
        if (exemptedAddresses[_to]) revert ProhibitedAddress();
        if (_amount == 0) revert ZeroAmount();
        if (_amount > balance) revert InsufficientBurnScore();

        // Mint the pending tokens of the sender & receiver (update userRewardsPerTokenBurned)
        mintRewards(from);
        mintRewards(_to);

        // reduce the sender's burn score
        burnScore[from] -= _amount;

        // increase the recipient's burn score
        burnScore[_to] += _amount;
    }

    ///@notice Burn the transfer tax and tokens from the LP
    ///@dev This function is triggered by all transfer types
    ///@dev Burn some tokens from the transaction and from the liquidity pool
    ///@dev Only called if the sender or receiver is not the liquidity pool
    ///@dev This avoids burnScore accruing to the LP
    function burnOnTransfer(address _sender, uint256 _amount) private returns (uint256 sendAmount) {
        // Get the token amount in the liquidity pool, reduced by the reserve buffer
        uint256 pooledAmount = this.balanceOf(liquidityPool);
        uint256 canBurnFromLP = (pooledAmount > RESERVE_BUFFER) ? pooledAmount - RESERVE_BUFFER : 0;

        // Calculate burn amounts
        uint256 burnedFromTx = (_amount * BURN_ON_TRANSFER) / BURN_PRECISION;
        uint256 burnedFromLP = (_amount * BURN_FROM_LP) / BURN_PRECISION;

        // Ensure there is always a reserve in the LP after burning (prevent R1 = 0 in AMM)
        burnedFromLP = (canBurnFromLP > burnedFromLP) ? burnedFromLP : canBurnFromLP;

        // Calculate & return the remaining amount of the transaction
        sendAmount = _amount - burnedFromTx;

        // Burn the tokens
        _burn(_sender, burnedFromTx);
        _burn(liquidityPool, burnedFromLP);

        // increase the burn tracker by the tx burn amount (individual and global)
        totalBurned += burnedFromTx;
        burnScore[_sender] += burnedFromTx;

        // emit event
        emit BurnedTokensFromLP(burnedFromLP);
    }

    ///@notice Mint the pending token rewards to the user
    ///@dev This function is triggered by all transfer types
    ///@dev Mint rewards to the user and update tracking variables
    function mintRewards(address _account) public {
        // mint claimable rewards to the user
        uint256 rewards = userRewards(_account);
        _mint(_account, rewards);

        // Update the rewards tracker (individual and global)
        uint256 addedRewards = totalRewards();
        rewardsPerTokenBurned += (addedRewards * REWARD_PRECISION) / totalBurned;
        userRewardsPerTokenBurned[_account] = rewardsPerTokenBurned;
        pendingMints = (pendingMints + addedRewards) - rewards;

        // Update the mint timestamp
        lastMintTime = block.timestamp;

        // emit event
        emit RewardsClaimed(_account, rewards);
    }

    // ============================================
    // ==        OVERRIDE ERC20 FUNCTIONS        ==
    // ============================================
    /// @notice Overrides the account balances to reflect time/burn-based increase
    ///@dev Show users their available balance via the standard interface
    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account) + userRewards(account);
    }

    /// @notice Overrides the total supply to reflect time-based increase
    ///@dev Return the sum of minted & burned (physical) tokens and potentially minted tokens
    function totalSupply() public view override returns (uint256) {
        return (super.totalSupply() + pendingMints + totalRewards());
    }

    ///@notice Adjusted Transfer function to send tokens
    ///@dev Claim pending rewards to the user's wallet
    ///@dev Burn a percentage of the transaction amount
    ///@dev Burn a percentage of amount from the liquidity pool
    function transfer(address _to, uint256 _amount) public override returns (bool) {
        address from = _msgSender();

        // Only check for burns & rewards after initialisation, otherwise normal ERC20 functionality
        if (liquidityPool != address(0)) {
            // mint rewards to sender
            mintRewards(from);

            // Execute burns, state updates and mint rewards
            // Skip if sender or receiver is liquidity pool or migrator
            // Enable tax free trading and migration
            if (!exemptedAddresses[from] && !exemptedAddresses[_to]) {
                _amount = burnOnTransfer(from, _amount);
            }
        }

        // send the tokens
        _transfer(from, _to, _amount);

        return true;
    }

    ///@notice Adjusted TransferFrom function to send tokens on behalf of a user
    ///@dev Claim pending rewards to the user's wallet
    ///@dev Burn a percentage of the transaction amount
    ///@dev Burn a percentage of amount from the liquidity pool
    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(_from, spender, _amount);

        // Only check for burns & rewards after initialisation, otherwise normal ERC20 functionality
        if (liquidityPool != address(0)) {
            // mint rewards to sender
            mintRewards(_from);

            // Execute burns, state updates and mint rewards
            // Skip if sender or receiver is liquidity pool or migrator
            // Enable tax free trading and migration
            if (!exemptedAddresses[_from] && !exemptedAddresses[_to]) {
                _amount = burnOnTransfer(_from, _amount);
            }
        }

        // send the tokens
        _transfer(_from, _to, _amount);

        return true;
    }
}
