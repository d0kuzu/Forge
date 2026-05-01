// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DataTypes} from "../libraries/DataTypes.sol";

/// @title IGachaLootbox — Interface for Gacha / Lootbox system
/// @notice Uses Chainlink VRF v2.5, deployed behind UUPS proxy
interface IGachaLootbox {
    error LootboxNotActive(uint256 lootboxType);
    error InsufficientPayment();
    error RequestNotFound(uint256 requestId);
    error RequestAlreadyFulfilled(uint256 requestId);
    error ArrayLengthMismatch();
    error InvalidWeights();

    event LootboxConfigured(uint256 indexed lootboxType, uint256 price, uint256 itemCount);
    event LootboxOpened(uint256 indexed requestId, address indexed requester, uint256 indexed lootboxType);
    event LootboxFulfilled(uint256 indexed requestId, address indexed requester, uint256 itemId, uint256 amount);
    event DropRatesUpdated(uint256 indexed lootboxType);
    event PriceUpdated(uint256 indexed lootboxType, uint256 oldPrice, uint256 newPrice);
    event RevenueWithdrawn(address indexed to, uint256 amount);

    function configureLootbox(uint256 lootboxType, uint256 price, uint256[] calldata itemIds, uint256[] calldata weights) external;
    function updateDropRates(uint256 lootboxType, uint256[] calldata newWeights) external;
    function setPrice(uint256 lootboxType, uint256 newPrice) external;
    function openLootbox(uint256 lootboxType) external returns (uint256 requestId);
    function withdrawRevenue(address to, uint256 amount) external;
    function getLootboxConfig(uint256 lootboxType) external view returns (DataTypes.LootboxConfig memory config);
    function getRequest(uint256 requestId) external view returns (DataTypes.GachaRequest memory request);
    function totalRevenue() external view returns (uint256);
}
