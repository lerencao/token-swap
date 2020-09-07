// TODO: replace the address with admin address
address 0x2 {
/// Token Swap
module TokenSwap {
    use 0x1::Token;
    use 0x1::Signer;
    use 0x1::Math;
    use 0x2::LiquidityToken::LiquidityToken;

    // Liquidity Token
    // TODO: token should be generic on <X, Y>
    // resource struct T {
    // }
    resource struct LiquidityTokenCapability<X, Y> {
        mint: Token::MintCapability<LiquidityToken<X, Y>>,
        burn: Token::BurnCapability<LiquidityToken<X, Y>>,
    }

    resource struct TokenPair<X, Y> {
        token_x_reserve: Token::Token<X>,
        token_y_reserve: Token::Token<Y>,
        last_block_timestamp: u64,
        last_price_x_cumulative: u128,
        last_price_y_cumulative: u128,
        last_k: u128,
    }

    /// TODO: check X,Y is token, and X,Y is sorted.


    // for now, only admin can register token pair
    public fun register_swap_pair<X, Y>(signer: &signer) {
        assert_admin(signer);
        let token_pair = make_token_pair<X, Y>();
        move_to(signer, token_pair);
        register_liquidity_token<X, Y>(signer);
    }

    fun register_liquidity_token<X, Y>(signer: &signer) {
        assert_admin(signer);
        Token::register_token<LiquidityToken<X, Y>>(signer, 1000000, 1000);
        let mint_capability = Token::remove_mint_capability<LiquidityToken<X, Y>>(signer);
        let burn_capability = Token::remove_burn_capability<LiquidityToken<X, Y>>(signer);
        move_to(signer, LiquidityTokenCapability { mint: mint_capability, burn: burn_capability });
    }

    fun make_token_pair<X, Y>(): TokenPair<X, Y> {
        // TODO: assert X, Y is token
        TokenPair<X, Y> {
            token_x_reserve: Token::zero<X>(),
            token_y_reserve: Token::zero<Y>(),
            last_block_timestamp: 0,
            last_price_x_cumulative: 0,
            last_price_y_cumulative: 0,
            last_k: 0,
        }
    }

    /// Liquidity Provider's methods
    public fun mint<X, Y>(
        x: Token::Token<X>,
        y: Token::Token<Y>,
    ): Token::Token<LiquidityToken<X, Y>> acquires TokenPair, LiquidityTokenCapability {
        let total_supply: u128 = Token::market_cap<LiquidityToken<X, Y>>();
        let x_value = Token::value<X>(&x);
        let y_value = Token::value<Y>(&y);
        let liquidity = if (total_supply == 0) {
            // 1000 is the MINIMUM_LIQUIDITY
            (Math::sqrt((x_value as u128) * (y_value as u128)) as u128) - 1000
        } else {
            let token_pair = borrow_global<TokenPair<X, Y>>(admin_address());
            let x_reserve = Token::value(&token_pair.token_x_reserve);
            let y_reserve = Token::value(&token_pair.token_y_reserve);
            let x_liquidity = x_value * total_supply / x_reserve;
            let y_liquidity = y_value * total_supply / y_reserve;
            // use smaller one.
            if (x_liquidity < y_liquidity) {
                x_liquidity
            } else {
                y_liquidity
            }
        };
        assert(liquidity > 0, 100);
        let token_pair = borrow_global_mut<TokenPair<X, Y>>(admin_address());
        Token::deposit(&mut token_pair.token_x_reserve, x);
        Token::deposit(&mut token_pair.token_y_reserve, y);
        let liquidity_cap = borrow_global<LiquidityTokenCapability<X, Y>>(admin_address());
        let mint_token = Token::mint_with_capability(&liquidity_cap.mint, liquidity);
        mint_token
    }

    public fun burn<X, Y>(
        to_burn: Token::Token<LiquidityToken<X, Y>>,
    ): (Token::Token<X>, Token::Token<Y>) acquires TokenPair, LiquidityTokenCapability {
        let to_burn_value = (Token::value(&to_burn) as u128);
        let token_pair = borrow_global_mut<TokenPair<X, Y>>(admin_address());
        let x_reserve = (Token::value(&token_pair.token_x_reserve) as u128);
        let y_reserve = (Token::value(&token_pair.token_y_reserve) as u128);
        let total_supply = Token::market_cap<LiquidityToken<X, Y>>();
        let x = to_burn_value * x_reserve / total_supply;
        let y = to_burn_value * y_reserve / total_supply;
        assert(x > 0 && y > 0, 101);
        burn_liquidity(to_burn);
        let x_token = Token::withdraw(&mut token_pair.token_x_reserve, x);
        let y_token = Token::withdraw(&mut token_pair.token_y_reserve, y);
        (x_token, y_token)
    }

    fun burn_liquidity<X, Y>(to_burn: Token::Token<LiquidityToken<X, Y>>)
    acquires LiquidityTokenCapability {
        let liquidity_cap = borrow_global<LiquidityTokenCapability<X, Y>>(admin_address());
        Token::burn_with_capability<LiquidityToken<X, Y>>(&liquidity_cap.burn, to_burn);
    }

    /// User methods
    public fun get_reserves<X, Y>(): (u128, u128) acquires TokenPair {
        let token_pair = borrow_global<TokenPair<X, Y>>(admin_address());
        let x_reserve = Token::value(&token_pair.token_x_reserve);
        let y_reserve = Token::value(&token_pair.token_y_reserve);
        (x_reserve, y_reserve)
    }

    public fun swap<X, Y>(
        x_in: Token::Token<X>,
        y_out: u128,
        y_in: Token::Token<Y>,
        x_out: u128,
    ): (Token::Token<X>, Token::Token<Y>) acquires TokenPair {
        let x_in_value = Token::value(&x_in);
        let y_in_value = Token::value(&y_in);
        assert(x_in_value > 0 || y_in_value > 0, 400);
        let (x_reserve, y_reserve) = get_reserves<X, Y>();
        let token_pair = borrow_global_mut<TokenPair<X, Y>>(admin_address());
        Token::deposit(&mut token_pair.token_x_reserve, x_in);
        Token::deposit(&mut token_pair.token_y_reserve, y_in);
        let x_swapped = Token::withdraw(&mut token_pair.token_x_reserve, x_out);
        let y_swapped = Token::withdraw(&mut token_pair.token_y_reserve, y_out);
        {
            let x_reserve_new = Token::value(&token_pair.token_x_reserve);
            let y_reserve_new = Token::value(&token_pair.token_y_reserve);
            let x_adjusted = x_reserve_new * 1000 - x_in_value * 3;
            let y_adjusted = y_reserve_new * 1000 - y_in_value * 3;
            assert(x_adjusted * y_adjusted >= x_reserve * y_reserve * 1000000, 500);
        };
        (x_swapped, y_swapped)
    }

    fun assert_admin(signer: &signer) {
        assert(Signer::address_of(signer) == admin_address(), 401);
    }

    fun admin_address(): address {
        0x2
    }
}
}