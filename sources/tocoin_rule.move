module token::to_coin_rule;

use sui::token::{Self as token, ActionRequest, TokenPolicy, TokenPolicyCap};

const EToCoinNotAllowed: u64 = 0;

public struct ToCoinRule has drop {}

public struct ToCoinRuleConfig has store {
    allowed: option::Option<address>,
}

public fun init_config<T>(
    policy: &mut TokenPolicy<T>,
    cap: &TokenPolicyCap<T>,
    allowed: option::Option<address>,
    ctx: &mut TxContext,
) {
    let cfg = ToCoinRuleConfig { allowed };
    token::add_rule_config<_, ToCoinRule, ToCoinRuleConfig>(ToCoinRule {}, policy, cap, cfg, ctx)
}

public fun verify<T>(request: &mut ActionRequest<T>, policy: &TokenPolicy<T>, ctx: &mut TxContext) {
    let cfg = token::rule_config<_, ToCoinRule, ToCoinRuleConfig>(ToCoinRule {}, policy);
    if (option::is_some(&cfg.allowed)) {
        let allowed = *option::borrow(&cfg.allowed);
        let sender = request.sender();
        if (sender != allowed) {
            abort EToCoinNotAllowed
        }
    };

    token::add_approval(ToCoinRule {}, request, ctx);
}

public fun set_to_coin_allowed<T>(
    policy: &mut TokenPolicy<T>,
    cap: &TokenPolicyCap<T>,
    allowed: option::Option<address>,
) {
    let cfg = token::rule_config_mut<_, ToCoinRule, ToCoinRuleConfig>(
        ToCoinRule {},
        policy,
        cap,
    );
    cfg.allowed = allowed
}

public fun clear_to_coin_allowed<T>(policy: &mut TokenPolicy<T>, cap: &TokenPolicyCap<T>) {
    let cfg = token::rule_config_mut<_, ToCoinRule, ToCoinRuleConfig>(
        ToCoinRule {},
        policy,
        cap,
    );
    cfg.allowed = option::none<address>()
}
