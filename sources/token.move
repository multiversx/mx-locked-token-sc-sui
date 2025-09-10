module token::token;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::token::{Self, TokenPolicy, Token};
use token::transfer_rule::{Self, TransferRule};

public struct TOKEN has drop {}

fun init(witness: TOKEN, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency<TOKEN>(
        witness,
        2,
        b"RRS",
        b"RRS",
        b"",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    let (mut policy, policy_cap) = token::new_policy<TOKEN>(
        &treasury_cap,
        ctx,
    );
    token::add_rule_for_action<TOKEN, TransferRule>(
        &mut policy,
        &policy_cap,
        token::transfer_action(),
        ctx,
    );
    policy.share_policy();
    transfer::public_transfer(policy_cap, ctx.sender());
    transfer::public_transfer(treasury_cap, ctx.sender())
}

public fun treasure_cap_mint_token(
    treasury_cap: &mut TreasuryCap<TOKEN>,
    amount: u64,
    ctx: &mut TxContext,
) {
    let coin = treasury_cap.mint(amount, ctx);
    let (token, request) = token::from_coin(coin, ctx);
    token::confirm_with_treasury_cap(treasury_cap, request, ctx);
    token.keep(ctx)
}

public fun policy_mint_token(
    treasury_cap: &mut TreasuryCap<TOKEN>,
    policy: &TokenPolicy<TOKEN>,
    amount: u64,
    address: address,
    ctx: &mut TxContext,
) {}

public fun mint_public(
    treasury_cap: &mut TreasuryCap<TOKEN>,
    policy: &TokenPolicy<TOKEN>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = treasury_cap.mint(amount, ctx);
    let (token, mut req) = token::from_coin(coin, ctx);
    token::confirm_with_treasury_cap(treasury_cap, req, ctx);
    let mut req = token::transfer(token, recipient, ctx);
    transfer_rule::verify(policy, &mut req, ctx);
    token::confirm_request(policy, req, ctx);
}

public fun burn(treasury_cap: &mut TreasuryCap<TOKEN>, coin: Coin<TOKEN>) {
    treasury_cap.burn(coin);
}

public fun policy_transfer(
    policy: &TokenPolicy<TOKEN>,
    token: Token<TOKEN>,
    recipient: address,
    ctx: &mut TxContext,
) {
    let mut req = token::transfer(token, recipient, ctx);

    transfer_rule::verify(policy, &mut req, ctx);

    token::confirm_request(policy, req, ctx);
}
