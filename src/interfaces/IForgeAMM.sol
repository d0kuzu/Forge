// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IForgeAMM — Interface for the custom Constant-Product AMM
/// @notice Pairs ForgeCoin (ERC20) with Dust (ForgeItems ERC1155 id=0)
/// @dev Math functions use inline Yul/Assembly for gas optimization
interface IForgeAMM {
    error InsufficientLiquidity();
    error InsufficientInputAmount();
    error InsufficientOutputAmount();
    error SlippageExceeded();
    error DeadlineExpired();
    error InvalidK();
    error ZeroAddress();
    error Reentrancy();

    event LiquidityAdded(address indexed provider, uint256 forgeCoinAmount, uint256 dustAmount, uint256 lpTokens);
    event LiquidityRemoved(address indexed provider, uint256 forgeCoinAmount, uint256 dustAmount, uint256 lpTokens);
    event Swap(address indexed user, bool forgeCoinToDust, uint256 amountIn, uint256 amountOut);
    event FeeCollected(uint256 feeAmount);
    event Sync(uint256 reserveForgeCoin, uint256 reserveDust);

    /// @notice Add liquidity to the ForgeCoin/Dust pool
    /// @param forgeCoinAmount  Amount of ForgeCoin to deposit
    /// @param dustAmount       Amount of Dust to deposit
    /// @param minLPTokens      Minimum LP tokens to receive (slippage protection)
    /// @param deadline         Transaction deadline timestamp
    /// @return lpTokens        Amount of LP tokens minted
    function addLiquidity(uint256 forgeCoinAmount, uint256 dustAmount, uint256 minLPTokens, uint256 deadline)
        external returns (uint256 lpTokens);

    /// @notice Remove liquidity from the pool
    /// @param lpTokens         LP tokens to burn
    /// @param minForgeCoin     Minimum ForgeCoin to receive
    /// @param minDust          Minimum Dust to receive
    /// @param deadline         Transaction deadline timestamp
    /// @return forgeCoinOut    ForgeCoin amount returned
    /// @return dustOut         Dust amount returned
    function removeLiquidity(uint256 lpTokens, uint256 minForgeCoin, uint256 minDust, uint256 deadline)
        external returns (uint256 forgeCoinOut, uint256 dustOut);

    /// @notice Swap ForgeCoin for Dust
    function swapForgeCoinForDust(uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        external returns (uint256 amountOut);

    /// @notice Swap Dust for ForgeCoin
    function swapDustForForgeCoin(uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        external returns (uint256 amountOut);

    /// @notice Get current pool reserves
    function getReserves() external view returns (uint256 reserveForgeCoin, uint256 reserveDust);

    /// @notice Calculate output amount given input (pure, Yul-optimized)
    /// @dev Implements x*y=k with 0.3% fee
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external pure returns (uint256 amountOut);

    /// @notice Calculate required input amount for desired output (pure, Yul-optimized)
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external pure returns (uint256 amountIn);

    /// @notice Quote equivalent value between reserves
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        external pure returns (uint256 amountB);
}
