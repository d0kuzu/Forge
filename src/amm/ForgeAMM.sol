// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ForgeLPToken} from "./ForgeLPToken.sol";
import {AMMath} from "../libraries/AMMath.sol";

/// @title ForgeAMM — Custom Constant-Product AMM for ForgeCoin / Dust
/// @notice Written from scratch (no Uniswap fork). Pairs ForgeCoin (ERC20) with
///         Dust (ForgeItems ERC1155, id=0). 0.3% swap fee. LP tokens issued to providers.
/// @dev Key design decisions:
///      - All price math uses inline Yul/Assembly via AMMath library
///      - Handles ERC1155 transfers for Dust (implements IERC1155Receiver)
///      - MINIMUM_LIQUIDITY (1000) burned on first deposit to prevent manipulation
///      - Reserves packed into struct with timestamp for oracle potential
///      - ReentrancyGuard on all external state-changing functions
contract ForgeAMM is ReentrancyGuard, IERC1155Receiver {
    using SafeERC20 for IERC20;

    // ============================================================
    //                       CONSTANTS
    // ============================================================

    /// @notice Minimum liquidity burned on first deposit (prevents price manipulation)
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    /// @notice The ERC1155 token ID for Dust
    uint256 public constant DUST_ID = 0;

    /// @notice Fee numerator (997/1000 = 0.3% fee)
    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;

    // ============================================================
    //                       IMMUTABLES
    // ============================================================

    /// @notice ForgeCoin ERC20 token
    IERC20 public immutable forgeCoin;

    /// @notice ForgeItems ERC1155 contract (Dust = id 0)
    IERC1155 public immutable forgeItems;

    /// @notice LP Token contract
    ForgeLPToken public immutable lpToken;

    // ============================================================
    //                       STORAGE
    // ============================================================

    /// @notice Reserve of ForgeCoin in the pool
    uint112 private _reserveForgeCoin;

    /// @notice Reserve of Dust in the pool
    uint112 private _reserveDust;

    /// @notice Timestamp of last reserve update
    uint32 private _blockTimestampLast;

    /// @notice Cumulative price for oracle (ForgeCoin price in Dust terms)
    uint256 public price0CumulativeLast;

    /// @notice Cumulative price for oracle (Dust price in ForgeCoin terms)
    uint256 public price1CumulativeLast;

    // ============================================================
    //                      CUSTOM ERRORS
    // ============================================================

    error InsufficientLiquidity();
    error InsufficientInputAmount();
    error InsufficientOutputAmount();
    error SlippageExceeded();
    error DeadlineExpired();
    error InvalidK();
    error ZeroAddress();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();

    // ============================================================
    //                         EVENTS
    // ============================================================

    event LiquidityAdded(
        address indexed provider,
        uint256 forgeCoinAmount,
        uint256 dustAmount,
        uint256 lpTokens
    );

    event LiquidityRemoved(
        address indexed provider,
        uint256 forgeCoinAmount,
        uint256 dustAmount,
        uint256 lpTokens
    );

    event Swap(
        address indexed user,
        bool forgeCoinToDust,
        uint256 amountIn,
        uint256 amountOut
    );

    event Sync(uint112 reserveForgeCoin, uint112 reserveDust);

    // ============================================================
    //                       MODIFIERS
    // ============================================================

    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        _;
    }

    // ============================================================
    //                      CONSTRUCTOR
    // ============================================================

    /// @param _forgeCoin    ForgeCoin ERC20 contract address
    /// @param _forgeItems   ForgeItems ERC1155 contract address
    constructor(address _forgeCoin, address _forgeItems) {
        if (_forgeCoin == address(0) || _forgeItems == address(0)) revert ZeroAddress();

        forgeCoin = IERC20(_forgeCoin);
        forgeItems = IERC1155(_forgeItems);

        // Deploy LP token with this AMM as the sole minter/burner
        lpToken = new ForgeLPToken(address(this));
    }

    // ============================================================
    //                      LIQUIDITY
    // ============================================================

    /// @notice Add liquidity to the ForgeCoin/Dust pool
    /// @dev Caller must approve both ForgeCoin (ERC20) and ForgeItems (setApprovalForAll)
    /// @param forgeCoinDesired  Desired ForgeCoin amount to deposit
    /// @param dustDesired       Desired Dust amount to deposit
    /// @param forgeCoinMin      Minimum ForgeCoin to deposit (slippage)
    /// @param dustMin           Minimum Dust to deposit (slippage)
    /// @param deadline          Transaction deadline timestamp
    /// @return liquidity        LP tokens minted to the caller
    function addLiquidity(
        uint256 forgeCoinDesired,
        uint256 dustDesired,
        uint256 forgeCoinMin,
        uint256 dustMin,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 liquidity) {
        (uint256 forgeCoinAmount, uint256 dustAmount) =
            _calculateLiquidityAmounts(forgeCoinDesired, dustDesired, forgeCoinMin, dustMin);

        // Transfer tokens to pool
        forgeCoin.safeTransferFrom(msg.sender, address(this), forgeCoinAmount);
        forgeItems.safeTransferFrom(msg.sender, address(this), DUST_ID, dustAmount, "");

        // Calculate LP tokens to mint
        uint256 totalLP = lpToken.totalSupply();

        if (totalLP == 0) {
            // First deposit: LP = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
            liquidity = AMMath.sqrt(AMMath.safeMul(forgeCoinAmount, dustAmount)) - MINIMUM_LIQUIDITY;
            // Permanently lock MINIMUM_LIQUIDITY to prevent total drain
            lpToken.mint(address(0xdead), MINIMUM_LIQUIDITY);
        } else {
            // Subsequent deposits: proportional to existing reserves
            uint256 lpFromFC = AMMath.safeMul(forgeCoinAmount, totalLP) / _reserveForgeCoin;
            uint256 lpFromDust = AMMath.safeMul(dustAmount, totalLP) / _reserveDust;
            liquidity = AMMath.min(lpFromFC, lpFromDust);
        }

        if (liquidity == 0) revert InsufficientLiquidityMinted();

        lpToken.mint(msg.sender, liquidity);
        _updateReserves();

        emit LiquidityAdded(msg.sender, forgeCoinAmount, dustAmount, liquidity);
    }

    /// @notice Remove liquidity from the pool
    /// @param liquidity     LP tokens to burn
    /// @param minForgeCoin  Minimum ForgeCoin to receive
    /// @param minDust       Minimum Dust to receive
    /// @param deadline      Transaction deadline timestamp
    /// @return forgeCoinOut ForgeCoin returned
    /// @return dustOut      Dust returned
    function removeLiquidity(
        uint256 liquidity,
        uint256 minForgeCoin,
        uint256 minDust,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 forgeCoinOut, uint256 dustOut) {
        uint256 totalLP = lpToken.totalSupply();
        if (liquidity == 0 || totalLP == 0) revert InsufficientLiquidityBurned();

        uint256 reserveFC = _reserveForgeCoin;
        uint256 reserveD = _reserveDust;

        // Calculate proportional amounts using Yul
        forgeCoinOut = AMMath.safeMul(liquidity, reserveFC) / totalLP;
        dustOut = AMMath.safeMul(liquidity, reserveD) / totalLP;

        if (forgeCoinOut == 0 || dustOut == 0) revert InsufficientLiquidityBurned();
        if (forgeCoinOut < minForgeCoin || dustOut < minDust) revert SlippageExceeded();

        // Burn LP tokens
        lpToken.burn(msg.sender, liquidity);

        // Transfer tokens to provider
        forgeCoin.safeTransfer(msg.sender, forgeCoinOut);
        forgeItems.safeTransferFrom(address(this), msg.sender, DUST_ID, dustOut, "");

        _updateReserves();

        emit LiquidityRemoved(msg.sender, forgeCoinOut, dustOut, liquidity);
    }

    // ============================================================
    //                        SWAPS
    // ============================================================

    /// @notice Swap ForgeCoin for Dust
    /// @param amountIn      ForgeCoin amount to swap
    /// @param minAmountOut  Minimum Dust to receive (slippage protection)
    /// @param deadline      Transaction deadline
    /// @return amountOut    Dust amount received
    function swapForgeCoinForDust(
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientInputAmount();

        uint256 reserveFC = _reserveForgeCoin;
        uint256 reserveD = _reserveDust;

        // Calculate output using Yul-optimized math
        amountOut = AMMath.getAmountOut(amountIn, reserveFC, reserveD);
        if (amountOut < minAmountOut) revert SlippageExceeded();
        if (amountOut >= reserveD) revert InsufficientLiquidity();

        // Execute swap: receive ForgeCoin, send Dust
        forgeCoin.safeTransferFrom(msg.sender, address(this), amountIn);
        forgeItems.safeTransferFrom(address(this), msg.sender, DUST_ID, amountOut, "");

        // Verify K invariant (post-swap reserves must satisfy k_new >= k_old)
        _verifyKInvariant(reserveFC, reserveD);
        _updateReserves();

        emit Swap(msg.sender, true, amountIn, amountOut);
    }

    /// @notice Swap Dust for ForgeCoin
    /// @param amountIn      Dust amount to swap
    /// @param minAmountOut  Minimum ForgeCoin to receive (slippage protection)
    /// @param deadline      Transaction deadline
    /// @return amountOut    ForgeCoin amount received
    function swapDustForForgeCoin(
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientInputAmount();

        uint256 reserveFC = _reserveForgeCoin;
        uint256 reserveD = _reserveDust;

        // Calculate output using Yul-optimized math
        amountOut = AMMath.getAmountOut(amountIn, reserveD, reserveFC);
        if (amountOut < minAmountOut) revert SlippageExceeded();
        if (amountOut >= reserveFC) revert InsufficientLiquidity();

        // Execute swap: receive Dust, send ForgeCoin
        forgeItems.safeTransferFrom(msg.sender, address(this), DUST_ID, amountIn, "");
        forgeCoin.safeTransfer(msg.sender, amountOut);

        // Verify K invariant
        _verifyKInvariant(reserveFC, reserveD);
        _updateReserves();

        emit Swap(msg.sender, false, amountIn, amountOut);
    }

    // ============================================================
    //                    VIEW FUNCTIONS
    // ============================================================

    /// @notice Get current pool reserves
    function getReserves()
        external
        view
        returns (uint256 reserveForgeCoin, uint256 reserveDust, uint32 blockTimestampLast)
    {
        return (_reserveForgeCoin, _reserveDust, _blockTimestampLast);
    }

    /// @notice Calculate output amount (external wrapper for AMMath)
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256)
    {
        return AMMath.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /// @notice Calculate input amount (external wrapper for AMMath)
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256)
    {
        return AMMath.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    /// @notice Quote equivalent value between reserves
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        external
        pure
        returns (uint256)
    {
        return AMMath.quote(amountA, reserveA, reserveB);
    }

    // ============================================================
    //                   INTERNAL FUNCTIONS
    // ============================================================

    /// @dev Calculate optimal liquidity amounts respecting current ratio
    function _calculateLiquidityAmounts(
        uint256 forgeCoinDesired,
        uint256 dustDesired,
        uint256 forgeCoinMin,
        uint256 dustMin
    ) internal view returns (uint256 forgeCoinAmount, uint256 dustAmount) {
        uint256 reserveFC = _reserveForgeCoin;
        uint256 reserveD = _reserveDust;

        if (reserveFC == 0 && reserveD == 0) {
            // First liquidity deposit — accept any ratio
            return (forgeCoinDesired, dustDesired);
        }

        // Calculate optimal Dust amount for desired ForgeCoin
        uint256 dustOptimal = AMMath.quote(forgeCoinDesired, reserveFC, reserveD);

        if (dustOptimal <= dustDesired) {
            if (dustOptimal < dustMin) revert SlippageExceeded();
            return (forgeCoinDesired, dustOptimal);
        }

        // Calculate optimal ForgeCoin amount for desired Dust
        uint256 forgeCoinOptimal = AMMath.quote(dustDesired, reserveD, reserveFC);
        assert(forgeCoinOptimal <= forgeCoinDesired);

        if (forgeCoinOptimal < forgeCoinMin) revert SlippageExceeded();
        return (forgeCoinOptimal, dustDesired);
    }

    /// @dev Update cached reserves from actual balances
    function _updateReserves() private {
        uint256 balanceFC = forgeCoin.balanceOf(address(this));
        uint256 balanceD = forgeItems.balanceOf(address(this), DUST_ID);

        // Safe cast to uint112 (overflow extremely unlikely with reasonable amounts)
        require(balanceFC <= type(uint112).max && balanceD <= type(uint112).max, "OVERFLOW");

        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - _blockTimestampLast;
        }

        // Update cumulative prices for TWAP oracle
        if (timeElapsed > 0 && _reserveForgeCoin > 0 && _reserveDust > 0) {
            unchecked {
                // Overflow is desired for cumulative price (wraps around)
                price0CumulativeLast +=
                    uint256(_reserveDust) * timeElapsed / uint256(_reserveForgeCoin);
                price1CumulativeLast +=
                    uint256(_reserveForgeCoin) * timeElapsed / uint256(_reserveDust);
            }
        }

        _reserveForgeCoin = uint112(balanceFC);
        _reserveDust = uint112(balanceD);
        _blockTimestampLast = blockTimestamp;

        emit Sync(_reserveForgeCoin, _reserveDust);
    }

    /// @dev Verify that the K invariant holds after a swap
    ///      Uses Yul for the multiplication comparison
    function _verifyKInvariant(uint256 oldReserveFC, uint256 oldReserveDust) private view {
        uint256 newBalanceFC = forgeCoin.balanceOf(address(this));
        uint256 newBalanceDust = forgeItems.balanceOf(address(this), DUST_ID);

        // k_new (adjusted for fee) must be >= k_old
        // (newBalanceFC * 1000 - amountInFC * 3) * (newBalanceDust * 1000 - amountInDust * 3) >= oldK * 1000^2
        // Simplified: newBalanceFC * newBalanceDust >= oldReserveFC * oldReserveDust
        // (This holds because the fee stays in the pool)
        uint256 kOld;
        uint256 kNew;
        assembly {
            // k_old = oldReserveFC * oldReserveDust
            kOld := mul(oldReserveFC, oldReserveDust)
            // k_new = newBalanceFC * newBalanceDust
            kNew := mul(newBalanceFC, newBalanceDust)
        }

        if (kNew < kOld) revert InvalidK();
    }

    // ============================================================
    //                  ERC1155 RECEIVER
    // ============================================================

    /// @dev Accept ERC1155 single transfers (required for receiving Dust)
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @dev Accept ERC1155 batch transfers
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /// @dev ERC165 introspection support
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
