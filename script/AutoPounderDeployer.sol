// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {AutoPounder} from "../src/AutoPounder.sol";
import {MainnetContracts as MC} from "./Contracts.sol";

interface IVault {
    function getAssets() external view returns (address[] memory);
}

/// @title AutoPounderDeployer
/// @notice Shared deployment logic for AutoPounder
/// @dev Used by both deploy scripts and integration tests
library AutoPounderDeployer {
    /// @notice Build the AutoPounder configuration for mainnet
    /// @return config The AutoPounder configuration struct
    function buildConfig() internal view returns (AutoPounder.Config memory config) {
        address vault = MC.STAK;

        // Get vault assets to determine erc4626_2
        address[] memory stakAssets = IVault(vault).getAssets();
        require(stakAssets.length >= 2, "STAK vault doesn't have 2 assets");
        address erc4626_2 = stakAssets[1];

        config = AutoPounder.Config({
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
            swapRoute: MC.getSwapRoute(),
            swapPools: MC.getSwapPools(),
            swapParams: MC.getSwapParams(),
            curvePool2_assetIndex: MC.CURVE_STAK_ASSET_INDEX,
            minOutputBps: 9900,
            maxOracleAge: 86400
        });
    }

    /// @notice Deploy a new AutoPounder instance
    /// @param admin The admin address for the AutoPounder
    /// @return autoPounder The deployed AutoPounder instance
    function deploy(address admin) internal returns (AutoPounder autoPounder) {
        AutoPounder.Config memory config = buildConfig();
        autoPounder = new AutoPounder(config, admin);
    }
}
