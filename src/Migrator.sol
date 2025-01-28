// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error NotOwner();
error ZeroAddress();
error ZeroAmount();
error TokenNotAllowed();
error IsAllowed();
error AlreadySet();
error InvalidRatio();
error NoBalanceAvailable();

///@title The Migrator enables migration from a standard ERC20 token to CASH if listed
///@author Possum Labs
/**
 * @notice This contract allows anyone to migrate a listed token to CASH at a specific ratio
 * The main purpose is to migrate PSM, a standard ERC20 token to CASH
 * Enabling the migration of other tokens of external communities may be evaluated at some point
 * If this was the case, the respective tokens will be inspected for non-standard behaviour
 * This contract is supposed to work only with standard ERC20 tokens
 */
contract Migrator {
    constructor(address _owner) {
        owner = _owner;
    }

    // ============================================
    // ==              VARIABLES                 ==
    // ============================================
    using SafeERC20 for IERC20;

    address public owner;
    IERC20 public cyberCash;

    mapping(address token => bool canMigrate) private allowedTokens;
    mapping(address token => uint256 cashPerToken) private ratios;
    uint256 private constant RATIO_PRECISION = 1000;

    // ============================================
    // ==                EVENTS                  ==
    // ============================================
    event TokenMigrationAdded(address indexed token, uint256 ratio, bool indexed canMigrate);
    event TokenMigrated(address indexed user, address indexed token, uint256 amountIn, uint256 cashOut);

    // ============================================
    // ==              FUNCTIONS                 ==
    // ============================================
    ///@notice Allow the owner to set the address of CyberCash
    ///@dev Prevent setting the zero address or setting the address multiple times
    function setCashAddress(address _cash) external {
        if (msg.sender != owner) revert NotOwner();
        if (_cash == address(0)) revert ZeroAddress();
        if (address(cyberCash) != address(0)) revert AlreadySet();

        cyberCash = IERC20(_cash);
    }

    ///@notice Allow the owner to add new tokens for migration and set the migration ratio
    ///@dev Tokens cannot be delisted
    ///@dev Ratios cannot be changed afterwards
    function addTokenMigration(address _token, uint256 _cashPer1000Token) external {
        if (msg.sender != owner) revert NotOwner();
        if (_token == address(0)) revert ZeroAddress();
        if (_cashPer1000Token == 0) revert InvalidRatio();
        if (allowedTokens[_token] == true) revert IsAllowed();

        allowedTokens[_token] = true;
        ratios[_token] = _cashPer1000Token;

        emit TokenMigrationAdded(_token, _cashPer1000Token, true);
    }

    ///@notice Enable users to migrate a listed token to CASH
    ///@dev If insufficient CASH is available, send the matching amount proportionally
    function migrate(address _token, uint256 _amount) external {
        if (!allowedTokens[_token]) revert TokenNotAllowed();
        if (_amount == 0) revert ZeroAmount();

        uint256 balanceCASH = cyberCash.balanceOf(address(this));
        if (balanceCASH == 0) revert NoBalanceAvailable();

        // Get the tokens to transfer from and to the user
        (uint256 spendToken, uint256 receivedCash) = migrationResult(_token, _amount);

        // Send the tokens
        IERC20(_token).safeTransferFrom(msg.sender, address(this), spendToken);
        cyberCash.transfer(msg.sender, receivedCash);

        emit TokenMigrated(msg.sender, _token, spendToken, receivedCash);
    }

    ///@notice Return if a token can be exchanged for CASH
    function canMigrate(address _token) external view returns (bool) {
        return allowedTokens[_token];
    }

    ///@notice Simulate the migration of a token to CASH
    ///@dev If insufficient CASH is available, return the spending amount and proportional CASH received
    function migrationResult(address _token, uint256 _amountIn)
        public
        view
        returns (uint256 spendAmount, uint256 receivedAmount)
    {
        // Return 0,0 if the token is not listed for migration
        if (allowedTokens[_token]) {
            uint256 balanceCASH = cyberCash.balanceOf(address(this));
            uint256 ratio = ratios[_token];

            uint256 requestedCash = (_amountIn * ratio) / RATIO_PRECISION;

            receivedAmount = (requestedCash < balanceCASH) ? requestedCash : balanceCASH;
            spendAmount = (requestedCash < balanceCASH) ? _amountIn : (_amountIn * balanceCASH) / requestedCash;
        }
    }
}
