// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "forge-std/Script.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";
import {AutoPounder} from "../src/AutoPounder.sol";
import {MainnetContracts as MC} from "./Contracts.sol";

/**
 * @title Deploy
 * @notice Deployment script for AutoPounder contract
 * @dev Run with: forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify
 */
contract Deploy is Script {
    using stdJson for string;

    address public deployer;
    AutoPounder public autoPounder;
    address public vault;
    address public erc4626_2;

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
        vault = MC.STAK;

        // Get vault assets to determine erc4626_2
        address[] memory stakAssets = IVault(vault).getAssets();
        require(stakAssets.length >= 2, "STAK vault doesn't have 2 assets");
        erc4626_2 = stakAssets[1];

        // Get swap route, pools, and params from MainnetContracts
        address[11] memory swapRoute = MC.getSwapRoute();
        address[5] memory swapPools = MC.getSwapPools();
        uint256[5][5] memory swapParams = MC.getSwapParams();

        // Build AutoPounder configuration
        AutoPounder.Config memory config = AutoPounder.Config({
            vault: vault,
            accountant: MC.STAKEDAO_ACCOUNTANT,
            gauge: MC.GAUGE,
            rewardToken: MC.CRV,
            baseAsset: MC.USDC,
            curveRouter: MC.CURVE_ROUTER,
            curvePool2: MC.CURVE_STAK_POOL,
            erc4626_1: MC.YN_USDX,
            erc4626_2: erc4626_2,
            rewardTokenOracle: MC.CHAINLINK_CRV_USD,
            baseAssetOracle: MC.CHAINLINK_USDC_USD,
            swapRoute: swapRoute,
            swapPools: swapPools,
            swapParams: swapParams,
            curvePool2_assetIndex: MC.CURVE_STAK_ASSET_INDEX,
            minOutputBps: 9900, // 99% = 1% slippage tolerance
            maxOracleAge: 86400 // 24 hours
        });

        vm.startBroadcast();

        // Deploy AutoPounder with deployer as admin
        autoPounder = new AutoPounder(config, deployer);

        vm.stopBroadcast();

        saveDeployment();
    }
}

interface IVault {
    function getAssets() external view returns (address[] memory);
}
