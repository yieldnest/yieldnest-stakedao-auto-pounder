// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AutoPounder} from "../src/AutoPounder.sol";
import {AutoPounderDeployer} from "./AutoPounderDeployer.sol";
import {MainnetActors} from "./Actors.sol";

/**
 * @title ConstructorArgs
 * @notice Script to generate ABI-encoded constructor arguments for AutoPounder
 * @dev Run with: forge script script/ConstructorArgs.s.sol:ConstructorArgs --rpc-url $RPC_URL
 */
contract ConstructorArgs is Script {
    function run() public {
        MainnetActors actors = new MainnetActors();
        AutoPounder.Config memory config = AutoPounderDeployer.buildConfig();
        address admin = actors.ADMIN();

        bytes memory encodedArgs = abi.encode(config, admin);

        // Output just the hex for easy parsing
        console.logBytes(encodedArgs);
    }
}
