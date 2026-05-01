// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AMMath — Yul/Assembly-optimized math for Constant-Product AMM
/// @notice All core price calculation, fee, and utility functions implemented in inline Yul
/// @dev Gas-optimized: bypasses Solidity's checked arithmetic where safe.
///      Overflow protection is maintained via explicit checks where necessary.
library AMMath {
    // ============================================================
    //                      CUSTOM ERRORS
    // ============================================================

    error MathOverflow();
    error DivisionByZero();
    error InsufficientInputAmount();
    error InsufficientLiquidity();
    error InsufficientOutputAmount();

    // ============================================================
    //                  SWAP CALCULATIONS (Yul)
    // ============================================================

    /// @notice Calculate output amount given input amount and reserves (with 0.3% fee)
    /// @dev Formula: amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
    ///      Fully implemented in inline Yul for gas optimization
    /// @param amountIn     Input token amount
    /// @param reserveIn    Reserve of the input token
    /// @param reserveOut   Reserve of the output token
    /// @return amountOut   Output token amount after fee
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        assembly {
            // Validate inputs
            if iszero(amountIn) {
                // revert InsufficientInputAmount()
                mstore(0x00, 0x51969a5f) // selector for InsufficientInputAmount()
                revert(0x1c, 0x04)
            }
            if or(iszero(reserveIn), iszero(reserveOut)) {
                // revert InsufficientLiquidity()
                mstore(0x00, 0xbb55fd27) // selector for InsufficientLiquidity()
                revert(0x1c, 0x04)
            }

            // amountInWithFee = amountIn * 997
            let amountInWithFee := mul(amountIn, 997)

            // Check for overflow: amountIn * 997
            if iszero(eq(div(amountInWithFee, 997), amountIn)) {
                mstore(0x00, 0x35278d12) // selector for MathOverflow()
                revert(0x1c, 0x04)
            }

            // numerator = amountInWithFee * reserveOut
            let numerator := mul(amountInWithFee, reserveOut)

            // Check for overflow: amountInWithFee * reserveOut
            if iszero(eq(div(numerator, reserveOut), amountInWithFee)) {
                mstore(0x00, 0x35278d12)
                revert(0x1c, 0x04)
            }

            // denominator = reserveIn * 1000 + amountInWithFee
            let reserveIn1000 := mul(reserveIn, 1000)

            // Check overflow: reserveIn * 1000
            if iszero(eq(div(reserveIn1000, 1000), reserveIn)) {
                mstore(0x00, 0x35278d12)
                revert(0x1c, 0x04)
            }

            let denominator := add(reserveIn1000, amountInWithFee)

            // Check overflow: addition
            if lt(denominator, reserveIn1000) {
                mstore(0x00, 0x35278d12)
                revert(0x1c, 0x04)
            }

            // amountOut = numerator / denominator
            amountOut := div(numerator, denominator)
        }
    }

    /// @notice Calculate required input amount for desired output (with 0.3% fee)
    /// @dev Formula: amountIn = (reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997) + 1
    ///      Fully implemented in inline Yul
    /// @param amountOut    Desired output amount
    /// @param reserveIn    Reserve of the input token
    /// @param reserveOut   Reserve of the output token
    /// @return amountIn    Required input amount
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        assembly {
            // Validate inputs
            if iszero(amountOut) {
                mstore(0x00, 0x42301c23) // selector for InsufficientOutputAmount()
                revert(0x1c, 0x04)
            }
            if or(iszero(reserveIn), iszero(reserveOut)) {
                mstore(0x00, 0xbb55fd27)
                revert(0x1c, 0x04)
            }
            // amountOut must be less than reserveOut
            if iszero(lt(amountOut, reserveOut)) {
                mstore(0x00, 0xbb55fd27)
                revert(0x1c, 0x04)
            }

            // numerator = reserveIn * amountOut * 1000
            let step1 := mul(reserveIn, amountOut)
            if iszero(eq(div(step1, amountOut), reserveIn)) {
                mstore(0x00, 0x35278d12)
                revert(0x1c, 0x04)
            }
            let numerator := mul(step1, 1000)
            if iszero(eq(div(numerator, 1000), step1)) {
                mstore(0x00, 0x35278d12)
                revert(0x1c, 0x04)
            }

            // denominator = (reserveOut - amountOut) * 997
            let diff := sub(reserveOut, amountOut)
            let denominator := mul(diff, 997)
            if iszero(eq(div(denominator, 997), diff)) {
                mstore(0x00, 0x35278d12)
                revert(0x1c, 0x04)
            }

            // amountIn = numerator / denominator + 1  (round up)
            amountIn := add(div(numerator, denominator), 1)
        }
    }

    /// @notice Quote equivalent value between reserves (no fee)
    /// @dev Formula: amountB = (amountA * reserveB) / reserveA
    ///      Used for calculating proportional liquidity amounts
    /// @param amountA     Amount of token A
    /// @param reserveA    Reserve of token A
    /// @param reserveB    Reserve of token B
    /// @return amountB    Equivalent amount of token B
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        assembly {
            if iszero(amountA) {
                mstore(0x00, 0x51969a5f)
                revert(0x1c, 0x04)
            }
            if or(iszero(reserveA), iszero(reserveB)) {
                mstore(0x00, 0xbb55fd27)
                revert(0x1c, 0x04)
            }

            // amountB = (amountA * reserveB) / reserveA
            let product := mul(amountA, reserveB)
            if iszero(eq(div(product, reserveB), amountA)) {
                mstore(0x00, 0x35278d12)
                revert(0x1c, 0x04)
            }

            amountB := div(product, reserveA)
        }
    }

    // ============================================================
    //                  UTILITY MATH (Yul)
    // ============================================================

    /// @notice Integer square root using Babylonian method (Yul-optimized)
    /// @dev Used for calculating initial LP tokens: sqrt(amount0 * amount1)
    /// @param y    The value to compute the square root of
    /// @return z   The floor square root of y
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        assembly {
            switch gt(y, 3)
            case 1 {
                z := y
                // Initial guess: x = y / 2 + 1
                let x := add(div(y, 2), 1)

                // Babylonian method: iterate until convergence
                // x_new = (x + y/x) / 2
                for {} lt(x, z) {} {
                    z := x
                    x := div(add(x, div(y, x)), 2)
                }
            }
            default {
                if iszero(iszero(y)) {
                    z := 1
                }
                // if y == 0, z remains 0
            }
        }
    }

    /// @notice Safe multiplication with overflow check (Yul)
    /// @param a    First operand
    /// @param b    Second operand
    /// @return c   Product a * b
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        assembly {
            switch iszero(a)
            case 1 {
                c := 0
            }
            default {
                c := mul(a, b)
                if iszero(eq(div(c, a), b)) {
                    mstore(0x00, 0x35278d12) // MathOverflow()
                    revert(0x1c, 0x04)
                }
            }
        }
    }

    /// @notice Minimum of two values (Yul)
    function min(uint256 a, uint256 b) internal pure returns (uint256 result) {
        assembly {
            result := a
            if lt(b, a) {
                result := b
            }
        }
    }
}
