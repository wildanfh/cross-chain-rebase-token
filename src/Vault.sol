// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    // Core Requirements:
    // 1. Store the address of the RebaseToken contract (passed in constructor).
    // 2. Implement a deposit function:
    //    - Accepts ETH from the user.
    //    - Mints RebaseTokens to the user, equivalent to the ETH sent (1:1 peg initially).
    // 3. Implement a redeem function:
    //    - Burns the user's RebaseTokens.
    //    - Sends the corresponding amount of ETH back to the user.
    // 4. Implement a mechanism to add ETH rewards to the vault.

    IRebaseToken private immutable I_REBASE_TOKEN;

    // Event for deposits (user is indexed for efficient filtering)
    event Deposit(address indexed user, uint256 amount);

    // Event for redemptions (user is indexed for efficient filtering)
    event Redeem(address indexed user, uint256 amount);

    error Vault__RedeemFailed();
    error Vault__DepositAmountIsZero();

    constructor(IRebaseToken _rebaseTokenAddress) {
        I_REBASE_TOKEN = _rebaseTokenAddress;
    }

    /**
     * @notice Fallback function to accept ETH rewards sent directly to the contract.
     * @dev Any ETH sent to this contract's address without data will be accepted.
     */
    receive() external payable {}

    /**
     * @notice Allows a user to deposit ETH and receive an equivalent amount of RebaseTokens.
     * @dev The amount of ETH sent with the transaction (msg.value) determines the amount of tokens minted.
     * Assumes a 1:1 peg for ETH to RebaseToken for simplicity in this version.
     */
    function deposit() external payable {
        // The amount of ETH sent is msg.value
        // The user making the call is msg.sender
        uint256 amountToMint = msg.value;

        // Ensure some ETH is actually sent
        if (amountToMint == 0) {
            revert Vault__DepositAmountIsZero();
        }

        // Call the mint function on the RebaseToken contract
        I_REBASE_TOKEN.mint(msg.sender, amountToMint, I_REBASE_TOKEN.getInterestRate());

        // Emit an event to log the deposit
        emit Deposit(msg.sender, amountToMint);
    }

    /**
     * @notice Allows a user to burn their RebaseTokens and receive a corresponding amount of ETH.
     * @param _amount The amount of RebaseTokens to redeem.
     * @dev Follows Checks-Effects-Interactions pattern. Uses low-level .call for ETH transfer.
     */
    function redeem(uint256 _amount) external {
        // 1. Effects (State changes occur first)
        // Burn the specified amount of tokens from the caller (msg.sender)
        uint256 amountToRedeem = _amount;
        if (_amount == type(uint256).max) {
            amountToRedeem = I_REBASE_TOKEN.balanceOf(msg.sender);
        }
        // The RebaseToken's burn function should handle checks for sufficient balance.
        I_REBASE_TOKEN.burn(msg.sender, _amount);

        // 2. Interactions (External calls / ETH transfer last)
        // Send the equivalent amount of ETH back to the user
        (bool success,) = payable(msg.sender).call{value: amountToRedeem}("");

        // Check if the ETH transfer succeeded
        if (!success) {
            revert Vault__RedeemFailed();
        }

        // Emit an event logging the redemption
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice Gets the address of the RebaseToken contract associated with this vault.
     * @return The address of the RebaseToken.
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(I_REBASE_TOKEN);
    }
}
