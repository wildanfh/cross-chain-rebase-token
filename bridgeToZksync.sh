#!/bin/bash

# Source environment variables (RPC URLs)
source .env

echo "1. Updating Foundry for ZKsync..."
foundryup -zksync

echo "2. Compiling Contracts for ZKsync..."
forge build --zksync

echo "3. Deploying Contracts on ZKsync Sepolia..."
# Note: In a true automated script, ZKsync parameters (router/RMN addresses) need to be determined dynamically or hardcoded.
# Here we represent the deployment step visually.
# forge create src/RebaseToken.sol:RebaseToken --legacy --zksync --account myaccount \
#     --rpc-url $ZKSYNC_SEPOLIA_RPC_URL
# ZKSYNC_REBASE_TOKEN_ADDRESS="..."
#
# forge create src/RebaseTokenPool.sol:RebaseTokenPool \
#     --constructor-args $ZKSYNC_REBASE_TOKEN_ADDRESS <decimals> <allowlist> <rmn> <router> \
#     --legacy --zksync --account myaccount --rpc-url $ZKSYNC_SEPOLIA_RPC_URL
# ZKSYNC_POOL_ADDRESS="..."

# Note: The following environmental variables must be replaced with the actual captured addresses post-deployment
ZKSYNC_REBASE_TOKEN_ADDRESS="0x6198d3094E0f2E57C64A37aA596C303312613ee5" 
ZKSYNC_POOL_ADDRESS="0x700e7380086a166CD78a243CCE9B70f836189d0e"
ZKSYNC_REGISTRY_MODULE="0x57Fe0a69622d14878aA7A6d246332d667c4E7657" 
ZKSYNC_TOKEN_ADMIN_REGISTRY="0xc7770174151759230526eE15383344692794b7DF"
ZKSYNC_ROUTER="0xA1fd7419A5fD7B1a193630f9a2f260195e340B16"
ZKSYNC_RMN="0x3DA2881E995a1215D360B4450259837905c7C467"

SEPOLIA_REBASE_TOKEN_ADDRESS="0x8254b343709C503Ff7Ed30Ab937FBd828D7F987B"
SEPOLIA_POOL_ADDRESS="0x3dA269C1A06bD65A055F1455AFd3bDd872a57a2D"
SEPOLIA_VAULT_ADDRESS="0x69631bdA45E44bE3144D5443dfEe79e57E45b875"

ETHEREUM_SEPOLIA_CHAIN_SELECTOR="16015286601757825753" # Hardcoded CCIP Chain Selector for Eth Sepolia

echo "4. Setting Permissions on ZKsync Sepolia Contracts..."
# grantMintAndBurnRole (assuming 0x... signature or properly cast)
cast send $ZKSYNC_REBASE_TOKEN_ADDRESS "grantMintAndBurnRole(address)" $ZKSYNC_POOL_ADDRESS \
    --account myaccount --legacy --zksync --rpc-url $ZKSYNC_SEPOLIA_RPC_URL

# registerAdminViaOwner
cast send $ZKSYNC_REGISTRY_MODULE "registerAdminViaOwner(address)" $ZKSYNC_REBASE_TOKEN_ADDRESS \
    --account myaccount --legacy --zksync --rpc-url $ZKSYNC_SEPOLIA_RPC_URL

# acceptAdminRole
cast send $ZKSYNC_TOKEN_ADMIN_REGISTRY "acceptAdminRole(address)" $ZKSYNC_REBASE_TOKEN_ADDRESS \
    --account myaccount --legacy --zksync --rpc-url $ZKSYNC_SEPOLIA_RPC_URL

# setPool
cast send $ZKSYNC_TOKEN_ADMIN_REGISTRY "setPool(address,address)" $ZKSYNC_REBASE_TOKEN_ADDRESS $ZKSYNC_POOL_ADDRESS \
    --account myaccount --legacy --zksync --rpc-url $ZKSYNC_SEPOLIA_RPC_URL

echo "5. Deploying Contracts on Ethereum Sepolia..."
forge script ./script/Deployer.s.sol:TokenAndPoolDeployer \
    --rpc-url $SEPOLIA_RPC_URL --account myaccount --broadcast

forge script ./script/Deployer.s.sol:VaultDeployer \
    --rpc-url $SEPOLIA_RPC_URL --account myaccount --broadcast

echo "6. Setting Permissions on Ethereum Sepolia Contracts..."
echo "Granting MintAndBurn role on Sepolia RebaseToken to Pool..."
forge script ./script/Deployer.s.sol:SetPermissions \
    --rpc-url $SEPOLIA_RPC_URL \
    --account myaccount \
    --broadcast \
    --sig "grantRole(address,address)" \
    $SEPOLIA_REBASE_TOKEN_ADDRESS $SEPOLIA_POOL_ADDRESS

echo "Setting Admin and Pool on Sepolia TokenAdminRegistry..."
forge script ./script/Deployer.s.sol:SetPermissions \
    --rpc-url $SEPOLIA_RPC_URL \
    --account myaccount \
    --broadcast \
    --sig "setAdminAndPool(address,address)" \
    $SEPOLIA_REBASE_TOKEN_ADDRESS $SEPOLIA_POOL_ADDRESS

echo "7. Configuring Pool on Ethereum Sepolia..."
# Requires ConfigurePoolScript to receive parameters via --sig or environment
# forge script ./script/ConfigurePool.s.sol:ConfigurePoolScript ...

echo "8. Depositing Funds into Sepolia Vault..."
AMOUNT=10000000000000000 # 0.01 ETH
cast send $SEPOLIA_VAULT_ADDRESS "deposit()" --value $AMOUNT \
    --rpc-url $SEPOLIA_RPC_URL --account myaccount

echo "9. Configuring Pool on ZKsync Sepolia..."
cast send $ZKSYNC_POOL_ADDRESS "applyChainUpdates((uint64,bytes[],bytes,RateLimiter.Config,RateLimiter.Config)[])" \
    "[[$ETHEREUM_SEPOLIA_CHAIN_SELECTOR, [$SEPOLIA_POOL_ADDRESS], $SEPOLIA_REBASE_TOKEN_ADDRESS, [false, 0, 0], [false, 0, 0]]]" \
    --rpc-url $ZKSYNC_SEPOLIA_RPC_URL --account myaccount --legacy --zksync

echo "10. Bridging Funds from Sepolia to ZKsync..."
# Requires BridgeTokensScript
# forge script ./script/BridgeTokens.s.sol:BridgeTokensScript ...
