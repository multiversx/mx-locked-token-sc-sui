module locked_token::treasury;

use locked_token::lk_roles::{Self, Roles};
use locked_token::version_control::{Self, assert_object_version_is_compatible_with_package};
use std::u64::{min, max};
use sui::coin::{Self, TreasuryCap};
use sui::dynamic_object_field as dof;
use sui::event;
use sui::table::{Self as table, Table};
use sui::token::{Self as t, Token, TokenPolicyCap};
use sui::vec_set::{Self, VecSet};

const ENotOwner: u64 = 1;
const ECapNotAuthorized: u64 = 2;
const EMigrationStarted: u64 = 3;
const EMigrationNotStarted: u64 = 4;
const EObjectMigrated: u64 = 5;
const ENotPendingVersion: u64 = 6;

/// Key for retrieving the `TreasuryCap` stored in a `Treasury<T>` dynamic object field
public struct TreasuryCapKey has copy, drop, store {}
/// Key for retrieving the `PolicyCap` stored in a `Treasury<T>` dynamic object field
public struct PolicyCapKey has copy, drop, store {}

/// Object representing the right for an admin or object to perform to_coin over the Token object
public struct ToCoinCap<phantom T> has key, store {
    id: UID,
}

/// Object representing the right for an admin or object to perform from_coin over the Token object
public struct FromCoinCap<phantom T> has key, store {
    id: UID,
}

/// Object representing the approval key for our ToCoinRule
public struct ToCoinRule has drop {}

/// Object representing the approval key for our FromCoinRule
public struct FromCoinRule has drop {}

/* ================== Events ============================ */

/// Event emitted when creating a ToCoinCap object
public struct ToCoinCapCreated<phantom T> has copy, drop {
    to_coin_cap: ID,
}

/// Event emitted when creating a FromCoinCap object
public struct FromCoinCapCreated<phantom T> has copy, drop {
    from_coin_cap: ID,
}

public struct MigrationStarted<phantom T> has copy, drop {
    compatible_versions: vector<u64>,
}

public struct MigrationAborted<phantom T> has copy, drop {
    compatible_versions: vector<u64>,
}

public struct MigrationCompleted<phantom T> has copy, drop {
    compatible_versions: vector<u64>,
}

/// Responsible for handling of token capabilities and policies
public struct Treasury<phantom T> has key, store {
    id: UID,
    roles: Roles<T>,
    active_authorizations: Table<ID, bool>,
    compatible_versions: VecSet<u64>,
}

public fun new<T>(
    treasury_cap: TreasuryCap<T>,
    policy_cap: TokenPolicyCap<T>,
    owner: address,
    ctx: &mut TxContext,
): Treasury<T> {
    let roles = lk_roles::new(owner, ctx);
    let mut treasury = Treasury {
        id: object::new(ctx),
        roles,
        active_authorizations: table::new(ctx),
        compatible_versions: vec_set::singleton(version_control::current_version()),
    };

    dof::add(&mut treasury.id, TreasuryCapKey {}, treasury_cap);
    dof::add(&mut treasury.id, PolicyCapKey {}, policy_cap);
    treasury
}

/* ================= Owner only ============================ */

/// Create a FromCoinCap object and send it to required address
public fun transfer_from_coin_cap<T>(
    treasury: &mut Treasury<T>,
    receiver: address,
    ctx: &mut TxContext,
) {
    assert_is_compatible(treasury);
    let cap = create_from_coin_cap(treasury, ctx);
    transfer::transfer(cap, receiver);
}

/// Composable entry that creates a new FromCoinCap and returns it
fun create_from_coin_cap<T>(treasury: &mut Treasury<T>, ctx: &mut TxContext): FromCoinCap<T> {
    assert!(treasury.roles.owner() == ctx.sender(), ENotOwner);

    let from_coin_cap = FromCoinCap { id: object::new(ctx) };
    table::add(&mut treasury.active_authorizations, object::id(&from_coin_cap), true);
    event::emit(FromCoinCapCreated<T> {
        from_coin_cap: object::id(&from_coin_cap),
    });

    from_coin_cap
}

