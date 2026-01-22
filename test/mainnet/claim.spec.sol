// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseIntegrationTest} from "./BaseIntegrationTest.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console} from "forge-std/console.sol";
import {AutoPounder} from "../../src/AutoPounder.sol";
import {IVault} from "./BaseIntegrationTest.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MainnetContracts} from "../../script/Contracts.sol";
import {AutoPounderVerifier} from "../../script/AutoPounderVerifier.sol";

/**
 * @title Spec
 * @notice Integration tests for AutoPounder compound workflow
 * @dev Tests full end-to-end claim and compounding functionality on mainnet fork
 */
contract ClaimIntegrationTest is BaseIntegrationTest {
    /**
     * @notice Test that the AutoPounder is properly configured using shared verifier
     */
    function test_Configuration() public view {
        AutoPounderVerifier.verify(autoPounder);
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
        address asset0 = stakAssets[0];

        IERC20 stakedLpToken = IERC20(erc4626_2);

        // Snapshot initial balances
        uint256 initialCRVBalance = IERC20(CRV).balanceOf(address(autoPounder));
        uint256 initialUSDCBalance = IERC20(USDC).balanceOf(address(autoPounder));
        uint256 initialVaultCRV = IERC20(CRV).balanceOf(address(STAK));
        uint256 initialVaultAsset0 = IERC20(asset0).balanceOf(address(STAK));
        uint256 initialLpBalance = stakedLpToken.balanceOf(address(STAK));

        autoPounder.compound();

        // Verify state changes
        uint256 finalCRVBalance = IERC20(CRV).balanceOf(address(autoPounder));
        uint256 finalUSDCBalance = IERC20(USDC).balanceOf(address(autoPounder));
        uint256 finalVaultCRV = IERC20(CRV).balanceOf(address(STAK));
        uint256 finalVaultAsset0 = IERC20(asset0).balanceOf(address(STAK));

        // After compounding, AutoPounder should have minimal residual balances
        // Most tokens should be compounded back into the vault
        assertEq(finalCRVBalance, initialCRVBalance, "CRV should be swapped");
        assertEq(finalUSDCBalance, initialUSDCBalance, "USDC should be deposited");
        assertGt(
            stakedLpToken.balanceOf(address(STAK)),
            initialLpBalance,
            "StakeDAO LP balance should increase after compounding"
        );

        // Vault's CRV, asset0 balances should stay the same before and after
        assertEq(finalVaultCRV, initialVaultCRV, "Vault CRV balance should not change");
        assertEq(finalVaultAsset0, initialVaultAsset0, "Vault asset0 balance should not change");

        // ============================================
        // Extra assertions: Verify complete workflow
        // ============================================

        // AutoPounder should have zero intermediate tokens (ynUSDx, Curve LP)
        assertEq(IERC20(YN_USDX).balanceOf(address(autoPounder)), 0, "ynUSDx should be deposited to Curve");
        assertEq(IERC20(CURVE_STAK_POOL).balanceOf(address(autoPounder)), 0, "Curve LP should be deposited to vault");

        // Measure meaningful compound occurred
        uint256 sharesGained = stakedLpToken.balanceOf(address(STAK)) - initialLpBalance;
        assertGt(sharesGained, 0, "Should have gained meaningful ERC4626_2 shares");
        assertGe(sharesGained, 1, "Should have gained at least 1 wei of shares");

        console.log("Shares gained (stakedLpToken):", sharesGained);
    }

    /**
     * @notice Test that only admin can update configuration
     */
    function test_OnlyAdminCanUpdateConfig() public {
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
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, autoPounder.DEFAULT_ADMIN_ROLE()
            )
        );
        autoPounder.updateConfig(newConfig);
        vm.stopPrank();
    }

    /**
     * @notice Test slippage protection parameter updates
     */
    function test_UpdateSlippageProtection() public {
        vm.startPrank(admin);

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
        vm.startPrank(admin);

        // Update to 2 hours
        autoPounder.setMaxOracleAge(7200);
        assertEq(autoPounder.maxOracleAge(), 7200, "MaxOracleAge should be updated");

        vm.stopPrank();
    }

    /**
     * @notice Test admin role transfer
     */
    function test_TransferAdminRole() public {
        address newAdmin = makeAddr("newAdmin");
        bytes32 adminRole = autoPounder.DEFAULT_ADMIN_ROLE();

        vm.startPrank(admin);
        autoPounder.grantRole(adminRole, newAdmin);
        autoPounder.renounceRole(adminRole, admin);
        vm.stopPrank();

        assertTrue(autoPounder.hasRole(adminRole, newAdmin), "New admin should have role");
        assertFalse(autoPounder.hasRole(adminRole, admin), "Old admin should not have role");

        // Old admin cannot update config
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, adminRole)
        );
        autoPounder.setMinOutputBps(9500);
        vm.stopPrank();

        // New admin can update config
        vm.startPrank(newAdmin);
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

        uint256 initialOwnerBalance = IERC20(USDC).balanceOf(admin);

        vm.startPrank(admin);
        autoPounder.recoverToken(USDC, 1000e6, admin);
        vm.stopPrank();

        uint256 finalOwnerBalance = IERC20(USDC).balanceOf(admin);

        assertEq(finalOwnerBalance - initialOwnerBalance, 1000e6, "Owner should receive recovered tokens");
        assertEq(IERC20(USDC).balanceOf(address(autoPounder)), 0, "AutoPounder should have no USDC left");
    }

    /**
     * @notice Test that compound reverts with stale oracle data
     */
    function test_RevertOnStaleOracle() public {
        // Set max oracle age to something very small
        vm.startPrank(admin);
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

    /**
     * @notice Test that compound is permissionless when no COMPOUNDER_ROLE members exist
     */
    function test_CompoundPermissionless() public {
        address randomUser = makeAddr("randomUser");
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        // Verify no compounders are set
        assertEq(autoPounder.getRoleMemberCount(compounderRole), 0, "No compounders should be set initially");

        // Anyone should be able to compound when no COMPOUNDER_ROLE members exist
        vm.prank(randomUser);
        autoPounder.compound();
    }

    /**
     * @notice Test that compound requires COMPOUNDER_ROLE when members exist
     */
    function test_CompoundRequiresRole() public {
        address compounder = makeAddr("compounder");
        address nonCompounder = makeAddr("nonCompounder");
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        // Grant COMPOUNDER_ROLE to compounder
        vm.prank(admin);
        autoPounder.grantRole(compounderRole, compounder);

        // Verify role member count increased
        assertEq(autoPounder.getRoleMemberCount(compounderRole), 1, "Should have 1 compounder");

        // Non-compounder should be rejected
        vm.prank(nonCompounder);
        vm.expectRevert(AutoPounder.Unauthorized.selector);
        autoPounder.compound();

        // Compounder should be able to compound
        vm.prank(compounder);
        autoPounder.compound();
    }

    // ============================================
    // Constructor Tests
    // ============================================

    /**
     * @notice Test that constructor reverts with zero admin address
     */
    function test_ConstructorRevertsZeroAdmin() public {
        address[11] memory swapRoute = MainnetContracts.getSwapRoute();
        address[5] memory swapPools = MainnetContracts.getSwapPools();
        uint256[5][5] memory swapParams = MainnetContracts.getSwapParams();

        address[] memory stakAssets = IVault(STAK).getAssets();
        address erc4626_2 = stakAssets[1];

        AutoPounder.Config memory config = AutoPounder.Config({
            vault: STAK,
            accountant: STAKEDAO_ACCOUNTANT,
            gauge: GAUGE,
            rewardToken: CRV,
            baseAsset: USDC,
            curveRouter: CURVE_ROUTER,
            curvePool2: CURVE_STAK_POOL,
            erc4626_1: YN_USDX,
            erc4626_2: erc4626_2,
            rewardTokenOracle: CHAINLINK_CRV_USD,
            baseAssetOracle: CHAINLINK_USDC_USD,
            swapRoute: swapRoute,
            swapPools: swapPools,
            swapParams: swapParams,
            curvePool2_assetIndex: CURVE_STAK_ASSET_INDEX,
            minOutputBps: 9900,
            maxOracleAge: 86400
        });

        vm.expectRevert(AutoPounder.InvalidAddress.selector);
        new AutoPounder(config, address(0));
    }

    /**
     * @notice Test that constructor reverts with zero vault address
     */
    function test_ConstructorRevertsZeroVault() public {
        address[11] memory swapRoute = MainnetContracts.getSwapRoute();
        address[5] memory swapPools = MainnetContracts.getSwapPools();
        uint256[5][5] memory swapParams = MainnetContracts.getSwapParams();

        address[] memory stakAssets = IVault(STAK).getAssets();
        address erc4626_2 = stakAssets[1];

        AutoPounder.Config memory config = AutoPounder.Config({
            vault: address(0), // Invalid
            accountant: STAKEDAO_ACCOUNTANT,
            gauge: GAUGE,
            rewardToken: CRV,
            baseAsset: USDC,
            curveRouter: CURVE_ROUTER,
            curvePool2: CURVE_STAK_POOL,
            erc4626_1: YN_USDX,
            erc4626_2: erc4626_2,
            rewardTokenOracle: CHAINLINK_CRV_USD,
            baseAssetOracle: CHAINLINK_USDC_USD,
            swapRoute: swapRoute,
            swapPools: swapPools,
            swapParams: swapParams,
            curvePool2_assetIndex: CURVE_STAK_ASSET_INDEX,
            minOutputBps: 9900,
            maxOracleAge: 86400
        });

        vm.expectRevert(AutoPounder.InvalidVault.selector);
        new AutoPounder(config, deployer);
    }

    /**
     * @notice Test that constructor reverts with zero accountant address
     */
    function test_ConstructorRevertsZeroAccountant() public {
        address[11] memory swapRoute = MainnetContracts.getSwapRoute();
        address[5] memory swapPools = MainnetContracts.getSwapPools();
        uint256[5][5] memory swapParams = MainnetContracts.getSwapParams();

        address[] memory stakAssets = IVault(STAK).getAssets();
        address erc4626_2 = stakAssets[1];

        AutoPounder.Config memory config = AutoPounder.Config({
            vault: STAK,
            accountant: address(0), // Invalid
            gauge: GAUGE,
            rewardToken: CRV,
            baseAsset: USDC,
            curveRouter: CURVE_ROUTER,
            curvePool2: CURVE_STAK_POOL,
            erc4626_1: YN_USDX,
            erc4626_2: erc4626_2,
            rewardTokenOracle: CHAINLINK_CRV_USD,
            baseAssetOracle: CHAINLINK_USDC_USD,
            swapRoute: swapRoute,
            swapPools: swapPools,
            swapParams: swapParams,
            curvePool2_assetIndex: CURVE_STAK_ASSET_INDEX,
            minOutputBps: 9900,
            maxOracleAge: 86400
        });

        vm.expectRevert(AutoPounder.InvalidAccountant.selector);
        new AutoPounder(config, deployer);
    }

    /**
     * @notice Test that constructor reverts with zero oracle address
     */
    function test_ConstructorRevertsZeroOracle() public {
        address[11] memory swapRoute = MainnetContracts.getSwapRoute();
        address[5] memory swapPools = MainnetContracts.getSwapPools();
        uint256[5][5] memory swapParams = MainnetContracts.getSwapParams();

        address[] memory stakAssets = IVault(STAK).getAssets();
        address erc4626_2 = stakAssets[1];

        AutoPounder.Config memory config = AutoPounder.Config({
            vault: STAK,
            accountant: STAKEDAO_ACCOUNTANT,
            gauge: GAUGE,
            rewardToken: CRV,
            baseAsset: USDC,
            curveRouter: CURVE_ROUTER,
            curvePool2: CURVE_STAK_POOL,
            erc4626_1: YN_USDX,
            erc4626_2: erc4626_2,
            rewardTokenOracle: address(0), // Invalid
            baseAssetOracle: CHAINLINK_USDC_USD,
            swapRoute: swapRoute,
            swapPools: swapPools,
            swapParams: swapParams,
            curvePool2_assetIndex: CURVE_STAK_ASSET_INDEX,
            minOutputBps: 9900,
            maxOracleAge: 86400
        });

        vm.expectRevert(AutoPounder.InvalidOracle.selector);
        new AutoPounder(config, deployer);
    }

    // ============================================
    // Access Control Tests
    // ============================================

    /**
     * @notice Test that non-admin cannot call setMinOutputBps
     */
    function test_OnlyAdminCanSetMinOutputBps() public {
        address attacker = makeAddr("attacker");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, autoPounder.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(attacker);
        autoPounder.setMinOutputBps(9500);
    }

    /**
     * @notice Test that non-admin cannot call setMaxOracleAge
     */
    function test_OnlyAdminCanSetMaxOracleAge() public {
        address attacker = makeAddr("attacker");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, autoPounder.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(attacker);
        autoPounder.setMaxOracleAge(3600);
    }

    /**
     * @notice Test that non-admin cannot call recoverToken
     */
    function test_OnlyAdminCanRecoverToken() public {
        address attacker = makeAddr("attacker");

        // Send some USDC to AutoPounder
        deal(USDC, address(autoPounder), 1000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, autoPounder.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(attacker);
        autoPounder.recoverToken(USDC, 1000e6, attacker);
    }

    /**
     * @notice Test that recoverToken reverts with zero destination
     */
    function test_RecoverTokenRevertsZeroDestination() public {
        deal(USDC, address(autoPounder), 1000e6);

        vm.prank(admin);
        vm.expectRevert(AutoPounder.InvalidDestination.selector);
        autoPounder.recoverToken(USDC, 1000e6, address(0));
    }

    // ============================================
    // Edge Cases for minOutputBps
    // ============================================

    /**
     * @notice Test setMinOutputBps at boundary values
     */
    function test_SetMinOutputBpsBoundaries() public {
        vm.startPrank(admin);

        // Should succeed at 0 (no slippage protection)
        autoPounder.setMinOutputBps(0);
        assertEq(autoPounder.minOutputBps(), 0);

        // Should succeed at 10000 (100% = no slippage allowed)
        autoPounder.setMinOutputBps(10000);
        assertEq(autoPounder.minOutputBps(), 10000);

        // Should fail at 10001
        vm.expectRevert(AutoPounder.InvalidBPS.selector);
        autoPounder.setMinOutputBps(10001);

        vm.stopPrank();
    }

    // ============================================
    // COMPOUNDER_ROLE Management Tests
    // ============================================

    /**
     * @notice Test adding multiple compounders
     */
    function test_MultipleCompounders() public {
        address compounder1 = makeAddr("compounder1");
        address compounder2 = makeAddr("compounder2");
        address nonCompounder = makeAddr("nonCompounder");
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        vm.startPrank(admin);
        autoPounder.grantRole(compounderRole, compounder1);
        autoPounder.grantRole(compounderRole, compounder2);
        vm.stopPrank();

        assertEq(autoPounder.getRoleMemberCount(compounderRole), 2, "Should have 2 compounders");
        assertTrue(autoPounder.hasRole(compounderRole, compounder1), "Compounder1 should have role");
        assertTrue(autoPounder.hasRole(compounderRole, compounder2), "Compounder2 should have role");

        // Non-compounder should be rejected
        vm.prank(nonCompounder);
        vm.expectRevert(AutoPounder.Unauthorized.selector);
        autoPounder.compound();

        // First compounder should succeed
        vm.prank(compounder1);
        autoPounder.compound();

        // Note: Second compounder would also be allowed, but we don't call it here
        // because rewards are depleted after first compound. The role check passes.
        assertTrue(autoPounder.hasRole(compounderRole, compounder2), "Compounder2 still has role");
    }

    /**
     * @notice Test revoking compounder role restores permissionless access
     */
    function test_RevokeCompounderRestoresPermissionless() public {
        address compounder = makeAddr("compounder");
        address randomUser = makeAddr("randomUser");
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        // Grant role
        vm.prank(admin);
        autoPounder.grantRole(compounderRole, compounder);

        // Random user cannot compound
        vm.prank(randomUser);
        vm.expectRevert(AutoPounder.Unauthorized.selector);
        autoPounder.compound();

        // Revoke role
        vm.prank(admin);
        autoPounder.revokeRole(compounderRole, compounder);

        // Now anyone can compound again
        assertEq(autoPounder.getRoleMemberCount(compounderRole), 0, "Should have 0 compounders");

        vm.prank(randomUser);
        autoPounder.compound();
    }

    /**
     * @notice Test compounder can renounce their own role
     */
    function test_CompounderCanRenounceRole() public {
        address compounder = makeAddr("compounder");
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        // Grant role
        vm.prank(admin);
        autoPounder.grantRole(compounderRole, compounder);

        // Compounder renounces
        vm.prank(compounder);
        autoPounder.renounceRole(compounderRole, compounder);

        assertFalse(autoPounder.hasRole(compounderRole, compounder), "Compounder should not have role");
        assertEq(autoPounder.getRoleMemberCount(compounderRole), 0, "Should have 0 compounders");
    }

    /**
     * @notice Test enumerating role members
     */
    function test_EnumerateRoleMembers() public {
        address compounder1 = makeAddr("compounder1");
        address compounder2 = makeAddr("compounder2");
        address compounder3 = makeAddr("compounder3");
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        vm.startPrank(admin);
        autoPounder.grantRole(compounderRole, compounder1);
        autoPounder.grantRole(compounderRole, compounder2);
        autoPounder.grantRole(compounderRole, compounder3);
        vm.stopPrank();

        assertEq(autoPounder.getRoleMemberCount(compounderRole), 3);

        // Verify we can enumerate all members
        address member0 = autoPounder.getRoleMember(compounderRole, 0);
        address member1 = autoPounder.getRoleMember(compounderRole, 1);
        address member2 = autoPounder.getRoleMember(compounderRole, 2);

        // All three addresses should be present (order may vary)
        bool hasCompounder1 = (member0 == compounder1 || member1 == compounder1 || member2 == compounder1);
        bool hasCompounder2 = (member0 == compounder2 || member1 == compounder2 || member2 == compounder2);
        bool hasCompounder3 = (member0 == compounder3 || member1 == compounder3 || member2 == compounder3);

        assertTrue(hasCompounder1, "Should contain compounder1");
        assertTrue(hasCompounder2, "Should contain compounder2");
        assertTrue(hasCompounder3, "Should contain compounder3");
    }

    // ============================================
    // Event Emission Tests
    // ============================================

    /**
     * @notice Test MinOutputBpsUpdated event emission
     */
    function test_EmitMinOutputBpsUpdated() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit AutoPounder.MinOutputBpsUpdated(9900, 9500);
        autoPounder.setMinOutputBps(9500);
    }

    /**
     * @notice Test MaxOracleAgeUpdated event emission
     */
    function test_EmitMaxOracleAgeUpdated() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit AutoPounder.MaxOracleAgeUpdated(86400, 7200);
        autoPounder.setMaxOracleAge(7200);
    }

    /**
     * @notice Test TokenRecovered event emission
     */
    function test_EmitTokenRecovered() public {
        deal(USDC, address(autoPounder), 1000e6);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit AutoPounder.TokenRecovered(USDC, 1000e6, admin);
        autoPounder.recoverToken(USDC, 1000e6, admin);
    }

    // ============================================
    // Multiple Admin Tests
    // ============================================

    /**
     * @notice Test multiple admins can coexist
     */
    function test_MultipleAdmins() public {
        address admin2 = makeAddr("admin2");
        bytes32 adminRole = autoPounder.DEFAULT_ADMIN_ROLE();

        // Grant admin role to second admin
        vm.prank(admin);
        autoPounder.grantRole(adminRole, admin2);

        // Both should be able to perform admin actions
        vm.prank(admin);
        autoPounder.setMinOutputBps(9800);
        assertEq(autoPounder.minOutputBps(), 9800);

        vm.prank(admin2);
        autoPounder.setMinOutputBps(9700);
        assertEq(autoPounder.minOutputBps(), 9700);

        // Verify enumeration
        assertEq(autoPounder.getRoleMemberCount(adminRole), 2, "Should have 2 admins");
    }

    /**
     * @notice Test that non-admin cannot grant roles
     */
    function test_NonAdminCannotGrantRoles() public {
        address attacker = makeAddr("attacker");
        address newCompounder = makeAddr("newCompounder");
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, autoPounder.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(attacker);
        autoPounder.grantRole(compounderRole, newCompounder);
    }

    /**
     * @notice Test DEFAULT_ADMIN_ROLE is admin of COMPOUNDER_ROLE
     */
    function test_AdminRoleIsCompounderRoleAdmin() public view {
        bytes32 adminRole = autoPounder.DEFAULT_ADMIN_ROLE();
        bytes32 compounderRole = autoPounder.COMPOUNDER_ROLE();

        assertEq(
            autoPounder.getRoleAdmin(compounderRole), adminRole, "DEFAULT_ADMIN_ROLE should be admin of COMPOUNDER_ROLE"
        );
    }
}

// Import the Chainlink interface for oracle testing
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
