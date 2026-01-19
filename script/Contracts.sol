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
    address public constant YN_RWAX = 0x01Ba69727E2860b37bc1a2bd56999c1aFb4C15D8; // TODO: Verify actual address

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
    // Curve Contracts
    // ============================================

    /// @notice Curve Router for multi-hop swaps
    address public constant CURVE_ROUTER = 0x45312ea0eFf7E09C83CBE249fa1d7598c4C8cd4e;

    /// @notice Curve pool for single-sided deposit to get LP tokens
    /// @dev This is curvePool2 in AutoPounder
    address public constant CURVE_STAK_POOL = 0xFFd3b4D343A8964a5C3c1caAc20f319C41A97BFF;

    /// @notice Index for single-sided deposit in STAK pool
    int128 public constant CURVE_STAK_ASSET_INDEX = 0;

    // Curve swap route for CRV -> USDC
    // Route: CRV -> TriCRV pool -> crvUSD -> crvUSD/USDC pool -> USDC
    function getSwapRoute() internal pure returns (address[11] memory route) {
        route[0] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV
        route[1] = 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14; // TriCRV pool
        route[2] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // crvUSD
        route[3] = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E; // crvUSD/USDC pool
        route[4] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        // Rest are zero addresses
    }

    // Curve swap pools for CRV -> USDC
    function getSwapPools() internal pure returns (address[5] memory pools) {
        pools[0] = 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14; // TriCRV pool
        pools[1] = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E; // crvUSD/USDC pool
        // Rest are zero addresses
    }

    // ============================================
    // Chainlink Oracles
    // ============================================

    /// @notice Chainlink CRV/USD price feed
    address public constant CHAINLINK_CRV_USD = 0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f;

    /// @notice Chainlink USDC/USD price feed
    address public constant CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
}
