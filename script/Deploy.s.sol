// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AutoPounder} from "../src/AutoPounder.sol";
import {MainnetContracts} from "./Contracts.sol";

/**
 * @title Deploy
 * @notice Deployment script for AutoPounder contract
 * @dev Run with: forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify
 */
contract Deploy is Script {
    function run() external returns (AutoPounder) {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying AutoPounder with account:", deployer);
        console.log("Account balance:", deployer.balance);

        // Get vault assets to determine erc4626_2
        address[] memory stakAssets = IVault(MainnetContracts.STAK).getAssets();
        require(stakAssets.length >= 2, "STAK vault doesn't have 2 assets");
        address erc4626_2 = stakAssets[1];

        console.log("STAK vault asset 0 (erc4626_1):", stakAssets[0]);
        console.log("STAK vault asset 1 (erc4626_2):", erc4626_2);

        // Get swap route and pools
        address[11] memory swapRoute = MainnetContracts.getSwapRoute();
        address[5] memory swapPools = MainnetContracts.getSwapPools();

        // Configure swap params: [i, j, swap_type, pool_type, n_coins] for each hop
        // Values: 2,0,1,3,0,1,0,1,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        uint256[5][5] memory swapParams;
        swapParams[0] = [uint256(2), uint256(0), uint256(1), uint256(3), uint256(0)];
        swapParams[1] = [uint256(1), uint256(0), uint256(1), uint256(1), uint256(2)];
        swapParams[2] = [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)];
        swapParams[3] = [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)];
        swapParams[4] = [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)];

        // Build AutoPounder configuration
        AutoPounder.Config memory config = AutoPounder.Config({
            vault: MainnetContracts.STAK,
            accountant: MainnetContracts.STAKEDAO_ACCOUNTANT,
            gauge: MainnetContracts.GAUGE,
            rewardToken: MainnetContracts.CRV,
            baseAsset: MainnetContracts.USDC,
            curveRouter: MainnetContracts.CURVE_ROUTER,
            curvePool2: MainnetContracts.CURVE_STAK_POOL,
            erc4626_1: MainnetContracts.YN_USDX,
            erc4626_2: erc4626_2,
            rewardTokenOracle: MainnetContracts.CHAINLINK_CRV_USD,
            baseAssetOracle: MainnetContracts.CHAINLINK_USDC_USD,
            swapRoute: swapRoute,
            swapPools: swapPools,
            swapParams: swapParams,
            curvePool2_assetIndex: MainnetContracts.CURVE_STAK_ASSET_INDEX,
            minOutputBps: 9900, // 99% = 1% slippage tolerance
            maxOracleAge: 86400 // 24 hours
        });

        vm.startBroadcast(deployerPrivateKey);

        // Deploy AutoPounder
        AutoPounder autoPounder = new AutoPounder(config);

        vm.stopBroadcast();

        console.log("AutoPounder deployed at:", address(autoPounder));
        console.log("");
        console.log("=== Configuration ===");
        console.log("Vault:", autoPounder.vault());
        console.log("Accountant:", autoPounder.accountant());
        console.log("Gauge:", autoPounder.gauge());
        console.log("Reward Token (CRV):", autoPounder.rewardToken());
        console.log("Base Asset (USDC):", autoPounder.baseAsset());
        console.log("Curve Router:", autoPounder.curveRouter());
        console.log("Curve Pool 2:", autoPounder.curvePool2());
        console.log("ERC4626_1 (ynUSDx):", autoPounder.erc4626_1());
        console.log("ERC4626_2:", autoPounder.erc4626_2());
        console.log("Reward Token Oracle:", autoPounder.rewardTokenOracle());
        console.log("Base Asset Oracle:", autoPounder.baseAssetOracle());
        console.log("Min Output BPS:", autoPounder.minOutputBps());
        console.log("Max Oracle Age:", autoPounder.maxOracleAge());
        console.log("Owner:", autoPounder.owner());
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Vault admin must grant PROCESSOR_ROLE to AutoPounder:");
        console.log("   IVault(STAK).grantRole(PROCESSOR_ROLE, %s)", address(autoPounder));
        console.log("");
        console.log("2. Vault admin must grant PROCESSOR_MANAGER_ROLE to themselves (if not already):");
        console.log("   IVault(STAK).grantRole(PROCESSOR_MANAGER_ROLE, <admin>)");
        console.log("");
        console.log("3. Create processor rule to allow CRV transfers to AutoPounder:");
        console.log("   IVault(STAK).setProcessorRule(CRV, transfer(address,uint256), <rule>)");

        return autoPounder;
    }
}

interface IVault {
    function getAssets() external view returns (address[] memory);
}
