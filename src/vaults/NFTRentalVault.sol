// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {DataTypes} from "../libraries/DataTypes.sol";
import {IForgeVault} from "../interfaces/IForgeVault.sol";

/// @title NFTRentalVault — ERC1155 Item Rental Marketplace
/// @notice Owners deposit ForgeItems and set daily ForgeCoin rental rates.
///         Renters pay upfront for a fixed duration. Items remain in the vault
///         during rental. Expired rentals can be liquidated by anyone.
/// @dev Key mechanics:
///      - Listing: owner transfers ERC1155 item to vault, sets price/duration
///      - Renting: renter pays ForgeCoin, gets "virtual access" for duration
///      - Return: item goes back to owner after expiry or early return
///      - Liquidation: anyone can trigger return of expired rentals
contract NFTRentalVault is ReentrancyGuard, IERC1155Receiver, Ownable {
    using SafeERC20 for IERC20;

    // ============================================================
    //                       IMMUTABLES
    // ============================================================

    /// @notice ForgeCoin token for rental payments
    IERC20 public immutable forgeCoin;

    /// @notice ForgeItems ERC1155 contract
    IERC1155 public immutable forgeItems;

    // ============================================================
    //                       STORAGE
    // ============================================================

    /// @notice Counter for listing IDs
    uint256 private _nextListingId = 1;

    /// @notice Counter for rental IDs
    uint256 private _nextRentalId = 1;

    /// @notice Listing ID => listing data
    mapping(uint256 => DataTypes.RentalListing) private _listings;

    /// @notice Rental ID => rental agreement data
    mapping(uint256 => DataTypes.RentalAgreement) private _rentals;

    /// @notice listing ID => current active rental ID (0 if none)
    mapping(uint256 => uint256) public activeRentalForListing;

    /// @notice Owner => accumulated unclaimed rent
    mapping(address => uint256) public unclaimedRent;

    /// @notice Platform fee in basis points (e.g., 250 = 2.5%)
    uint256 public constant PLATFORM_FEE_BPS = 250;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Vault for sweeping revenue
    IForgeVault public forgeVault;

    /// @notice Accumulated platform fees ready to sweep
    uint256 public accumulatedPlatformFees;

    // ============================================================
    //                      CUSTOM ERRORS
    // ============================================================

    error ListingNotActive(uint256 listingId);
    error RentalNotActive(uint256 rentalId);
    error InvalidDuration(uint256 duration, uint256 min, uint256 max);
    error NotListingOwner(uint256 listingId);
    error NotRenter(uint256 rentalId);
    error RentalNotExpired(uint256 rentalId);
    error ItemCurrentlyRented(uint256 listingId);
    error InsufficientPayment();
    error ZeroAmount();
    error ZeroAddress();
    error NothingToClaim();

    // ============================================================
    //                         EVENTS
    // ============================================================

    event ItemListed(uint256 indexed listingId, address indexed owner, uint256 indexed itemId, uint256 amount, uint256 pricePerDay);
    event ItemDelisted(uint256 indexed listingId);
    event ListingUpdated(uint256 indexed listingId, uint256 newPricePerDay);
    event ItemRented(uint256 indexed rentalId, uint256 indexed listingId, address indexed renter, uint256 duration, uint256 totalPaid);
    event ItemReturned(uint256 indexed rentalId);
    event RentClaimed(address indexed owner, uint256 amount);
    event RentalLiquidated(uint256 indexed rentalId);
    event PlatformFeesSwept(uint256 amount);

    // ============================================================
    //                      CONSTRUCTOR
    // ============================================================

    /// @param _forgeCoin    ForgeCoin ERC20 address
    /// @param _forgeItems   ForgeItems ERC1155 address
    /// @param initialOwner  Owner for configuring fees
    constructor(address _forgeCoin, address _forgeItems, address initialOwner) Ownable(initialOwner) {
        if (_forgeCoin == address(0) || _forgeItems == address(0)) revert ZeroAddress();
        forgeCoin = IERC20(_forgeCoin);
        forgeItems = IERC1155(_forgeItems);
    }

    // ============================================================
    //                    LISTING MANAGEMENT
    // ============================================================

    /// @notice List an ERC1155 item for rent
    /// @dev Transfers item from owner to vault. Owner must setApprovalForAll first.
    /// @param itemId       ForgeItems token ID
    /// @param amount       Number of tokens to list
    /// @param pricePerDay  Daily rental cost in ForgeCoin (18 decimals)
    /// @param minDuration  Minimum rental duration in seconds
    /// @param maxDuration  Maximum rental duration in seconds
    /// @return listingId   The ID of the created listing
    function listItem(
        uint256 itemId,
        uint256 amount,
        uint256 pricePerDay,
        uint256 minDuration,
        uint256 maxDuration
    ) external nonReentrant returns (uint256 listingId) {
        if (amount == 0) revert ZeroAmount();
        if (minDuration > maxDuration) revert InvalidDuration(minDuration, minDuration, maxDuration);

        listingId = _nextListingId++;

        _listings[listingId] = DataTypes.RentalListing({
            owner: msg.sender,
            itemId: itemId,
            amount: amount,
            pricePerDay: pricePerDay,
            minDuration: minDuration,
            maxDuration: maxDuration,
            active: true
        });

        // Transfer item to vault
        forgeItems.safeTransferFrom(msg.sender, address(this), itemId, amount, "");

        emit ItemListed(listingId, msg.sender, itemId, amount, pricePerDay);
    }

    /// @notice Remove a listing and reclaim the item
    /// @dev Only callable by listing owner. Item must not be currently rented.
    function delistItem(uint256 listingId) external nonReentrant {
        DataTypes.RentalListing storage listing = _listings[listingId];
        if (!listing.active) revert ListingNotActive(listingId);
        if (listing.owner != msg.sender) revert NotListingOwner(listingId);
        if (activeRentalForListing[listingId] != 0) revert ItemCurrentlyRented(listingId);

        listing.active = false;

        // Return item to owner
        forgeItems.safeTransferFrom(address(this), msg.sender, listing.itemId, listing.amount, "");

        emit ItemDelisted(listingId);
    }

    /// @notice Update listing parameters
    /// @dev Only callable by listing owner when not rented
    function updateListing(
        uint256 listingId,
        uint256 newPricePerDay,
        uint256 newMinDuration,
        uint256 newMaxDuration
    ) external {
        DataTypes.RentalListing storage listing = _listings[listingId];
        if (!listing.active) revert ListingNotActive(listingId);
        if (listing.owner != msg.sender) revert NotListingOwner(listingId);
        if (activeRentalForListing[listingId] != 0) revert ItemCurrentlyRented(listingId);

        listing.pricePerDay = newPricePerDay;
        listing.minDuration = newMinDuration;
        listing.maxDuration = newMaxDuration;

        emit ListingUpdated(listingId, newPricePerDay);
    }

    // ============================================================
    //                       RENTING
    // ============================================================

    /// @notice Rent an item by paying ForgeCoin upfront
    /// @param listingId  The listing to rent from
    /// @param duration   Rental duration in seconds
    /// @return rentalId  The ID of the created rental agreement
    function rentItem(
        uint256 listingId,
        uint256 duration
    ) external nonReentrant returns (uint256 rentalId) {
        DataTypes.RentalListing storage listing = _listings[listingId];
        if (!listing.active) revert ListingNotActive(listingId);
        if (activeRentalForListing[listingId] != 0) revert ItemCurrentlyRented(listingId);
        if (duration < listing.minDuration || duration > listing.maxDuration) {
            revert InvalidDuration(duration, listing.minDuration, listing.maxDuration);
        }

        // Calculate total cost: (pricePerDay * duration) / 1 day
        uint256 totalCost = (listing.pricePerDay * duration) / 1 days;
        if (totalCost == 0) revert ZeroAmount();

        // Transfer ForgeCoin from renter
        forgeCoin.safeTransferFrom(msg.sender, address(this), totalCost);

        // Calculate platform fee
        uint256 platformFee = (totalCost * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 ownerPayment = totalCost - platformFee;

        // Accrue rent to owner (claimable later)
        unclaimedRent[listing.owner] += ownerPayment;

        // Immediately route platform fee to ForgeVault if configured, else accumulate
        if (address(forgeVault) != address(0) && platformFee > 0) {
            forgeCoin.approve(address(forgeVault), platformFee);
            forgeVault.distributeRewards(platformFee);
        } else {
            accumulatedPlatformFees += platformFee;
        }

        rentalId = _nextRentalId++;

        _rentals[rentalId] = DataTypes.RentalAgreement({
            listingId: listingId,
            renter: msg.sender,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            totalPaid: totalCost,
            active: true
        });

        activeRentalForListing[listingId] = rentalId;

        emit ItemRented(rentalId, listingId, msg.sender, duration, totalCost);
    }

    /// @notice Return rented item early (rental ends immediately)
    /// @dev Only callable by the renter. No refund — full payment already made.
    function returnItem(uint256 rentalId) external nonReentrant {
        DataTypes.RentalAgreement storage rental = _rentals[rentalId];
        if (!rental.active) revert RentalNotActive(rentalId);
        if (rental.renter != msg.sender) revert NotRenter(rentalId);

        _endRental(rentalId);

        emit ItemReturned(rentalId);
    }

    /// @notice Liquidate an expired rental (anyone can call)
    /// @dev Ends the rental and makes the item available for re-listing
    function liquidateExpiredRental(uint256 rentalId) external nonReentrant {
        DataTypes.RentalAgreement storage rental = _rentals[rentalId];
        if (!rental.active) revert RentalNotActive(rentalId);
        if (block.timestamp < rental.endTime) revert RentalNotExpired(rentalId);

        _endRental(rentalId);

        emit RentalLiquidated(rentalId);
    }

    /// @notice Claim accumulated rental payments
    function claimRent() external nonReentrant {
        uint256 amount = unclaimedRent[msg.sender];
        if (amount == 0) revert NothingToClaim();

        unclaimedRent[msg.sender] = 0;
        forgeCoin.safeTransfer(msg.sender, amount);

        emit RentClaimed(msg.sender, amount);
    }

    // ============================================================
    //                      ADMIN FUNCTIONS
    // ============================================================

    /// @notice Set the ForgeVault address for sweeping revenue
    function setForgeVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert ZeroAddress();
        forgeVault = IForgeVault(_vault);
    }

    /// @notice Sweep all accumulated platform fees directly to the Vault
    /// @dev Requires forgeVault to be set and this contract to have DISTRIBUTOR_ROLE on it
    function sweepPlatformFees() external nonReentrant {
        if (address(forgeVault) == address(0)) revert ZeroAddress();
        uint256 amount = accumulatedPlatformFees;
        if (amount == 0) revert NothingToClaim();

        accumulatedPlatformFees = 0;
        forgeCoin.approve(address(forgeVault), amount);
        forgeVault.distributeRewards(amount);

        emit PlatformFeesSwept(amount);
    }

    // ============================================================
    //                      VIEW FUNCTIONS
    // ============================================================

    /// @notice Calculate total rental cost for a listing and duration
    function calculateRentalCost(uint256 listingId, uint256 duration)
        external
        view
        returns (uint256)
    {
        DataTypes.RentalListing storage listing = _listings[listingId];
        return (listing.pricePerDay * duration) / 1 days;
    }

    /// @notice Get listing details
    function getListing(uint256 listingId) external view returns (DataTypes.RentalListing memory) {
        return _listings[listingId];
    }

    /// @notice Get rental agreement details
    function getRental(uint256 rentalId) external view returns (DataTypes.RentalAgreement memory) {
        return _rentals[rentalId];
    }

    /// @notice Check if a rental is currently active and not expired
    function isRented(uint256 rentalId) external view returns (bool) {
        DataTypes.RentalAgreement storage rental = _rentals[rentalId];
        return rental.active && block.timestamp < rental.endTime;
    }

    // ============================================================
    //                   INTERNAL FUNCTIONS
    // ============================================================

    /// @dev End a rental and clear the active rental mapping
    function _endRental(uint256 rentalId) private {
        DataTypes.RentalAgreement storage rental = _rentals[rentalId];
        rental.active = false;
        activeRentalForListing[rental.listingId] = 0;
    }

    // ============================================================
    //                  ERC1155 RECEIVER
    // ============================================================

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
