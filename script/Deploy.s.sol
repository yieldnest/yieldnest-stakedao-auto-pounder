// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "forge-std/Script.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";
import {AutoPounder} from "../src/AutoPounder.sol";
import {AutoPounderDeployer} from "./AutoPounderDeployer.sol";

/**
 * @title Deploy
 * @notice Deployment script for AutoPounder contract
 * @dev Run with: forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify --sender <DEPLOYER_ADDRESS> --account <ACCOUNT_LABEL-DEPLOYER_ADDRESS>
 */
contract Deploy is Script {
    using stdJson for string;

    address public deployer;
    AutoPounder public autoPounder;

    function label() public view returns (string memory) {
        return string.concat("autoPounder-", Strings.toString(block.chainid));
    }

    function deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment() internal {
        vm.serializeAddress(label(), "autoPounder", address(autoPounder));
        vm.serializeAddress(label(), "vault", autoPounder.vault());
        vm.serializeAddress(label(), "accountant", autoPounder.accountant());
        vm.serializeAddress(label(), "gauge", autoPounder.gauge());
        vm.serializeAddress(label(), "rewardToken", autoPounder.rewardToken());
        vm.serializeAddress(label(), "baseAsset", autoPounder.baseAsset());
        vm.serializeAddress(label(), "curveRouter", autoPounder.curveRouter());
        vm.serializeAddress(label(), "curvePool2", autoPounder.curvePool2());
        vm.serializeAddress(label(), "erc4626_1", autoPounder.erc4626_1());
        vm.serializeAddress(label(), "erc4626_2", autoPounder.erc4626_2());
        vm.serializeAddress(label(), "rewardTokenOracle", autoPounder.rewardTokenOracle());
        vm.serializeAddress(label(), "baseAssetOracle", autoPounder.baseAssetOracle());
        vm.serializeUint(label(), "minOutputBps", autoPounder.minOutputBps());
        vm.serializeUint(label(), "maxOracleAge", autoPounder.maxOracleAge());

        string memory jsonOutput = vm.serializeAddress(label(), "deployer", deployer);

        vm.writeJson(jsonOutput, deploymentFilePath());
    }

    function run() public {
        deployer = msg.sender;

        vm.startBroadcast();

        autoPounder = AutoPounderDeployer.deploy(deployer);

        vm.stopBroadcast();

        saveDeployment();
    }
}
