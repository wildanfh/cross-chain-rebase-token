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
import {Client} from "@ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/interfaces/IRouterClient.sol";

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
    address user = makeAddr("user");

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
        vm.selectFork(sepoliaFork);
        vm.startPrank(owner);
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        vm.stopPrank();

        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
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
        // Step 6: Configure token pools for cross-chain
        // =====================================================
        configureTokenPool(
            sepoliaFork,
            address(sepoliaPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaPool),
            address(arbSepoliaToken)
        );

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
        vm.selectFork(forkId);

        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);

        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePoolAddress);

        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        vm.prank(owner);
        TokenPool(localPoolAddress).applyChainUpdates(remoteChainSelectorsToRemove, chainsToAdd);
    }

    // =========================================
    // Helper: Bridge tokens from local to remote chain
    // =========================================
    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);

        // 1. Build the CCIP message
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000}))
        });

        // 2. Get the CCIP fee
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);

        // 3. Fund the user with LINK for fees (test-only via simulator faucet)
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        // 4. Approve LINK for the Router (to pay the fee)
        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);

        // 5. Approve the bridged token for the Router
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        // 6. Record the user's local balance BEFORE sending
        uint256 localBalanceBefore = localToken.balanceOf(user);

        // 8. Send the CCIP message
        vm.prank(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        // 9. Assert local balance decreased by amountToBridge
        uint256 localBalanceAfter = localToken.balanceOf(user);
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge, "Local balance incorrect after send");

        // 10. Simulate time passing for message propagation
        vm.warp(block.timestamp + 20 minutes);

        // 11. Read the user's balance on remote chain BEFORE message routing.
        //     Must briefly switch to remoteFork because remoteToken only exists there.
        vm.selectFork(remoteFork);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);

        // 12. Switch back to localFork because switchChainAndRouteMessage
        //     uses vm.activeFork() to detect the SOURCE chain.
        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        // 13. Now we are on remoteFork. Assert remote balance increased by amountToBridge.
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge, "Remote balance incorrect after receive");
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

    function testBridgeAllTokens() public {
        uint256 amountToDeposit = 1e5;

        // =====================================================
        // 1. Deposit into Vault on Sepolia
        // =====================================================
        vm.selectFork(sepoliaFork);
        vm.deal(user, amountToDeposit);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: amountToDeposit}();

        assertEq(sepoliaToken.balanceOf(user), amountToDeposit, "User Sepolia token balance after deposit incorrect");

        // =====================================================
        // 2. Bridge all tokens: Sepolia → Arbitrum Sepolia
        // =====================================================
        bridgeTokens(
            amountToDeposit,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );

        // =====================================================
        // 3. Warp time on Arb Sepolia so interest accrues
        // =====================================================
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes);

        // After time passes, the rebase token balance grows due to interest.
        // We bridge back the FULL balance (principal + accrued interest).
        uint256 arbBalance = arbSepoliaToken.balanceOf(user);
        assertGt(arbBalance, amountToDeposit, "Balance should have grown due to interest accrual");

        // =====================================================
        // 4. Bridge all tokens back: Arbitrum Sepolia → Sepolia
        // =====================================================
        bridgeTokens(
            arbBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );

        // =====================================================
        // 5. Final verification on Sepolia
        // =====================================================
        vm.selectFork(sepoliaFork);
        assertEq(
            sepoliaToken.balanceOf(user),
            arbBalance,
            "User Sepolia token balance after round-trip should match Arb balance"
        );

        uint256 initialInterestRate = sepoliaToken.getUserInterestRate(user);
        vm.selectFork(arbSepoliaFork);
        uint256 bridgedInterestRate = arbSepoliaToken.getUserInterestRate(user);
        assertEq(initialInterestRate, bridgedInterestRate, "Interest rates do not match across chains");
    }
}

