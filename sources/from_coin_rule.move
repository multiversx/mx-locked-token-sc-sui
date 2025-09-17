module token::from_coin_rule;

use sui::token::{Self as token, ActionRequest, TokenPolicy, TokenPolicyCap};

const EFromCoinNotAllowed: u64 = 0;

public struct FromCoinRule has drop {}

public struct FromCoinRuleConfig has store {
    allowed: option::Option<address>,
}

public fun init_config<T>(
    policy: &mut TokenPolicy<T>,
    cap: &TokenPolicyCap<T>,
    allowed: option::Option<address>,
    ctx: &mut TxContext,
) {
    let cfg = FromCoinRuleConfig { allowed };
    token::add_rule_config<_, FromCoinRule, FromCoinRuleConfig>(
        FromCoinRule {},
        policy,
        cap,
        cfg,
        ctx,
    )
}

public fun verify<T>(request: &mut ActionRequest<T>, policy: &TokenPolicy<T>, ctx: &mut TxContext) {
    let cfg = token::rule_config<_, FromCoinRule, FromCoinRuleConfig>(FromCoinRule {}, policy);
    if (option::is_some(&cfg.allowed)) {
        let allowed = *option::borrow(&cfg.allowed);
        let sender = request.sender();
        if (sender != allowed) {
            abort EFromCoinNotAllowed
        }
    };

    token::add_approval(FromCoinRule {}, request, ctx);
}

public fun set_from_coin_allowed<T>(
    policy: &mut TokenPolicy<T>,
    cap: &TokenPolicyCap<T>,
    allowed: option::Option<address>,
) {
    let cfg = token::rule_config_mut<_, FromCoinRule, FromCoinRuleConfig>(
        FromCoinRule {},
        policy,
        cap,
    );
    cfg.allowed = allowed
}

public fun clear_from_coin_allowed<T>(policy: &mut TokenPolicy<T>, cap: &TokenPolicyCap<T>) {
    let cfg = token::rule_config_mut<_, FromCoinRule, FromCoinRuleConfig>(
        FromCoinRule {},
        policy,
        cap,
    );
    cfg.allowed = option::none<address>()
}
