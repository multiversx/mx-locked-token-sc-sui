module locked_token::locked_token_tests;

use sui::clock::{Self, Clock};
use sui::object::UID;
use sui::tx_context::TxContext;

/// Error codes
const E_NOT_OWNER: u64 = 1;
const E_INSUFFICIENT_BALANCE: u64 = 2;
const E_REQUEST_NOT_STAMPED: u64 = 3;
const E_REQUEST_ALREADY_STAMPED: u64 = 4;

/// Closed-loop fungible token stored in owner-scoped vaults.
/// No global coin store; transfers must go through policy-governed spend flow.
public struct Vault has key {
    id: UID,
    owner: address,
    amount: u64,
}

/// Governance policy for lock/unlock using either timelock (Clock) or admin toggle.
public struct Policy has key {
    id: UID,
    /// Unix timestamp in milliseconds after which transfers are allowed if admin has not locked.
    unlock_time_ms: u64,
    /// When true, policy allows stamping irrespective of time; when false, time must pass.
    admin_unlocked: bool,
    /// Address that can toggle admin lock and update unlock time.
    admin: address,
}

/// Spend-flow transfer request which must be stamped by policy before confirmation.
public struct TransferRequest has drop, store {
    from: address,
    to: address,
    amount: u64,
    stamped: bool,
}

/// Spend-flow request (burn on confirm) which must be stamped by policy.
public struct SpendRequest has drop, store {
    from: address,
    amount: u64,
    stamped: bool,
}

/// Create a new empty vault for `owner`.
public fun create_vault(owner: address, ctx: &mut TxContext): Vault {
    Vault { id: sui::object::new(ctx), owner, amount: 0 }
}

/// Initialize a policy with an initial timelock and admin address.
public fun create_policy(admin: address, unlock_time_ms: u64, ctx: &mut TxContext): Policy {
    Policy { id: sui::object::new(ctx), unlock_time_ms, admin_unlocked: false, admin }
}

/// Mint tokens into a vault. Only admin may mint via policy.
public fun mint(policy: &Policy, to_vault: &mut Vault, amount: u64, ctx: &mut TxContext) {
    assert!(sui::tx_context::sender(ctx) == policy.admin, E_NOT_OWNER);
    to_vault.amount = to_vault.amount + amount;
}

/// Burn tokens from a vault. Only admin may burn via policy.
public fun burn(policy: &Policy, from_vault: &mut Vault, amount: u64, ctx: &mut TxContext) {
    assert!(sui::tx_context::sender(ctx) == policy.admin, E_NOT_OWNER);
    assert!(from_vault.amount >= amount, E_INSUFFICIENT_BALANCE);
    from_vault.amount = from_vault.amount - amount;
}

/// Begin a spend-flow transfer by creating a request. Does not move balance yet.
/// The policy must later stamp this request; then `confirm_transfer` will execute it.
public fun request_transfer(from_vault: &Vault, to: address, amount: u64): TransferRequest {
    assert!(from_vault.amount >= amount, E_INSUFFICIENT_BALANCE);
    TransferRequest { from: from_vault.owner, to, amount, stamped: false }
}

/// Begin a spend-flow (burn) by creating a request. Policy must stamp before confirmation.
public fun request_spend(from_vault: &Vault, amount: u64): SpendRequest {
    assert!(from_vault.amount >= amount, E_INSUFFICIENT_BALANCE);
    SpendRequest { from: from_vault.owner, amount, stamped: false }
}

/// Policy stamping: approve a request if unlocked by time or admin toggle.
/// If `admin_unlocked` is true, stamp immediately. Otherwise require `Clock` >= `unlock_time_ms`.
public fun stamp_if_unlocked(policy: &Policy, req: &mut TransferRequest, clock_obj: &Clock) {
    assert!(!req.stamped, E_REQUEST_ALREADY_STAMPED);
    if (policy.admin_unlocked || clock::timestamp_ms(clock_obj) >= policy.unlock_time_ms) {
        req.stamped = true;
    }
}

/// Policy stamping for spend requests.
public fun stamp_spend_if_unlocked(policy: &Policy, req: &mut SpendRequest, clock_obj: &Clock) {
    assert!(!req.stamped, E_REQUEST_ALREADY_STAMPED);
    if (policy.admin_unlocked || clock::timestamp_ms(clock_obj) >= policy.unlock_time_ms) {
        req.stamped = true;
    }
}

/// Admin-only stamping helper that does not require a Clock reference.
public fun stamp_if_admin_unlocked(policy: &Policy, req: &mut TransferRequest) {
    assert!(!req.stamped, E_REQUEST_ALREADY_STAMPED);
    if (policy.admin_unlocked) { req.stamped = true; }
}

/// Admin-only stamping helper for spend requests without a Clock reference.
public fun stamp_spend_if_admin_unlocked(policy: &Policy, req: &mut SpendRequest) {
    assert!(!req.stamped, E_REQUEST_ALREADY_STAMPED);
    if (policy.admin_unlocked) { req.stamped = true; }
}

/// Confirm a stamped transfer: move balance from `from_vault` to `to_vault`.
/// The caller must be the owner of `from_vault`.
public fun confirm_transfer(
    from_vault: &mut Vault,
    to_vault: &mut Vault,
    req: TransferRequest,
    ctx: &mut TxContext,
) {
    assert!(req.stamped, E_REQUEST_NOT_STAMPED);
    assert!(req.from == from_vault.owner, E_NOT_OWNER);
    assert!(sui::tx_context::sender(ctx) == from_vault.owner, E_NOT_OWNER);
    assert!(from_vault.amount >= req.amount, E_INSUFFICIENT_BALANCE);
    from_vault.amount = from_vault.amount - req.amount;
    to_vault.amount = to_vault.amount + req.amount;
}

/// Confirm a stamped spend: burn from the caller's vault.
public fun confirm_spend(from_vault: &mut Vault, req: SpendRequest, ctx: &mut TxContext) {
    assert!(req.stamped, E_REQUEST_NOT_STAMPED);
    assert!(req.from == from_vault.owner, E_NOT_OWNER);
    assert!(sui::tx_context::sender(ctx) == from_vault.owner, E_NOT_OWNER);
    assert!(from_vault.amount >= req.amount, E_INSUFFICIENT_BALANCE);
    from_vault.amount = from_vault.amount - req.amount; // burn
}

/// Admin toggles immediate unlock on/off.
public fun set_admin_unlock(policy: &mut Policy, value: bool, ctx: &mut TxContext) {
    assert!(sui::tx_context::sender(ctx) == policy.admin, E_NOT_OWNER);
    policy.admin_unlocked = value;
}

/// Admin updates the time-lock unlock timestamp.
public fun set_unlock_time_ms(policy: &mut Policy, unlock_time_ms: u64, ctx: &mut TxContext) {
    assert!(sui::tx_context::sender(ctx) == policy.admin, E_NOT_OWNER);
    policy.unlock_time_ms = unlock_time_ms;
}

/// View helpers
public fun get_amount(v: &Vault): u64 { v.amount }

public fun get_owner(v: &Vault): address { v.owner }

public fun is_admin_unlocked(p: &Policy): bool { p.admin_unlocked }

public fun get_unlock_time_ms(p: &Policy): u64 { p.unlock_time_ms }

public fun get_admin(p: &Policy): address { p.admin }

public fun is_transfer_stamped(r: &TransferRequest): bool { r.stamped }

public fun is_spend_stamped(r: &SpendRequest): bool { r.stamped }
