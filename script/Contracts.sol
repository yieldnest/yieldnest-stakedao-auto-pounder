/* solhint-disable one-contract-per-file */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IContracts {
    function WETH() external pure returns (address);
}

library MainnetContracts {
    // ============================================
    // YieldNest Contracts
    // ============================================

    /// @notice STAK vault - Main YieldNest vault
    address public constant STAK = 0xD1573de52fFF44dd92D275e20Fdab0296CCFF141;

    /// @notice ynRWAx - ERC4626 vault for base asset (USDC)
    /// @dev This is erc4626_1 in AutoPounder
    address public constant YN_RWAX = 0x3210ab8b1db4bf6f45b9D3b4cf59e0cD8C2E4E7A; // TODO: Verify actual address

    // ============================================
    // StakeDAO Contracts
    // ============================================

    /// @notice StakeDAO Accountant contract for reward claims
    address public constant STAKEDAO_ACCOUNTANT = 0x93b4B9bd266fFA8AF68e39EDFa8cFe2A62011Ce0;

    /// @notice StakeDAO gauge for staking
    address public constant GAUGE = 0xb341f2d7e56524B52E3F7989A2E59366e1e5F18F;

    // ============================================
    // Token Addresses
    // ============================================

    /// @notice CRV token - Reward token from StakeDAO
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice USDC token - Base asset for compounding
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice WETH - Wrapped Ether
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // ============================================
    // Curve Pools
    // ============================================

    /// @notice Curve CRV/USDC pool for swapping rewards to base asset
    /// @dev This is curvePool1 in AutoPounder - TriCRV pool
    address public constant CURVE_CRV_USDC_POOL = 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;

    /// @notice Curve pool for single-sided deposit to get LP tokens
    /// @dev This is curvePool2 in AutoPounder - need to identify correct pool
    address public constant CURVE_STAK_POOL = 0xFFd3b4D343A8964a5C3c1caAc20f319C41A97BFF; // TODO: Verify STAK pool address

    // Curve pool indices for CRV/USDC pool
    /// @notice Index of USDC in the CRV/USDC pool
    int128 public constant CURVE_CRV_USDC_USDC_INDEX = 0;

    /// @notice Index of CRV in the CRV/USDC pool
    int128 public constant CURVE_CRV_USDC_CRV_INDEX = 1;

    /// @notice Index for single-sided deposit in STAK pool
    int128 public constant CURVE_STAK_ASSET_INDEX = 0;

    // ============================================
    // Chainlink Oracles
    // ============================================

    /// @notice Chainlink CRV/USD price feed
    address public constant CHAINLINK_CRV_USD = 0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f;

    /// @notice Chainlink USDC/USD price feed
    address public constant CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
}
