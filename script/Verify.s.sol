// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AutoPounder} from "../src/AutoPounder.sol";
import {AutoPounderVerifier} from "./AutoPounderVerifier.sol";

/**
 * @title Verify
 * @notice Verification script for deployed AutoPounder contract
 * @dev Run with: forge script script/Verify.s.sol:Verify --rpc-url $RPC_URL -vvv --sig "run(address)" <AUTOPOUNDER_ADDRESS>
 */
contract Verify is Script {
    function run(address autoPounderAddress) public view {
        console.log("Verifying AutoPounder at:", autoPounderAddress);

        AutoPounder autoPounder = AutoPounder(autoPounderAddress);

        AutoPounderVerifier.verify(autoPounder);

        console.log("Verification successful!");
        console.log("  vault:", autoPounder.vault());
        console.log("  accountant:", autoPounder.accountant());
        console.log("  gauge:", autoPounder.gauge());
        console.log("  rewardToken:", autoPounder.rewardToken());
        console.log("  baseAsset:", autoPounder.baseAsset());
        console.log("  curveRouter:", autoPounder.curveRouter());
        console.log("  curvePool2:", autoPounder.curvePool2());
        console.log("  erc4626_1:", autoPounder.erc4626_1());
        console.log("  erc4626_2:", autoPounder.erc4626_2());
        console.log("  minOutputBps:", autoPounder.minOutputBps());
        console.log("  maxOracleAge:", autoPounder.maxOracleAge());
    }
}
