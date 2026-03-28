// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";




contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        // Impersonate the 'owner' address for deployments and role granting
        vm.startPrank(owner);

        rebaseToken = new RebaseToken();

        // Deploy Vault: requires IRebaseToken.
        // Direct casting (IRebaseToken(rebaseToken)) is invalid.
        // Correct way: cast rebaseToken to address, then to IRebaseToken.
        vault = new Vault(IRebaseToken(address(rebaseToken)));

        // Grant the MINT_AND_BURN_ROLE to the Vault contract.
        // The grantMintAndBurnRole function expects an address.
        rebaseToken.grantMintAndBurnRole(address(vault));

        vm.deal(owner, 1 ether);

        // Send 1 ETH to the Vault to simulate initial funds.
        // The target address must be cast to 'payable'.
        (bool success,) = payable(address(vault)).call{value: 1 ether}("");

        require(success, "ETH transfer failed");

        // Stop impersonating the 'owner'
        vm.stopPrank();
    }

    // Test if interest accrues linearly after a deposit.
    // 'amount' will be a fuzzed input.
    function testDepositLinear(uint256 amount) public {
        // Constrain the fuzzed 'amount' to a practical range.
        // Min: 0.00001 ETH (1e5 wei), Max: type(uint96).max to avoid overflows.
        amount = bound(amount, 1e5, type(uint96).max);

        // 1. User deposits 'amount' ETH
        vm.startPrank(user);
        vm.deal(user, amount);

        vault.deposit{value: amount}();

        uint256 initialBalance = rebaseToken.balanceOf(user);

        uint256 timeDelta = 1 days;
        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterFirstWarp = rebaseToken.balanceOf(user);
        uint256 interestFirstPeriod = balanceAfterFirstWarp - initialBalance;

        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterSecondWarp = rebaseToken.balanceOf(user);
        uint256 interestSecondPeriod = balanceAfterSecondWarp - balanceAfterFirstWarp;

        assertApproxEqAbs(interestFirstPeriod, interestSecondPeriod, 1, "Interest accrual is not linear");

        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
        require(success, "Failed to add rewards");
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        vault.redeem(type(uint256).max);

        assertEq(rebaseToken.balanceOf(user), 0);
        assertApproxEqAbs(address(user).balance, amount, 1);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        time = bound(time, 1 days, 365 days); // Batasi waktu agar tidak overflow

        vm.startPrank(user);
        vm.deal(user, depositAmount);
        vault.deposit{value: depositAmount}();
        vm.stopPrank();

        vm.warp(block.timestamp + time);

        uint256 balanceAfterTime = rebaseToken.balanceOf(user);
        uint256 rewardAmount = balanceAfterTime - depositAmount;
        vm.deal(address(this), rewardAmount);

        addRewardsToVault(rewardAmount);

        vm.startPrank(user);
        vault.redeem(type(uint256).max);

        assertGt(address(user).balance, depositAmount); // Uang yang kembali harus lebih besar dari deposit
        vm.stopPrank();
    }

    function testGetPrincipleAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        assertEq(rebaseToken.principleBalanceOf(user), amount);

        vm.warp(block.timestamp + 10 days); // Maju 10 hari

        // Saldo modal harus tetap sama meski saldo total (dengan bunga) naik
        assertEq(rebaseToken.principleBalanceOf(user), amount);
        vm.stopPrank();
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user); // User biasa mencoba set rate
        vm.expectRevert("Ownable: caller is not the owner");
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        uint256 interestRate = rebaseToken.getInterestRate();

        vm.prank(user);
        vm.expectRevert();
        rebaseToken.mint(user, 1 ether, interestRate);

        vm.prank(user);
        vm.expectRevert();
        rebaseToken.burn(user, 1 ether);
    }

    // ==========================================
    // TAMBAHAN TES UNTUK MENAIKKAN COVERAGE
    // ==========================================

    function testDepositZeroReverts() public {
        vm.startPrank(user);
        vm.expectPartialRevert(bytes4(Vault.Vault__DepositAmountIsZero.selector));
        vault.deposit{value: 0}();
        vm.stopPrank();
    }

    function testGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }

    function testSetInterestRateSuccess() public {
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10); // Bos menurunkan suku bunga jadi 4e10
        assertEq(rebaseToken.getInterestRate(), 4e10); // Sukses
    }

    function testSetInterestRateCanOnlyDecrease() public {
        vm.prank(owner);
        // Suku bunga awal adalah 5e10. Jika dicoba naik jadi 6e10, harusnya gagal
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        rebaseToken.setInterestRate(6e10);
    }

    function testTransferInheritsInterestRate(uint256 amount, uint256 transferAmount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        transferAmount = bound(transferAmount, 1, amount);

        // 1. User nabung saat rate global 5e10
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        vm.stopPrank();

        // 2. Bos menurunkan rate global jadi 4e10
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // 3. User transfer ke Penerima Baru
        address penerimaBaru = makeAddr("penerima");

        vm.prank(user);
        bool success = rebaseToken.transfer(penerimaBaru, transferAmount);
        assertTrue(success, "Transfer should succeed");

        // 4. Penerima baru HARUS mewarisi rate 5e10 dari pengirim, BUKAN 4e10 (rate global saat ini)
        assertEq(rebaseToken.getUserInterestRate(penerimaBaru), 5e10);
        // Saldo penerima harus sesuai
        assertEq(rebaseToken.principleBalanceOf(penerimaBaru), transferAmount);
    }
}