/// Create a ToCoinCap object and send it to required address
public fun transfer_to_coin_cap<T>(
    treasury: &mut Treasury<T>,
    receiver: address,
    ctx: &mut TxContext,
) {
    assert_is_compatible(treasury);
    let cap = create_to_coin_cap(treasury, ctx);
    transfer::transfer(cap, receiver);
}

/// Composable entry that creates a new ToCoinCap and returns it
fun create_to_coin_cap<T>(treasury: &mut Treasury<T>, ctx: &mut TxContext): ToCoinCap<T> {
    assert!(treasury.roles.owner() == ctx.sender(), ENotOwner);

    let to_coin_cap = ToCoinCap { id: object::new(ctx) };
    table::add(&mut treasury.active_authorizations, object::id(&to_coin_cap), true);
    event::emit(ToCoinCapCreated<T> {
        to_coin_cap: object::id(&to_coin_cap),
    });

    to_coin_cap
}

/// Revokes a previously created cap's rights to use from_coin and to_coin
public fun revoke_authorization<T>(treasury: &mut Treasury<T>, cap_id: ID, ctx: &mut TxContext) {
    assert!(treasury.roles.owner() == ctx.sender(), ENotOwner);
    if (table::contains(&treasury.active_authorizations, cap_id)) {
        let _ = table::remove(&mut treasury.active_authorizations, cap_id);
    }
}

public fun mint_coin_to_receiver<T>(
    treasury: &mut Treasury<T>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    assert_is_compatible(treasury);
    assert!(treasury.roles.owner() == ctx.sender(), ENotOwner);
    let tcap = treasury_mut_cap_ref(treasury);

    tcap.mint_and_transfer<T>(amount, recipient, ctx)
}

public fun transfer_ownership<T>(treasury: &mut Treasury<T>, new_owner: address, ctx: &TxContext) {
    assert!(treasury.roles.owner() == ctx.sender(), ENotOwner);

    treasury.roles.owner_role_mut().begin_role_transfer(new_owner, ctx)
}

public fun accept_ownership<T>(treasury: &mut Treasury<T>, ctx: &TxContext) {
    let pending = treasury.roles.pending_owner();

    assert!(option::is_some(&pending) && option::borrow(&pending) == ctx.sender(), ENotOwner);

    treasury.roles.owner_role_mut().accept_role(ctx)
}

/*======================= Access control ===============================*/

public fun assert_active_auth<T>(treasury: &Treasury<T>, id: ID) {
    assert!(
        table::contains(&treasury.active_authorizations, id) && *table::borrow(&treasury.active_authorizations, id),
        ECapNotAuthorized,
    );
}

/*====================== User facing ==================================*/

/// Checks for a valid ToCoinCap and unwraps the Coin object from the input Token
public fun to_coin<T>(
    treasury: &Treasury<T>,
    to_coin_cap: &ToCoinCap<T>,
    input_token: Token<T>,
    ctx: &mut TxContext,
): coin::Coin<T> {
    assert_is_compatible(treasury);
    assert_active_auth(treasury, object::id(to_coin_cap));
    let (out, mut request) = t::to_coin(input_token, ctx);

    let policy = policy_cap_ref(treasury);
    t::add_approval(ToCoinRule {}, &mut request, ctx);
    t::confirm_with_policy_cap(policy, request, ctx);

    out
}

/// Checks for a valid FromCoinCap and wrapps a Coin into a Token
public fun from_coin<T>(
    treasury: &Treasury<T>,
    from_coin_cap: &FromCoinCap<T>,
    input_coin: coin::Coin<T>,
    ctx: &mut TxContext,
): Token<T> {
    assert_is_compatible(treasury);
    assert_active_auth(treasury, object::id(from_coin_cap));
    let (out, request) = t::from_coin(input_coin, ctx);

    let policy = policy_cap_ref(treasury);
    t::confirm_with_policy_cap(policy, request, ctx);

    out
}

