// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AutoPounder} from "../../src/AutoPounder.sol";
import {MainnetContracts} from "../../script/Contracts.sol";

interface IVault {
    function getAssets() external view returns (address[] memory);
    function processor(address[] calldata targets, uint256[] calldata values, bytes[] calldata data)
        external
        returns (bytes[] memory);
}

contract BaseIntegrationTest is Test {
    AutoPounder public autoPounder;

    // Import all addresses from MainnetContracts
    address constant STAK = MainnetContracts.STAK;
    address constant STAKEDAO_ACCOUNTANT = MainnetContracts.STAKEDAO_ACCOUNTANT;
    address constant CRV = MainnetContracts.CRV;
    address constant USDC = MainnetContracts.USDC;
    address constant GAUGE = MainnetContracts.GAUGE;
    address constant YN_RWAX = MainnetContracts.YN_RWAX;
    address constant CURVE_ROUTER = MainnetContracts.CURVE_ROUTER;
    address constant CURVE_STAK_POOL = MainnetContracts.CURVE_STAK_POOL;
    address constant CHAINLINK_CRV_USD = MainnetContracts.CHAINLINK_CRV_USD;
    address constant CHAINLINK_USDC_USD = MainnetContracts.CHAINLINK_USDC_USD;

    int128 constant CURVE_STAK_ASSET_INDEX = MainnetContracts.CURVE_STAK_ASSET_INDEX;

    // Test accounts
    address deployer;
    address vaultOwner;

    function setUp() public virtual {
        // Create test accounts
        deployer = makeAddr("deployer");
        vaultOwner = makeAddr("vaultOwner");

        // Get the second asset from STAK vault (erc4626_2)
        address[] memory stakAssets = IVault(STAK).getAssets();
        require(stakAssets.length >= 2, "STAK vault doesn't have 2 assets");
        address erc4626_2 = stakAssets[1];

        // Get swap route and pools from MainnetContracts
        address[11] memory swapRoute = MainnetContracts.getSwapRoute();
        address[5] memory swapPools = MainnetContracts.getSwapPools();

        // Build AutoPounder configuration
        AutoPounder.Config memory config = AutoPounder.Config({
            vault: STAK,
            accountant: STAKEDAO_ACCOUNTANT,
            gauge: GAUGE,
            rewardToken: CRV,
            baseAsset: USDC,
            curveRouter: CURVE_ROUTER,
            curvePool2: CURVE_STAK_POOL,
            erc4626_1: YN_RWAX,
            erc4626_2: erc4626_2,
            rewardTokenOracle: CHAINLINK_CRV_USD,
            baseAssetOracle: CHAINLINK_USDC_USD,
            swapRoute: swapRoute,
            swapPools: swapPools,
            curvePool2_assetIndex: CURVE_STAK_ASSET_INDEX
        });

        // Deploy AutoPounder
        vm.startPrank(deployer);
        autoPounder = new AutoPounder(config);
        vm.stopPrank();
    }
}
