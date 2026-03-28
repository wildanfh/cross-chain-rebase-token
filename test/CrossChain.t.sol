// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {CCIPLocalSimulatorFork} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

contract CrossChainTest is Test {
    // =========================================
    // State Variables
    // =========================================
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    // Source chain (Sepolia) contracts
    RebaseToken sepoliaToken;
    Vault vault; // Vault hanya di source chain (Sepolia)

    // Destination chain (Arbitrum Sepolia) contracts
    RebaseToken arbSepoliaToken;

    // Token pools will be declared and deployed in a later stage
    // RebaseTokenPool sepoliaPool;
    // RebaseTokenPool arbSepoliaPool;

    address owner = makeAddr("owner");

    function setUp() public {
        // =====================================================
        // Step 1: Create forks and deploy the CCIP simulator
        // =====================================================

        // Create and immediately select the Sepolia fork as our starting environment.
        // "sepolia" alias is resolved from foundry.toml's [rpc_endpoints].
        sepoliaFork = vm.createSelectFork("sepolia");

        // Create the Arbitrum Sepolia fork (but don't switch to it yet).
        arbSepoliaFork = vm.createFork("arb-sepolia");

        // Deploy the CCIPLocalSimulatorFork — this simulates the CCIP relay layer.
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        // Make the simulator persistent across ALL forks so both chains
        // can interact with the same instance.
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // =====================================================
        // Step 2: Deploy and configure on Sepolia (source chain)
        // =====================================================
        // We are currently on sepoliaFork (selected above).

        vm.startPrank(owner);

        // Deploy RebaseToken on Sepolia
        sepoliaToken = new RebaseToken();

        // Deploy Vault on Sepolia (only on source chain)
        // Cast address(sepoliaToken) to IRebaseToken to satisfy the Vault constructor
        vault = new Vault(IRebaseToken(address(sepoliaToken)));

        // Grant MINT_AND_BURN_ROLE to Vault so it can mint/burn tokens
        sepoliaToken.grantMintAndBurnRole(address(vault));

        vm.stopPrank();

        // =====================================================
        // Step 3: Deploy and configure on Arbitrum Sepolia (destination chain)
        // =====================================================
        vm.selectFork(arbSepoliaFork); // Switch to the Arbitrum Sepolia fork

        vm.startPrank(owner);

        // Deploy RebaseToken on Arbitrum Sepolia
        arbSepoliaToken = new RebaseToken();

        vm.stopPrank();

        // Token pool deployments and CCIP configuration will follow
        // in subsequent lessons.
    }

    // =========================================
    // Placeholder test to verify setup works
    // =========================================
    function testForkSetup() public {
        // Verify Sepolia fork has the token deployed
        vm.selectFork(sepoliaFork);
        assertGt(address(sepoliaToken).code.length, 0, "Sepolia token should be deployed");
        assertGt(address(vault).code.length, 0, "Vault should be deployed on Sepolia");

        // Verify Arbitrum Sepolia fork has the token deployed
        vm.selectFork(arbSepoliaFork);
        assertGt(address(arbSepoliaToken).code.length, 0, "Arb Sepolia token should be deployed");
    }
}