/// Wraps a Coin into a Token and transfers it to the recipient. Only FromCoin cap holders can use this
public fun transfer_from_coin<T>(
    treasury: &mut Treasury<T>,
    recipient: address,
    from_coin_cap: &FromCoinCap<T>,
    input_coin: coin::Coin<T>,
    ctx: &mut TxContext,
) {
    assert_is_compatible(treasury);
    let wrapped_token = from_coin(treasury, from_coin_cap, input_coin, ctx);

    let policy = policy_cap_ref(treasury);
    let request = t::transfer(wrapped_token, recipient, ctx);
    t::confirm_with_policy_cap(policy, request, ctx);
}

public fun compatible_versions<T>(treasury: &Treasury<T>): vector<u64> {
    *treasury.compatible_versions.keys()
}

/// Returns the current active version (lowest version in the set)
public fun current_active_version<T>(treasury: &Treasury<T>): u64 {
    let versions = treasury.compatible_versions.keys();
    if (versions.length() == 1) {
        versions[0]
    } else {
        min(versions[0], versions[1])
    }
}

/// Returns the pending version if migration is in progress, otherwise returns none
public fun pending_version<T>(treasury: &Treasury<T>): Option<u64> {
    if (treasury.compatible_versions.size() == 2) {
        let versions = treasury.compatible_versions.keys();
        option::some(max(versions[0], versions[1]))
    } else {
        option::none()
    }
}

/// Starts the migration process, making the Treasury object be
/// additionally compatible with this package's version.
public fun start_migration<T>(treasury: &mut Treasury<T>, ctx: &TxContext) {
    treasury.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(treasury.compatible_versions.size() == 1, EMigrationStarted);

    let active_version = treasury.compatible_versions.keys()[0];
    assert!(active_version < version_control::current_version(), EObjectMigrated);

    treasury.compatible_versions.insert(version_control::current_version());

    event::emit(MigrationStarted<T> {
        compatible_versions: *treasury.compatible_versions.keys(),
    });
}

/// Aborts the migration process, reverting the Treasury object's compatibility
/// to the previous version.
public fun abort_migration<T>(treasury: &mut Treasury<T>, ctx: &TxContext) {
    treasury.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(treasury.compatible_versions.size() == 2, EMigrationNotStarted);

    let pending_version = max(
        treasury.compatible_versions.keys()[0],
        treasury.compatible_versions.keys()[1],
    );
    assert!(pending_version == version_control::current_version(), ENotPendingVersion);

    treasury.compatible_versions.remove(&pending_version);

    event::emit(MigrationAborted<T> {
        compatible_versions: *treasury.compatible_versions.keys(),
    });
}

/// Completes the migration process, making the Treasury object be
/// only compatible with this package's version.
public fun complete_migration<T>(treasury: &mut Treasury<T>, ctx: &TxContext) {
    treasury.roles.owner_role().assert_sender_is_active_role(ctx);
    assert!(treasury.compatible_versions.size() == 2, EMigrationNotStarted);

    let (version_a, version_b) = (
        treasury.compatible_versions.keys()[0],
        treasury.compatible_versions.keys()[1],
    );
    let (active_version, pending_version) = (min(version_a, version_b), max(version_a, version_b));

    assert!(pending_version == version_control::current_version(), ENotPendingVersion);

    treasury.compatible_versions.remove(&active_version);

    event::emit(MigrationCompleted<T> {
        compatible_versions: *treasury.compatible_versions.keys(),
    });
}

// === Assertions ===

/// [Package private] Asserts that the Treasury object
/// is compatible with the package's version.
public(package) fun assert_is_compatible<T>(treasury: &Treasury<T>) {
    assert_object_version_is_compatible_with_package(treasury.compatible_versions);
}

/// Helper function to check if a migration is in progress
public fun is_migration_in_progress<T>(treasury: &Treasury<T>): bool {
    treasury.compatible_versions.size() > 1
}

/*==================== Internals ======================================*/
fun policy_cap_ref<T>(t: &Treasury<T>): &TokenPolicyCap<T> {
    dof::borrow(&t.id, PolicyCapKey {})
}

fun treasury_cap_ref<T>(t: &Treasury<T>): &TreasuryCap<T> {
    dof::borrow(&t.id, TreasuryCapKey {})
}

fun treasury_mut_cap_ref<T>(t: &mut Treasury<T>): &mut TreasuryCap<T> {
    dof::borrow_mut(&mut t.id, TreasuryCapKey {})
}
