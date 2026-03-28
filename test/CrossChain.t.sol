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
import {RegistryModuleOwnerCustom} from "@ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";

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
    Vault vault;

    // Destination chain (Arbitrum Sepolia) contracts
    RebaseToken arbSepoliaToken;
    RebaseTokenPool arbSepoliaPool;

    // Network details for each chain (router, rmnProxy, registries, etc.)
    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    address owner = makeAddr("owner");

    function setUp() public {
        // =====================================================
        // Step 1: Create forks and deploy the CCIP simulator
        // =====================================================
        sepoliaFork = vm.createSelectFork("sepolia");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // =====================================================
        // Step 2: Deploy and configure on Sepolia (source chain)
        // =====================================================
        // We are currently on sepoliaFork (selected above).
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);

        // Deploy RebaseToken on Sepolia
        sepoliaToken = new RebaseToken();

        // Deploy Vault on Sepolia (only on source chain)
        vault = new Vault(IRebaseToken(address(sepoliaToken)));

        // Deploy RebaseTokenPool on Sepolia
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            18,
            address(0), // no advanced pool hooks
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        // Grant MINT_AND_BURN_ROLE to Vault and Pool
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));

        vm.stopPrank();

        // =====================================================
        // Step 3: Deploy and configure on Arbitrum Sepolia
        // =====================================================
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);

        // Deploy RebaseToken on Arbitrum Sepolia
        arbSepoliaToken = new RebaseToken();

        // Deploy RebaseTokenPool on Arbitrum Sepolia
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            18,
            address(0), // no advanced pool hooks
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        // Grant MINT_AND_BURN_ROLE to Pool (no vault on destination chain)
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));

        vm.stopPrank();

        // =====================================================
        // Step 4: Claim admin role for tokens in CCIP system
        // =====================================================

        // --- Sepolia: Register + Accept admin ---
        vm.selectFork(sepoliaFork);
        vm.startPrank(owner);

        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(sepoliaToken));

        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .acceptAdminRole(address(sepoliaToken));

        vm.stopPrank();

        // --- Arbitrum Sepolia: Register + Accept admin ---
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);

        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(arbSepoliaToken));

        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .acceptAdminRole(address(arbSepoliaToken));

        vm.stopPrank();

        // =====================================================
        // Step 5: Link tokens to their pools
        // =====================================================

        // --- Sepolia: Link sepoliaToken → sepoliaPool ---
        vm.selectFork(sepoliaFork);
        vm.startPrank(owner);

        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(sepoliaToken), address(sepoliaPool));

        vm.stopPrank();

        // --- Arbitrum Sepolia: Link arbSepoliaToken → arbSepoliaPool ---
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);

        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(arbSepoliaToken), address(arbSepoliaPool));

        vm.stopPrank();

        // Token pool chain configuration (applyChainUpdates) will be
        // implemented in a dedicated function in the next lesson.
    }

    // =========================================
    // Tests
    // =========================================
    function testForkSetup() public {
        // Verify Sepolia deployments
        vm.selectFork(sepoliaFork);
        assertGt(address(sepoliaToken).code.length, 0, "Sepolia token should be deployed");
        assertGt(address(vault).code.length, 0, "Vault should be deployed on Sepolia");
        assertGt(address(sepoliaPool).code.length, 0, "Sepolia pool should be deployed");

        // Verify Arbitrum Sepolia deployments
        vm.selectFork(arbSepoliaFork);
        assertGt(address(arbSepoliaToken).code.length, 0, "Arb Sepolia token should be deployed");
        assertGt(address(arbSepoliaPool).code.length, 0, "Arb Sepolia pool should be deployed");
    }
}
