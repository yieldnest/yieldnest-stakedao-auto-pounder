// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {AutoPounder} from "../src/AutoPounder.sol";
import {MainnetContracts as MC} from "./Contracts.sol";

interface IVaultAssets {
    function getAssets() external view returns (address[] memory);
}

/// @title AutoPounderVerifier
/// @notice Shared verification logic for AutoPounder deployments
/// @dev Used by both Verify script and integration tests
library AutoPounderVerifier {
    error VerificationFailed(string reason);

    /// @notice YnSecurityCouncil address - expected admin for AutoPounder
    address internal constant YN_SECURITY_COUNCIL = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;

    /// @notice Verifies all configuration values match expected mainnet values
    /// @param autoPounder The deployed AutoPounder instance to verify
    function verify(AutoPounder autoPounder) internal view {
        // Get expected erc4626_2 from vault
        address[] memory stakAssets = IVaultAssets(MC.STAK).getAssets();
        if (stakAssets.length < 2) revert VerificationFailed("STAK vault doesn't have 2 assets");
        address expectedErc4626_2 = stakAssets[1];

        // Verify core addresses
        if (autoPounder.vault() != MC.STAK) {
            revert VerificationFailed("vault mismatch");
        }
        if (autoPounder.accountant() != MC.STAKEDAO_ACCOUNTANT) {
            revert VerificationFailed("accountant mismatch");
        }
        if (autoPounder.gauge() != MC.GAUGE) {
            revert VerificationFailed("gauge mismatch");
        }
        if (autoPounder.rewardToken() != MC.CRV) {
            revert VerificationFailed("rewardToken mismatch");
        }
        if (autoPounder.baseAsset() != MC.USDC) {
            revert VerificationFailed("baseAsset mismatch");
        }
        if (autoPounder.curveRouter() != MC.CURVE_ROUTER) {
            revert VerificationFailed("curveRouter mismatch");
        }
        if (autoPounder.curvePool2() != MC.CURVE_STAK_POOL) {
            revert VerificationFailed("curvePool2 mismatch");
        }
        if (autoPounder.erc4626_1() != MC.YN_USDX) {
            revert VerificationFailed("erc4626_1 mismatch");
        }
        if (autoPounder.erc4626_2() != expectedErc4626_2) {
            revert VerificationFailed("erc4626_2 mismatch");
        }

        // Verify oracles
        if (autoPounder.rewardTokenOracle() != MC.CHAINLINK_CRV_USD) {
            revert VerificationFailed("rewardTokenOracle mismatch");
        }
        if (autoPounder.baseAssetOracle() != MC.CHAINLINK_USDC_USD) {
            revert VerificationFailed("baseAssetOracle mismatch");
        }

        // Verify curve pool index
        if (autoPounder.curvePool2_assetIndex() != MC.CURVE_STAK_ASSET_INDEX) {
            revert VerificationFailed("curvePool2_assetIndex mismatch");
        }

        // Verify swap route (first 5 addresses are the meaningful ones)
        address[11] memory expectedRoute = MC.getSwapRoute();
        for (uint256 i = 0; i < 5; i++) {
            if (autoPounder.swapRoute(i) != expectedRoute[i]) {
                revert VerificationFailed("swapRoute mismatch");
            }
        }

        // Verify swap pools (first 2 pools are used)
        address[5] memory expectedPools = MC.getSwapPools();
        for (uint256 i = 0; i < 2; i++) {
            if (autoPounder.swapPools(i) != expectedPools[i]) {
                revert VerificationFailed("swapPools mismatch");
            }
        }

        // Verify admin role is granted to YnSecurityCouncil
        if (!autoPounder.hasRole(autoPounder.DEFAULT_ADMIN_ROLE(), YN_SECURITY_COUNCIL)) {
            revert VerificationFailed("admin role not granted to YnSecurityCouncil");
        }

        // Verify parameters
        if (autoPounder.minOutputBps() != 9900) {
            revert VerificationFailed("minOutputBps mismatch");
        }
        if (autoPounder.maxOracleAge() != 86400) {
            revert VerificationFailed("maxOracleAge mismatch");
        }
    }
}
