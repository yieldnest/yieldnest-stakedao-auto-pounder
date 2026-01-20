// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console} from "forge-std/console.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/**
 * @title AutoPounder
 * @notice Contract that automates the reward compounding process for StakeDAO vaults
 * @dev Workflow:
 * 1. Claims rewards from StakeDAO accountant via vault processor
 * 2. Transfers reward tokens to this contract via processor
 * 3. Swaps rewards for base asset in Curve pool #1
 * 4. Deposits base asset into ERC4626 vault
 * 5. Single-sided deposit into Curve pool #2
 * 6. Deposits resulting LP tokens back into vault
 * 7. Deposits LP into ERC4626 vault (2nd asset of IVault)
 */
contract AutoPounder {
    // ============================================
    // Structs
    // ============================================
    struct Config {
        address vault;
        address accountant;
        address gauge;
        address rewardToken;
        address baseAsset;
        address curveRouter; // Curve router for swaps
        address curvePool2;
        address erc4626_1;
        address erc4626_2;
        address rewardTokenOracle; // Chainlink oracle for reward token price
        address baseAssetOracle; // Chainlink oracle for base asset price
        address[11] swapRoute; // Route for rewardToken -> baseAsset swap
        address[5] swapPools; // Pools for rewardToken -> baseAsset swap
        uint256[5][5] swapParams; // Swap parameters for Curve router
        int128 curvePool2_assetIndex;
    }

    // ============================================
    // Errors
    // ============================================
    error InvalidVault();
    error InvalidAccountant();
    error InvalidGauge();
    error InvalidRewardToken();
    error InvalidBaseAsset();
    error InvalidCurvePool();
    error InvalidCurveRouter();
    error InvalidERC4626();
    error InvalidOracle();
    error StaleOraclePrice();
    error InsufficientOutput();
    error ProcessorCallFailed(uint256 index);
    error TransferFailed();
    error OnlyOwner();

    // ============================================
    // Events
    // ============================================
    event RewardsClaimed(address indexed vault, uint256 amount);
    event RewardsSwapped(uint256 rewardAmount, uint256 baseAssetAmount);
    event BaseAssetDeposited(uint256 amount, uint256 shares);
    event LiquidityAdded(uint256 assetAmount, uint256 lpTokens);
    event LPDeposited(uint256 lpAmount, uint256 vaultShares);
    event ConfigUpdated(
        address vault,
        address accountant,
        address rewardToken,
        address baseAsset,
        address curvePool1,
        address curvePool2,
        address erc4626_1,
        address erc4626_2
    );

    // ============================================
    // State Variables
    // ============================================
    address public owner;
    address public vault;
    address public accountant;
    address public gauge; // StakeDAO gauge to claim from
    address public rewardToken;
    address public baseAsset;
    address public curveRouter; // Curve router for swaps
    address public curvePool2; // Pool for single-sided deposit
    address public erc4626_1; // ERC4626 for base asset
    address public erc4626_2; // ERC4626 for LP tokens (2nd asset in vault)

    // Chainlink oracles
    address public rewardTokenOracle; // Chainlink price feed for reward token
    address public baseAssetOracle; // Chainlink price feed for base asset

    // Curve swap route parameters
    address[11] public swapRoute; // Route for rewardToken -> baseAsset swap
    address[5] public swapPools; // Pools for rewardToken -> baseAsset swap
    uint256[5][5] public swapParams; // Swap parameters for Curve router

    // Curve pool parameters
    int128 public curvePool2_assetIndex;

    // Slippage protection (basis points, e.g., 9900 = 99% = 1% slippage)
    uint256 public minOutputBps = 9900;

    // Oracle staleness threshold (e.g., 86400 = 24 hours)
    uint256 public maxOracleAge = 86400;

    // ============================================
    // Modifiers
    // ============================================
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // ============================================
    // Constructor
    // ============================================
    constructor(Config memory config) {
        owner = msg.sender;
        vault = config.vault;
        accountant = config.accountant;
        gauge = config.gauge;
        rewardToken = config.rewardToken;
        baseAsset = config.baseAsset;
        curveRouter = config.curveRouter;
        curvePool2 = config.curvePool2;
        erc4626_1 = config.erc4626_1;
        erc4626_2 = config.erc4626_2;
        rewardTokenOracle = config.rewardTokenOracle;
        baseAssetOracle = config.baseAssetOracle;
        swapRoute = config.swapRoute;
        swapPools = config.swapPools;
        swapParams = config.swapParams;
        curvePool2_assetIndex = config.curvePool2_assetIndex;

        _validateConfig();
    }

    // ============================================
    // External Functions
    // ============================================

    /**
     * @notice Executes the full auto-compounding workflow
     * @dev All minimum outputs are calculated internally using oracle prices and minOutputBps
     */
    function compound() external {
        console.log("=== Starting compound() ===");

        // Step 1: Claim rewards from accountant via processor
        console.log("Step 1: Claiming rewards...");
        uint256 rewardAmount = _claimRewards();
        console.log("Claimed reward amount:", rewardAmount);
        emit RewardsClaimed(vault, rewardAmount);

        // Step 2: Transfer rewards to this contract via processor
        console.log("Step 2: Transferring rewards to self...");
        _transferRewardsToSelf(rewardAmount);
        console.log("Rewards transferred successfully");

        // Step 3: Swap rewards for base asset in Curve pool #1
        // minOut is calculated inside using oracle prices
        console.log("Step 3: Swapping rewards for base asset...");
        uint256 baseAssetAmount = _swapRewardForBaseAsset(rewardAmount);
        console.log("Base asset amount received:", baseAssetAmount);
        emit RewardsSwapped(rewardAmount, baseAssetAmount);

        // Step 4: Deposit base asset into ERC4626 vault #1
        console.log("Step 4: Depositing base asset to ERC4626_1...");
        uint256 intermediateShares = _depositToERC4626_1(baseAssetAmount);
        console.log("Intermediate shares received:", intermediateShares);
        emit BaseAssetDeposited(baseAssetAmount, intermediateShares);

        // Step 5: Single-sided deposit into Curve pool #2
        console.log("Step 5: Adding liquidity single-sided...");
        uint256 lpTokenAmount = _addLiquiditySingleSided(intermediateShares);
        console.log("LP token amount received:", lpTokenAmount);
        emit LiquidityAdded(intermediateShares, lpTokenAmount);

        // Step 6: Transfer LP tokens back to vault via processor
        console.log("Step 6: Transferring LP tokens to vault...");
        _transferLPToVault(lpTokenAmount);
        console.log("LP tokens transferred successfully");

        // Step 7: Deposit LP into ERC4626 #2 (2nd asset in vault) via processor
        console.log("Step 7: Depositing LP to ERC4626_2...");
        uint256 finalShares = _depositLPToVault(lpTokenAmount);
        console.log("Final shares received:", finalShares);
        emit LPDeposited(lpTokenAmount, finalShares);

        console.log("=== Compound completed successfully ===");
    }

    /**
     * @notice Updates configuration parameters
     */
    function updateConfig(Config memory config) external onlyOwner {
        vault = config.vault;
        accountant = config.accountant;
        gauge = config.gauge;
        rewardToken = config.rewardToken;
        baseAsset = config.baseAsset;
        curveRouter = config.curveRouter;
        curvePool2 = config.curvePool2;
        erc4626_1 = config.erc4626_1;
        erc4626_2 = config.erc4626_2;
        rewardTokenOracle = config.rewardTokenOracle;
        baseAssetOracle = config.baseAssetOracle;
        swapRoute = config.swapRoute;
        swapPools = config.swapPools;
        swapParams = config.swapParams;
        curvePool2_assetIndex = config.curvePool2_assetIndex;

        _validateConfig();

        emit ConfigUpdated(
            config.vault,
            config.accountant,
            config.rewardToken,
            config.baseAsset,
            config.curveRouter,
            config.curvePool2,
            config.erc4626_1,
            config.erc4626_2
        );
    }

    /**
     * @notice Updates minimum output basis points for slippage protection
     * @param _minOutputBps New minimum output in basis points (e.g., 9900 = 99%)
     */
    function setMinOutputBps(uint256 _minOutputBps) external onlyOwner {
        require(_minOutputBps <= 10000, "Invalid BPS");
        minOutputBps = _minOutputBps;
    }

    /**
     * @notice Updates maximum oracle age threshold
     * @param _maxOracleAge New maximum oracle age in seconds
     */
    function setMaxOracleAge(uint256 _maxOracleAge) external onlyOwner {
        maxOracleAge = _maxOracleAge;
    }

    /**
     * @notice Transfers ownership to a new address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    /**
     * @notice Emergency function to recover stuck tokens
     */
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }

    // ============================================
    // Internal Functions
    // ============================================

    /**
     * @dev Step 1: Claims rewards from accountant via vault processor
     */
    function _claimRewards() internal returns (uint256) {
        // Check balance before claim
        uint256 balanceBefore = IERC20(rewardToken).balanceOf(vault);

        // Prepare processor call to claim(address[],bytes[]) on accountant
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);

        // Prepare arrays for claim function arguments with gauge address
        address[] memory claimTargets = new address[](1);
        bytes[] memory claimData = new bytes[](1);

        claimTargets[0] = gauge;
        claimData[0] = ""; // Empty bytes for the gauge

        targets[0] = accountant;
        values[0] = 0;
        data[0] = abi.encodeWithSignature("claim(address[],bytes[])", claimTargets, claimData);

        // Execute via vault processor (claim() returns nothing)
        IVault(vault).processor(targets, values, data);

        // Check balance after claim to determine amount claimed
        uint256 balanceAfter = IERC20(rewardToken).balanceOf(vault);

        // Return the difference (amount claimed)
        return balanceAfter - balanceBefore;
    }

    /**
     * @dev Step 2: Transfers reward tokens from vault to this contract
     */
    function _transferRewardsToSelf(uint256 amount) internal {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = rewardToken;
        values[0] = 0;
        data[0] = abi.encodeWithSignature("transfer(address,uint256)", address(this), amount);

        bytes[] memory results = IVault(vault).processor(targets, values, data);

        if (results.length == 0) revert ProcessorCallFailed(1);
        if (!abi.decode(results[0], (bool))) revert TransferFailed();
    }

    /**
     * @dev Step 3: Swaps reward token for base asset using Curve router
     */
    function _swapRewardForBaseAsset(uint256 amount) internal returns (uint256) {
        // Approve Curve router to spend reward tokens
        IERC20(rewardToken).approve(curveRouter, amount);

        // Calculate minimum output using oracle prices and slippage protection
        uint256 expectedOutput = _calculateExpectedOutput(amount, rewardTokenOracle, baseAssetOracle);
        uint256 minOut = (expectedOutput * minOutputBps) / 10000;

        // Execute Curve router exchange using configured swap params
        // exchange(address[11] _route, uint256[5][5] _swap_params, uint256 _amount, uint256 _min_dy, address[5] _pools)
        bytes memory callData = abi.encodeWithSignature(
            "exchange(address[11],uint256[5][5],uint256,uint256,address[5])",
            swapRoute,
            swapParams,
            amount,
            minOut,
            swapPools
        );

        (bool success, bytes memory result) = curveRouter.call(callData);
        require(success, "Curve router swap failed");

        return abi.decode(result, (uint256));
    }

    /**
     * @dev Step 4: Deposits base asset into ERC4626 vault
     */
    function _depositToERC4626_1(uint256 amount) internal returns (uint256) {
        // Approve ERC4626 to spend base asset
        IERC20(baseAsset).approve(erc4626_1, amount);

        // Deposit and receive shares
        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", amount, address(this));

        (bool success, bytes memory result) = erc4626_1.call(callData);
        require(success, "ERC4626 deposit failed");

        return abi.decode(result, (uint256));
    }

    /**
     * @dev Step 5: Single-sided deposit into Curve pool #2
     * @param amount Amount of erc4626_1 shares to deposit
     */
    function _addLiquiditySingleSided(uint256 amount) internal returns (uint256) {
        // Approve Curve pool to spend the ERC4626 shares (not the underlying asset)
        IERC20(erc4626_1).approve(curvePool2, amount);

        // For single-sided deposit, create amounts array with only one non-zero value
        // This assumes a 2-token pool; adjust if needed
        uint256[] memory amounts = new uint256[](2);
        amounts[uint256(uint128(curvePool2_assetIndex))] = amount;

        // Call add_liquidity on the Curve pool with dynamic array (no ETH needed)
        // Using 0 for min_lp_out temporarily for testing
        return ICurvePool(curvePool2).add_liquidity{value: 0}(amounts, 0);
    }

    /**
     * @dev Step 6: Transfers LP tokens from this contract to vault
     */
    function _transferLPToVault(uint256 amount) internal {
        // Get LP token address from Curve pool
        address lpToken = ICurvePool(curvePool2).lp_token();

        // Transfer LP tokens to vault
        bool success = IERC20(lpToken).transfer(vault, amount);
        if (!success) revert TransferFailed();
    }

    /**
     * @dev Step 7: Deposits LP tokens into ERC4626 #2 via vault processor
     */
    function _depositLPToVault(uint256 amount) internal returns (uint256) {
        // Get LP token address
        address lpToken = ICurvePool(curvePool2).lp_token();

        // Prepare processor calls to approve and deposit
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);

        // First call: approve ERC4626_2 to spend LP tokens
        targets[0] = lpToken;
        values[0] = 0;
        data[0] = abi.encodeWithSignature("approve(address,uint256)", erc4626_2, amount);

        // Second call: deposit LP tokens into ERC4626_2
        targets[1] = erc4626_2;
        values[1] = 0;
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, vault);

        // Execute via vault processor
        bytes[] memory results = IVault(vault).processor(targets, values, data);

        if (results.length < 2) revert ProcessorCallFailed(2);

        // Return shares received from deposit
        return abi.decode(results[1], (uint256));
    }

    /**
     * @dev Calculates expected output amount using Chainlink oracles
     * @param inputAmount Amount of input token
     * @param inputOracle Chainlink oracle for input token
     * @param outputOracle Chainlink oracle for output token
     * @return expectedOutput Expected amount of output token
     */
    function _calculateExpectedOutput(uint256 inputAmount, address inputOracle, address outputOracle)
        internal
        view
        returns (uint256 expectedOutput)
    {
        // Get and validate input price
        (, int256 inputPrice,, uint256 updatedAt1,) = AggregatorV3Interface(inputOracle).latestRoundData();
        require(inputPrice > 0, "Invalid input price");
        if (block.timestamp - updatedAt1 > maxOracleAge) revert StaleOraclePrice();

        // Get and validate output price
        (, int256 outputPrice,, uint256 updatedAt2,) = AggregatorV3Interface(outputOracle).latestRoundData();
        require(outputPrice > 0, "Invalid output price");
        if (block.timestamp - updatedAt2 > maxOracleAge) revert StaleOraclePrice();

        // Get oracle decimals
        uint8 inputOracleDecimals = AggregatorV3Interface(inputOracle).decimals();
        uint8 outputOracleDecimals = AggregatorV3Interface(outputOracle).decimals();

        // Get token decimals (CRV=18, USDC=6)
        uint8 inputTokenDecimals = IERC20Metadata(rewardToken).decimals();
        uint8 outputTokenDecimals = IERC20Metadata(baseAsset).decimals();

        // Calculate: (inputAmount * inputPrice) / outputPrice
        // Then adjust for oracle decimals and token decimals
        uint256 priceRatio = (uint256(inputPrice) * 10 ** outputOracleDecimals) / uint256(outputPrice);

        // Adjust for token decimals: convert from input token decimals to output token decimals
        if (inputTokenDecimals >= outputTokenDecimals) {
            expectedOutput = (inputAmount * priceRatio)
                / (10 ** inputOracleDecimals * 10 ** (inputTokenDecimals - outputTokenDecimals));
        } else {
            expectedOutput = (inputAmount * priceRatio * 10 ** (outputTokenDecimals - inputTokenDecimals))
                / 10 ** inputOracleDecimals;
        }
    }

    /**
     * @dev Validates that configuration addresses are non-zero
     */
    function _validateConfig() internal view {
        if (vault == address(0)) revert InvalidVault();
        if (accountant == address(0)) revert InvalidAccountant();
        if (gauge == address(0)) revert InvalidGauge();
        if (rewardToken == address(0)) revert InvalidRewardToken();
        if (baseAsset == address(0)) revert InvalidBaseAsset();
        if (curveRouter == address(0)) revert InvalidCurveRouter();
        if (curvePool2 == address(0)) revert InvalidCurvePool();
        if (erc4626_1 == address(0)) revert InvalidERC4626();
        if (erc4626_2 == address(0)) revert InvalidERC4626();
        if (rewardTokenOracle == address(0)) revert InvalidOracle();
        if (baseAssetOracle == address(0)) revert InvalidOracle();
        if (swapRoute[0] == address(0)) revert InvalidCurveRouter();
        if (swapPools[0] == address(0)) revert InvalidCurveRouter();
    }
}

// ============================================
// Interfaces
// ============================================

interface IVault {
    function processor(address[] calldata targets, uint256[] calldata values, bytes[] calldata data)
        external
        returns (bytes[] memory);
}

interface IERC4626 {
    function asset() external view returns (address);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}

interface ICurvePool {
    function add_liquidity(uint256[] calldata amounts, uint256 min_mint_amount) external payable returns (uint256);
    function lp_token() external view returns (address);
}
