// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {CCIPLocalSimulatorFork} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "@chainlink-local/src/ccip/Register.sol";

contract GetZksyncConfig is Script {
    function run() external {
        CCIPLocalSimulatorFork ccip = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory details = ccip.getNetworkDetails(300); // 300 is ZKsync Sepolia
        console.log("TokenAdminRegistry:", details.tokenAdminRegistryAddress);
        console.log("RegistryModuleOwnerCustom:", details.registryModuleOwnerCustomAddress);
    }
}
