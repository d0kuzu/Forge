// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Guild — Mini-contract deployed via CREATE2 by GuildFactory
/// @notice Represents an in-game guild with a leader, members, and shared treasury.
///         Each guild is a separate contract with its own address and state.
/// @dev Deployed deterministically by GuildFactory using CREATE2.
///      Leader can manage members and guild treasury.
contract Guild {
    using SafeERC20 for IERC20;

    // ============================================================
    //                       STORAGE
    // ============================================================

    /// @notice The factory that deployed this guild
    address public immutable factory;

    /// @notice Human-readable guild name
    string public name;

    /// @notice Guild leader address
    address public leader;

    /// @notice Timestamp when guild was created
    uint256 public creationTime;

    /// @notice Set of guild members (leader is always a member)
    mapping(address => bool) public isMember;

    /// @notice List of all member addresses
    address[] public members;

    /// @notice Total number of members
    uint256 public memberCount;

    /// @notice Maximum members allowed
    uint256 public constant MAX_MEMBERS = 50;

    // ============================================================
    //                      CUSTOM ERRORS
    // ============================================================

    error OnlyLeader();
    error OnlyFactory();
    error AlreadyMember(address account);
    error NotMember(address account);
    error GuildFull();
    error CannotRemoveLeader();
    error ZeroAddress();

    // ============================================================
    //                         EVENTS
    // ============================================================

    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);
    event LeaderTransferred(address indexed oldLeader, address indexed newLeader);
    event TreasuryWithdrawn(address indexed token, address indexed to, uint256 amount);

    // ============================================================
    //                       MODIFIERS
    // ============================================================

    modifier onlyLeader() {
        if (msg.sender != leader) revert OnlyLeader();
        _;
    }

    // ============================================================
    //                      CONSTRUCTOR
    // ============================================================

    /// @param _name    Guild name
    /// @param _leader  Guild leader address
    constructor(string memory _name, address _leader) {
        if (_leader == address(0)) revert ZeroAddress();

        factory = msg.sender;
        name = _name;
        leader = _leader;
        creationTime = block.timestamp;

        // Leader is automatically a member
        isMember[_leader] = true;
        members.push(_leader);
        memberCount = 1;
    }

    // ============================================================
    //                    MEMBER MANAGEMENT
    // ============================================================

    /// @notice Add a member to the guild
    /// @dev Only callable by the leader
    function addMember(address account) external onlyLeader {
        if (account == address(0)) revert ZeroAddress();
        if (isMember[account]) revert AlreadyMember(account);
        if (memberCount >= MAX_MEMBERS) revert GuildFull();

        isMember[account] = true;
        members.push(account);
        memberCount++;

        emit MemberAdded(account);
    }

    /// @notice Remove a member from the guild
    /// @dev Only callable by the leader. Cannot remove the leader.
    function removeMember(address account) external onlyLeader {
        if (account == leader) revert CannotRemoveLeader();
        if (!isMember[account]) revert NotMember(account);

        isMember[account] = false;
        memberCount--;

        // Remove from members array (swap and pop)
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == account) {
                members[i] = members[members.length - 1];
                members.pop();
                break;
            }
        }

        emit MemberRemoved(account);
    }

    /// @notice Leave the guild voluntarily
    function leaveGuild() external {
        if (msg.sender == leader) revert CannotRemoveLeader();
        if (!isMember[msg.sender]) revert NotMember(msg.sender);

        isMember[msg.sender] = false;
        memberCount--;

        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == msg.sender) {
                members[i] = members[members.length - 1];
                members.pop();
                break;
            }
        }

        emit MemberRemoved(msg.sender);
    }

    /// @notice Transfer leadership to another member
    function transferLeadership(address newLeader) external onlyLeader {
        if (!isMember[newLeader]) revert NotMember(newLeader);

        address oldLeader = leader;
        leader = newLeader;

        emit LeaderTransferred(oldLeader, newLeader);
    }

    // ============================================================
    //                      TREASURY
    // ============================================================

    /// @notice Withdraw ERC20 tokens from guild treasury
    /// @dev Only callable by the leader
    function withdrawTreasury(
        address token,
        address to,
        uint256 amount
    ) external onlyLeader {
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit TreasuryWithdrawn(token, to, amount);
    }

    // ============================================================
    //                      VIEW FUNCTIONS
    // ============================================================

    /// @notice Get all current members
    function getMembers() external view returns (address[] memory) {
        return members;
    }

    /// @notice Receive native currency (guild treasury)
    receive() external payable {}
}
