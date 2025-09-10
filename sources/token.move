module token::token;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::token::{Self, TokenPolicy, ActionRequest, TokenPolicyCap, Token};
use token::transfer_rule::{Self, TransferRule};

public struct TOKEN has drop {}

fun init(witness: TOKEN, ctx: &mut TxContext) {
    let (treasury, metadata) = coin::create_currency(
            witness,
            0,                                // decimals
            b"POC",                           // symbol
            b"Policy-guarded Token",          // name
            b"Demo CLT with OnlyTo", // description
            option::none(),                   // icon URL
            ctx
        );

        let (mut policy, cap) = token::new_policy(&treasury, ctx);

        token::allow<TOKEN>(&mut policy, &cap, token::transfer_action(), ctx);
        token::add_rule_for_action<TOKEN, TransferRule>(&mut policy, &cap, token::transfer_action(), ctx);

        token::share_policy(policy);
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(cap, ctx.sender());
        transfer::public_transfer(treasury, ctx.sender());
}

public fun mint(
    treasury_cap: &mut TreasuryCap<TOKEN>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    treasury_cap.mint_and_transfer(amount, recipient, ctx)
}
public fun set_only_to(
        policy: &mut TokenPolicy<TOKEN>,
        cap: &TokenPolicyCap<TOKEN>,
        allowed: address,
        ctx: &mut TxContext
    ) { transfer_rule::add_config<TOKEN>(policy, cap, allowed, ctx); }

public fun mint_and_transfer(
        cap: &mut TreasuryCap<TOKEN>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ): ActionRequest<TOKEN> {
        let tok: Token<TOKEN> = token::mint(cap, amount, ctx);
        token::transfer(tok, recipient, ctx)
    }