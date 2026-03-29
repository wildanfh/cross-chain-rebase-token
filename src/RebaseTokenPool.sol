// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pool} from "@ccip/contracts/libraries/Pool.sol";
import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {IERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    // Constructor sesuai signature baru: token, decimals, advancedPoolHooks, rmnProxy, router
    constructor(IERC20 token, uint8 localTokenDecimals, address advancedPoolHooks, address rmnProxy, address router)
        TokenPool(token, localTokenDecimals, advancedPoolHooks, rmnProxy, router)
    {}

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        public
        virtual
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        // 4 argumen: input, blockConfirmations, tokenArgs, feeAmount
        _validateLockOrBurn(lockOrBurnIn, WAIT_FOR_FINALITY, "", 0);

        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        public
        virtual
        override
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn, releaseOrMintIn.sourceDenominatedAmount, WAIT_FOR_FINALITY);

        address receiver = releaseOrMintIn.receiver;
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));

        IRebaseToken(address(i_token)).mint(receiver, releaseOrMintIn.sourceDenominatedAmount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.sourceDenominatedAmount});
    }
}
