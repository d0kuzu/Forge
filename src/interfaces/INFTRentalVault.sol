// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DataTypes} from "../libraries/DataTypes.sol";

/// @title INFTRentalVault — Interface for ERC1155 item rental system
/// @notice Owners deposit ForgeItems, renters pay ForgeCoin for timed access
interface INFTRentalVault {
    error ListingNotActive(uint256 listingId);
    error RentalNotActive(uint256 rentalId);
    error InvalidDuration(uint256 duration, uint256 min, uint256 max);
    error NotListingOwner(uint256 listingId);
    error NotRenter(uint256 rentalId);
    error RentalNotExpired(uint256 rentalId);
    error InsufficientPayment();
    error ZeroAmount();

    event ItemListed(uint256 indexed listingId, address indexed owner, uint256 indexed itemId, uint256 amount, uint256 pricePerDay);
    event ItemDelisted(uint256 indexed listingId);
    event ListingUpdated(uint256 indexed listingId, uint256 newPricePerDay);
    event ItemRented(uint256 indexed rentalId, uint256 indexed listingId, address indexed renter, uint256 duration, uint256 totalPaid);
    event ItemReturned(uint256 indexed rentalId);
    event RentClaimed(uint256 indexed rentalId, address indexed owner, uint256 amount);
    event RentalLiquidated(uint256 indexed rentalId);

    /// @notice List an ERC1155 item for rent (transfers item to vault)
    function listItem(uint256 itemId, uint256 amount, uint256 pricePerDay, uint256 minDuration, uint256 maxDuration)
        external returns (uint256 listingId);

    /// @notice Remove a listing and reclaim the item
    function delistItem(uint256 listingId) external;

    /// @notice Update listing parameters
    function updateListing(uint256 listingId, uint256 newPricePerDay, uint256 newMinDuration, uint256 newMaxDuration) external;

    /// @notice Rent an item by paying ForgeCoin
    /// @param listingId  The listing to rent from
    /// @param duration   Rental duration in seconds
    function rentItem(uint256 listingId, uint256 duration) external returns (uint256 rentalId);

    /// @notice Return rented item early
    function returnItem(uint256 rentalId) external;

    /// @notice Owner claims accumulated rent payment
    function claimRent(uint256 rentalId) external;

    /// @notice Liquidate expired rental (anyone can call)
    function liquidateExpiredRental(uint256 rentalId) external;

    /// @notice Calculate total cost for a rental
    function calculateRentalCost(uint256 listingId, uint256 duration) external view returns (uint256);

    /// @notice Get listing details
    function getListing(uint256 listingId) external view returns (DataTypes.RentalListing memory);

    /// @notice Get rental agreement details
    function getRental(uint256 rentalId) external view returns (DataTypes.RentalAgreement memory);

    /// @notice Check if a rental is currently active
    function isRented(uint256 rentalId) external view returns (bool);
}
