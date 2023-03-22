// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

/// Thrown when Cooldown is initialized with a 0 cooldown.
error ZeroInitCooldown();

/// Thrown if the Cooldown is being reinitialized with a new cooldown duration.
error Reinitialize();

/// Thrown if the Cooldown is NOT initialized during an active cooldown check.
error Uninitialized();

/// Thrown if the Cooldown is triggered.
/// @param caller The root caller that triggered the calldown.
/// @param sender The `msg.sender` the cooldown is active for, MAY NOT be
/// `caller` in the case of reentrancy.
/// @param cooldownExpiresAt Timestamp the cooldown will expire at.
error ActiveCooldown(address caller, address sender, uint256 cooldownExpiresAt);

/// @title Cooldown
/// @notice `Cooldown` is a base contract that rate limits functions on the
/// implementing contract per `msg.sender`.
///
/// Each time a function with the `onlyAfterCooldown` modifier is called the
/// `msg.sender` must wait N seconds before calling any modified function.
///
/// This does nothing to prevent sybils who can generate an arbitrary number of
/// `msg.sender` values in parallel to spam a contract.
///
/// `Cooldown` is intended to prevent rapid state cycling to grief a contract,
/// such as rapidly locking and unlocking a large amount of capital in the
/// `SeedERC20` contract.
///
/// Requiring a lock/deposit of significant economic stake that sybils will not
/// have access to AND applying a cooldown IS a sybil mitigation. The economic
/// stake alone is NOT sufficient if gas is cheap as sybils can cycle the same
/// stake between each other. The cooldown alone is NOT sufficient as many
/// sybils can be created, each as a new `msg.sender`.
///
/// @dev Base for anything that enforces a cooldown delay on functions.
/// `Cooldown` requires a minimum time in seconds to elapse between actions
/// that cooldown. The modifier `onlyAfterCooldown` both enforces and triggers
/// the cooldown. There is a single cooldown across all functions per-contract
/// so any function call that requires a cooldown will also trigger it for all
/// other functions.
///
/// Cooldown is NOT an effective sybil resistance alone, as the cooldown is
/// per-address only. It is always possible for many accounts to be created to
/// spam a contract with dust in parallel.
///
/// Cooldown is useful to stop a single account rapidly cycling contract state in
/// a way that can be disruptive to peers. Cooldown works best when coupled with
/// economic stake associated with each state change so that peers must lock
/// capital during the cooldown. `Cooldown` tracks the first `msg.sender` it sees
/// for a call stack so cooldowns are enforced across reentrant code. Any
/// function that enforces a cooldown also has reentrancy protection.
contract Cooldown {
    /// Cooldown contract has initialized.
    /// @param sender `msg.sender` initializing the Cooldown contract.
    /// @param cooldownDuration Duration in seconds between when a cooldown is
    /// triggered by some caller and it being able to be called again.
    event CooldownInitialize(address sender, uint256 cooldownDuration);

    /// Cooldown has been triggered.
    /// @param sender `msg.sender` that triggered the cooldown.
    /// @param cooldownExpiry Timestamp in seconds that the sender can call
    /// functions on cooldown again.
    event CooldownTriggered(address sender, uint256 cooldownExpiry);

    /// Time in seconds to restrict access to modified functions.
    uint32 internal cooldownDuration;

    /// Active caller to Cooldown. Is zeroed out between calls to save gas.
    address internal cooldownCaller;

    /// Every caller has its own cooldown, the minimum time that the caller call
    /// another function sharing the same cooldown state.
    mapping(address => uint256) internal cooldownExpiries;

    /// Initialize the cooldown duration.
    /// The cooldown duration is global to the contract.
    /// Cooldown duration must be greater than 0.
    /// Cooldown duration can only be set once.
    /// @param cooldownDuration_ The global cooldown duration.
    function initializeCooldown(uint32 cooldownDuration_) internal {
        if (cooldownDuration_ < 1) {
            revert ZeroInitCooldown();
        }
        if (cooldownDuration > 0) {
            revert Reinitialize();
        }
        cooldownDuration = cooldownDuration_;
        emit CooldownInitialize(msg.sender, cooldownDuration_);
    }

    /// Modifies a function to enforce the cooldown for `msg.sender`.
    /// Saves the original caller so that cooldowns are enforced across
    /// reentrant code.
    modifier onlyAfterCooldown() {
        uint256 cooldownDuration_ = cooldownDuration;
        if (cooldownDuration_ < 1) {
            revert Uninitialized();
        }

        // Guard against reentrancy being used to bypass cooldowns, without
        // resorting to tx.origin.
        address caller_ = cooldownCaller;
        if (caller_ == address(0)) {
            caller_ = msg.sender;
            cooldownCaller = msg.sender;
        }

        if (cooldownExpiries[caller_] > block.timestamp) {
            revert ActiveCooldown(caller_, msg.sender, cooldownExpiries[caller_]);
        }

        // Every action that requires a cooldown also triggers a cooldown.
        uint256 cooldownExpiry_ = block.timestamp + cooldownDuration_;
        cooldownExpiries[caller_] = cooldownExpiry_;
        emit CooldownTriggered(caller_, cooldownExpiry_);

        // Do stuff.
        _;

        // Refund as much gas as we can.
        delete cooldownCaller;
    }
}
