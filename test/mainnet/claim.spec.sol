// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console} from "forge-std/console.sol";
import {AutoPounder} from "../../src/AutoPounder.sol";
import {IVault} from "./BaseIntegrationTest.sol";

/**
 * @title Spec
 * @notice Integration tests for AutoPounder compound workflow
 * @dev Tests full end-to-end claim and compounding functionality on mainnet fork
 */
contract ClaimIntegrationTest is BaseIntegrationTest {
    /**
     * @notice Test that the AutoPounder is properly configured
     */
    function test_Configuration() public view {
        assertEq(autoPounder.vault(), STAK, "Vault mismatch");
        assertEq(autoPounder.accountant(), STAKEDAO_ACCOUNTANT, "Accountant mismatch");
        assertEq(autoPounder.gauge(), GAUGE, "Gauge mismatch");
        assertEq(autoPounder.rewardToken(), CRV, "Reward token mismatch");
        assertEq(autoPounder.baseAsset(), USDC, "Base asset mismatch");
        assertEq(autoPounder.curveRouter(), CURVE_ROUTER, "Curve router mismatch");
        assertEq(autoPounder.rewardTokenOracle(), CHAINLINK_CRV_USD, "CRV oracle mismatch");
        assertEq(autoPounder.baseAssetOracle(), CHAINLINK_USDC_USD, "USDC oracle mismatch");
        assertEq(autoPounder.owner(), deployer, "Owner mismatch");
    }

    /**
     * @notice Test that Chainlink oracles are returning valid prices
     */
    function test_OraclePrices() public view {
        // Query CRV oracle
        (, int256 crvPrice,, uint256 crvUpdatedAt,) = AggregatorV3Interface(CHAINLINK_CRV_USD).latestRoundData();

        assertGt(crvPrice, 0, "CRV price should be positive");
        assertGt(crvUpdatedAt, 0, "CRV oracle should have update time");
        assertLt(block.timestamp - crvUpdatedAt, 86400, "CRV price should be recent (< 1 day)");

        // Query USDC oracle
        (, int256 usdcPrice,, uint256 usdcUpdatedAt,) = AggregatorV3Interface(CHAINLINK_USDC_USD).latestRoundData();

        assertGt(usdcPrice, 0, "USDC price should be positive");
        assertGt(usdcUpdatedAt, 0, "USDC oracle should have update time");
        assertLt(block.timestamp - usdcUpdatedAt, 86400, "USDC price should be recent (< 1 day)");

        // Log prices for debugging
        console.log("CRV Price:", uint256(crvPrice));
        console.log("USDC Price:", uint256(usdcPrice));
    }

    /**
     * @notice Test full compound workflow
     * @dev This requires:
     * - Vault has processor rules set up for the AutoPounder
     * - Accountant has claimable rewards
     * - All approvals and pool configurations are correct
     */
    function test_Compound() public {
        // Note: PROCESSOR_ROLE is automatically granted in BaseIntegrationTest.setUp()

        // Get the second asset from STAK vault (erc4626_2)
        address[] memory stakAssets = IVault(STAK).getAssets();
        assertGe(stakAssets.length, 2, "STAK vault doesn't have 2 assets");
        address erc4626_2 = stakAssets[1];

        IERC20 stakedLpToken = IERC20(erc4626_2);


        // Check initial balances
        uint256 initialCRVBalance = IERC20(CRV).balanceOf(address(autoPounder));
        uint256 initialUSDCBalance = IERC20(USDC).balanceOf(address(autoPounder));

        uint256 initialLpBalance = stakedLpToken.balanceOf(address(STAK));        

        autoPounder.compound();

        // Verify state changes
        uint256 finalCRVBalance = IERC20(CRV).balanceOf(address(autoPounder));
        uint256 finalUSDCBalance = IERC20(USDC).balanceOf(address(autoPounder));

        // After compounding, AutoPounder should have minimal residual balances
        // Most tokens should be compounded back into the vault
        assertEq(finalCRVBalance, initialCRVBalance, "CRV should be swapped");
        assertEq(finalUSDCBalance, initialUSDCBalance, "USDC should be deposited");
        assertGt(stakedLpToken.balanceOf(address(STAK)), initialLpBalance, "StakeDAO LP balance should increase after compounding");
    }

    /**
     * @notice Test that only owner can update configuration
     */
    function test_OnlyOwnerCanUpdateConfig() public {
        address attacker = makeAddr("attacker");

        address[11] memory dummyRoute;
        address[5] memory dummyPools;
        uint256[5][5] memory dummyParams;

        AutoPounder.Config memory newConfig = AutoPounder.Config({
            vault: address(0x1),
            accountant: address(0x2),
            gauge: address(0x3),
            rewardToken: address(0x4),
            baseAsset: address(0x5),
            curveRouter: address(0x6),
            curvePool2: address(0x7),
            erc4626_1: address(0x8),
            erc4626_2: address(0x9),
            rewardTokenOracle: address(0xA),
            baseAssetOracle: address(0xB),
            swapRoute: dummyRoute,
            swapPools: dummyPools,
            swapParams: dummyParams,
            curvePool2_assetIndex: 0,
            minOutputBps: 9900,
            maxOracleAge: 86400
        });

        vm.startPrank(attacker);
        vm.expectRevert(AutoPounder.OnlyOwner.selector);
        autoPounder.updateConfig(newConfig);
        vm.stopPrank();
    }

    /**
     * @notice Test slippage protection parameter updates
     */
    function test_UpdateSlippageProtection() public {
        vm.startPrank(deployer);

        // Update to 2% slippage (9800 bps)
        autoPounder.setMinOutputBps(9800);
        assertEq(autoPounder.minOutputBps(), 9800, "MinOutputBps should be updated");

        // Should revert if setting above 10000
        vm.expectRevert(AutoPounder.InvalidBPS.selector);
        autoPounder.setMinOutputBps(10001);

        vm.stopPrank();
    }

    /**
     * @notice Test oracle staleness parameter updates
     */
    function test_UpdateOracleStaleness() public {
        vm.startPrank(deployer);

        // Update to 2 hours
        autoPounder.setMaxOracleAge(7200);
        assertEq(autoPounder.maxOracleAge(), 7200, "MaxOracleAge should be updated");

        vm.stopPrank();
    }

    /**
     * @notice Test ownership transfer
     */
    function test_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(deployer);
        autoPounder.transferOwnership(newOwner);
        vm.stopPrank();

        assertEq(autoPounder.owner(), newOwner, "Owner should be transferred");

        // Old owner cannot update config
        vm.startPrank(deployer);
        vm.expectRevert(AutoPounder.OnlyOwner.selector);
        autoPounder.setMinOutputBps(9500);
        vm.stopPrank();

        // New owner can update config
        vm.startPrank(newOwner);
        autoPounder.setMinOutputBps(9500);
        assertEq(autoPounder.minOutputBps(), 9500);
        vm.stopPrank();
    }

    /**
     * @notice Test emergency token recovery
     */
    function test_RecoverToken() public {
        // Send some USDC to AutoPounder
        deal(USDC, address(autoPounder), 1000e6);

        uint256 initialOwnerBalance = IERC20(USDC).balanceOf(deployer);

        vm.startPrank(deployer);
        autoPounder.recoverToken(USDC, 1000e6, deployer);
        vm.stopPrank();

        uint256 finalOwnerBalance = IERC20(USDC).balanceOf(deployer);

        assertEq(finalOwnerBalance - initialOwnerBalance, 1000e6, "Owner should receive recovered tokens");
        assertEq(IERC20(USDC).balanceOf(address(autoPounder)), 0, "AutoPounder should have no USDC left");
    }

    /**
     * @notice Test that compound reverts with stale oracle data
     */
    function test_RevertOnStaleOracle() public {
        // Set max oracle age to something very small
        vm.startPrank(deployer);
        autoPounder.setMaxOracleAge(1);
        vm.stopPrank();

        // Fast forward time so oracle data is stale
        vm.warp(block.timestamp + 3600);

        // Should revert with StaleOraclePrice
        vm.expectRevert(AutoPounder.StaleOraclePrice.selector);
        autoPounder.compound();
    }

    /**
     * @notice Test Curve pool configuration
     */
    function test_CurvePoolIndices() public view {
        // Check swap route configuration
        assertEq(autoPounder.swapRoute(0), CRV, "Route[0] should be CRV");
        assertEq(autoPounder.swapRoute(4), USDC, "Route[4] should be USDC");
        assertEq(autoPounder.curvePool2_assetIndex(), CURVE_STAK_ASSET_INDEX);
    }
}

// Import the Chainlink interface for oracle testing
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
