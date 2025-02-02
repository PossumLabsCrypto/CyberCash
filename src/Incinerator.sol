// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {CyberCash} from "src/CyberCash.sol";

error NotInitialized();
error ZeroAmount();
error ZeroAddress();

contract Incinerator {
    constructor(address _CyberCash) {
        if (_CyberCash == address(0)) revert ZeroAddress();
        cyberCash = CyberCash(_CyberCash);
    }

    // ============================================
    // ==              VARIABLES                 ==
    // ============================================
    CyberCash public cyberCash;

    // ============================================
    // ==              FUNCTIONS                 ==
    // ============================================
    ///@notice Send CASH between user and contract and send the burnScore to the user
    function burnLoop(uint256 _amount) public {
        if (cyberCash.liquidityPool() == address(0)) revert NotInitialized();
        if (_amount == 0) revert ZeroAmount();

        address from = msg.sender;
        uint256 amount = _amount;
        uint256 balance;
        uint256 burnScore;

        // Transfer CASH from the user to the contract
        cyberCash.transferFrom(from, address(this), amount);

        // Transfer CASH balance from the contract back to the user
        balance = cyberCash.balanceOf(address(this));
        cyberCash.transfer(from, balance);

        // Transfer burnScore from the contract to the user
        burnScore = cyberCash.burnScore(address(this));
        cyberCash.transferBurnScore(msg.sender, burnScore);
    }
}
