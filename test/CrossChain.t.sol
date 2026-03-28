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
import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/libraries/RateLimiter.sol";

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

    // Network details for each chain
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
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);

        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            18,
            address(0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));

        vm.stopPrank();

        // =====================================================
        // Step 3: Deploy and configure on Arbitrum Sepolia
        // =====================================================
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);

        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            18,
            address(0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));

        vm.stopPrank();

        // =====================================================
        // Step 4: Claim admin role for tokens in CCIP system
        // =====================================================

        // --- Sepolia ---
        vm.selectFork(sepoliaFork);
        vm.startPrank(owner);
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .acceptAdminRole(address(sepoliaToken));
        vm.stopPrank();

        // --- Arbitrum Sepolia ---
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
        vm.selectFork(sepoliaFork);
        vm.startPrank(owner);
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(sepoliaToken), address(sepoliaPool));
        vm.stopPrank();

        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(arbSepoliaToken), address(arbSepoliaPool));
        vm.stopPrank();

        // =====================================================
        // Step 6: Configure token pools for cross-chain communication
        // =====================================================

        // Sepolia pool ↔ Arbitrum Sepolia pool
        configureTokenPool(
            sepoliaFork,
            address(sepoliaPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaPool),
            address(arbSepoliaToken)
        );

        // Arbitrum Sepolia pool ↔ Sepolia pool
        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaPool),
            address(sepoliaToken)
        );
    }

    // =========================================
    // Helper: Configure a token pool for a remote chain
    // =========================================
    function configureTokenPool(
        uint256 forkId,
        address localPoolAddress,
        uint64 remoteChainSelector,
        address remotePoolAddress,
        address remoteTokenAddress
    ) public {
        // 1. Switch to the local chain's fork
        vm.selectFork(forkId);

        // 2. Prepare the empty removal array (we are only adding)
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);

        // 3. Create the remote pool addresses array
        //    Each element is an ABI-encoded pool address
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePoolAddress);

        // 4. Construct the ChainUpdate struct
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            })
        });

        // 5. Apply the chain update as the pool owner
        vm.prank(owner);
        TokenPool(localPoolAddress).applyChainUpdates(
            remoteChainSelectorsToRemove,
            chainsToAdd
        );
    }

    // =========================================
    // Tests
    // =========================================
    function testForkSetup() public {
        vm.selectFork(sepoliaFork);
        assertGt(address(sepoliaToken).code.length, 0, "Sepolia token should be deployed");
        assertGt(address(vault).code.length, 0, "Vault should be deployed on Sepolia");
        assertGt(address(sepoliaPool).code.length, 0, "Sepolia pool should be deployed");

        vm.selectFork(arbSepoliaFork);
        assertGt(address(arbSepoliaToken).code.length, 0, "Arb Sepolia token should be deployed");
        assertGt(address(arbSepoliaPool).code.length, 0, "Arb Sepolia pool should be deployed");
    }
}
