// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AutoPounder} from "../../src/AutoPounder.sol";
import {MainnetContracts} from "../../script/Contracts.sol";
import {MainnetActors} from "../../script/Actors.sol";

interface IVault {
    enum ParamType {
        UINT256,
        ADDRESS
    }

    struct ParamRule {
        ParamType paramType;
        bool isArray;
        address[] allowList;
    }

    struct FunctionRule {
        bool isActive;
        ParamRule[] paramRules;
        address validator; // IValidator
    }

    function getAssets() external view returns (address[] memory);
    function processor(address[] calldata targets, uint256[] calldata values, bytes[] calldata data)
        external
        returns (bytes[] memory);
    function grantRole(bytes32 role, address account) external;
    function PROCESSOR_ROLE() external view returns (bytes32);
    function PROCESSOR_MANAGER_ROLE() external view returns (bytes32);
    function setProcessorRule(address target, bytes4 functionSig, FunctionRule calldata rule) external;
}

contract BaseIntegrationTest is Test {
    AutoPounder public autoPounder;
    MainnetActors public actors;

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
        // Fork mainnet for integration testing
        // vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        // Deploy actors contract to get admin address
        actors = new MainnetActors();

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

        // Grant PROCESSOR_ROLE to AutoPounder
        // Note: In a real deployment, the vault admin would need to grant this role
        bytes32 processorRole = IVault(STAK).PROCESSOR_ROLE();
        bytes32 processorManagerRole = IVault(STAK).PROCESSOR_MANAGER_ROLE();

        vm.startPrank(actors.ADMIN());

        // Grant PROCESSOR_ROLE to AutoPounder
        IVault(STAK).grantRole(processorRole, address(autoPounder));

        // Grant PROCESSOR_MANAGER_ROLE to ADMIN so we can create rules
        IVault(STAK).grantRole(processorManagerRole, actors.ADMIN());

        // Create rule to allow transferring CRV tokens to AutoPounder
        // This allows: CRV.transfer(autoPounder, amount)
        bytes4 transferSig = bytes4(keccak256("transfer(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        // First param: address recipient - restricted to AutoPounder only
        address[] memory allowList = new address[](1);
        allowList[0] = address(autoPounder);
        paramRules[0] = IVault.ParamRule({
            paramType: IVault.ParamType.ADDRESS,
            isArray: false,
            allowList: allowList
        });

        // Second param: uint256 amount - no restrictions
        paramRules[1] = IVault.ParamRule({
            paramType: IVault.ParamType.UINT256,
            isArray: false,
            allowList: new address[](0)
        });

        IVault.FunctionRule memory transferRule = IVault.FunctionRule({
            isActive: true,
            paramRules: paramRules,
            validator: address(0)
        });

        IVault(STAK).setProcessorRule(CRV, transferSig, transferRule);

        vm.stopPrank();
    }
}
