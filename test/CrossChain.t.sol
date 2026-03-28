// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {CCIPLocalSimulatorFork} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "@chainlink-local/src/ccip/Register.sol";
import {IERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/IERC20.sol";

contract CrossChainTest is Test {
    // =========================================
    // State Variables
    // =========================================
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    // Source chain (Sepolia) contracts
    RebaseToken sepoliaToken;
    RebaseTokenPool sepoliaPool;
    Vault sepoliaVault;

    // Destination chain (Arbitrum Sepolia) contracts
    RebaseToken arbSepoliaToken;
    RebaseTokenPool arbSepoliaPool;
    Vault arbSepoliaVault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        // =====================================================
        // Step 1: Create forks and deploy the CCIP simulator
        // =====================================================

        // Create and immediately select the Sepolia fork as our starting environment.
        // The "sepolia" alias is resolved from foundry.toml's [rpc_endpoints].
        sepoliaFork = vm.createSelectFork("sepolia");

        // Create the Arbitrum Sepolia fork (but don't switch to it yet).
        arbSepoliaFork = vm.createFork("arb-sepolia");

        // Deploy the CCIPLocalSimulatorFork — this simulates the CCIP relay layer.
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        // Make the simulator persistent across ALL forks so both chains
        // can interact with the same instance.
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // =====================================================
        // Step 2: Deploy contracts on the Sepolia fork
        // =====================================================
        // We are currently on sepoliaFork (selected above).
        Register.NetworkDetails memory sepoliaNetworkDetails =
            ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);

        // Deploy RebaseToken on Sepolia
        sepoliaToken = new RebaseToken();

        // Deploy Vault on Sepolia
        sepoliaVault = new Vault(IRebaseToken(address(sepoliaToken)));

        // Deploy RebaseTokenPool on Sepolia
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            18,
            address(0), // no advanced pool hooks
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        // Grant MINT_AND_BURN_ROLE to Vault and Pool
        sepoliaToken.grantMintAndBurnRole(address(sepoliaVault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));

        vm.stopPrank();

        // =====================================================
        // Step 3: Switch to Arbitrum Sepolia and deploy there
        // =====================================================
        vm.selectFork(arbSepoliaFork);

        Register.NetworkDetails memory arbSepoliaNetworkDetails =
            ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);

        // Deploy RebaseToken on Arbitrum Sepolia
        arbSepoliaToken = new RebaseToken();

        // Deploy Vault on Arbitrum Sepolia
        arbSepoliaVault = new Vault(IRebaseToken(address(arbSepoliaToken)));

        // Deploy RebaseTokenPool on Arbitrum Sepolia
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            18,
            address(0), // no advanced pool hooks
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        // Grant MINT_AND_BURN_ROLE to Vault and Pool
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaVault));
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));

        vm.stopPrank();
    }

    // =========================================
    // Placeholder test to verify setup works
    // =========================================
    function testForkSetup() public {
        // Verify we can switch between forks
        vm.selectFork(sepoliaFork);
        assertEq(address(sepoliaToken).code.length > 0, true, "Sepolia token should be deployed");

        vm.selectFork(arbSepoliaFork);
        assertEq(address(arbSepoliaToken).code.length > 0, true, "Arb Sepolia token should be deployed");
    }
}
