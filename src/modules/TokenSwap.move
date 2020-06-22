/// Token Swap

// TODO: replace the address with admin address
address 0x02 {
module TokenSwap {
    use 0x1::Coin;
    use 0x1::FixedPoint32;
    use 0x02::Math;
    // Liquidity Token
    // TODO: token should be generic on <TokenX, TokenY>
    resource struct T {
    }
    resource struct LiquidityTokenCapability {
        mint: Coin::MintCapability,
        burn: Coin::BurnCapability,
    }

    resource struct TokenPair<TokenX, TokenY> {
        token_x_reserve: Coin.T<TokenX>,
        token_y_reserve: Coin.T<TokenY>,
        last_block_timestamp: u64,
        last_price_x_cumulative: u128,
        last_price_y_cumulative: u128,
        last_k: u128,
    }


    // resource struct RegisteredSwapPair<TokenX, TokenY> {
    //     holder: address,
    // }


    /// TODO: check X,Y is token, and X,Y is sorted.

    /// Admin methods

    public fun initialize(signer: &signer) {
        assert_admin(signer);

        let exchange_rate = FixedPoint32::create_from_rational(1, 1);
        Coin::register_currency(account, exchange_rate, 1000000, 1000);

        let mint_capability = Coin::remove_mint_capability(signer);
        let burn_capability = Coin::remove_burn_capability(signer);
        move_to(signer, LiquidityTokenCapability {
            mint: mint_capability,
            burn: burn_capability,
        });
    }

    // for now, only admin can register token pair
    public fun register_swap_pair<TokenX, TokenY>(signer: &signer) {
        assert_admin(signer);
        let token_pair = make_token_pair<TokenX, TokenY>();
        move_to(signer, token_pair);
    }

    fun make_token_pair<X, Y>(): TokenPair<X, Y> {
        // TODO: assert X, Y is coin
        TokenPair<X, Y> {
            token_x_reserve: 0,
            token_y_reserve: 0,
            token_x_balance: Coin.zero<X>(),
            token_y_balance: Coin.zero<Y>(),
            last_block_timestamp: 0,
            last_price_x_cumulative: 0,
            last_price_y_cumulative: 0,
            last_k: 0,
        }
    }

    /// Liquidity Provider's methods

    public fun mint<TokenX, TokenY>(signer: &signer, x: Coin.T<TokenX>, y: Coin.T<TokenY>): Coin.T<Self.T> {
        let total_supply = Coin.market_cap<T>();
        let x_value = Coin.value(&x);
        let y_value = Coin.value(&y);

        let liquidity = if total_supply == 0 {
            // 1000 is the MINIMUM_LIQUIDITY
            Math::sqrt((x_value as u128) * (y_value as u128)) - 1000
        } else {
            let token_pair = borrow_global<TokenPair<TokenX, TokenY>>(admin_address());
            let x_reserve = Coin::value(&token_pair.token_x_reserve);
            let y_reserve = Coin::value(&token_pair.token_y_reserve);

            let x_liquidity = x_value.mul(total_supply) / x_reserve;
            let y_liquidity = y_value.mul(total_supply) / y_reserve;

            // use smaller one.
            if x_liquidity < y_liquidity {
                x_liquidity
            } else {
                y_liquidity
            }
        };
        assert(liquidity > 0, 100);

        let token_pair = borrow_global_mut<TokenPair<TokenX, TokenY>>(admin_address());
        Coin::deposit(&mut token_pair.token_x_reserve, x);
        Coin::deposit(&mut token_pair.token_y_reserve, y);

        let liquidity_cap = borrow_global<LiquidityTokenCapability>(admin_address());
        let mint_token = Coin::mint_with_capability(liquidity, &liquidity_cap.mint);
        mint_token
    }

    public fun burn<TokenX, TokenY>(signer: &signer, to_burn: Coin::T<Self.T>): (Coin.T<TokenX>, Coin.T<TokenY>) {
        let to_burn_value = Coin::value(&to_burn);

        let token_pair = borrow_global_mut<TokenPair<TokenX, TokenY>>(admin_address());
        let x_reserve = Coin::value(&token_pair.token_x_reserve);
        let y_reserve = Coin::value(&token_pair.token_y_reserve);
        let total_supply = Coin.market_cap<T>();

        let x = to_burn_value * x_reserve / total_supply;
        let y = to_burn_value * y_reserve / total_supply;
        assert(x > 0 && y > 0, 101);

        burn_liquidity(to_burn, Signer::address_of(signer));

        let x_token = Coin::withdraw(&mut token_pair.token_x_reserve, x);
        let y_token = Coin::withdraw(&mut token_pair.token_y_reserve, y);

        (x_token, y_token)
    }

    fun burn_liquidity(to_burn: Coin::T<Self.T>, preburn_address: address) {
        let liquidity_cap = borrow_global<LiquidityTokenCapability>(admin_address());
        let preburn = Coin::new_perburn_with_capability<Self.T>(&liquidity_cap.burn);
        Coin::preburn_with_resource(to_burn, &mut preburn, preburn_address);
        Coin::burn_with_resource_cap(&mut preburn, preburn_address, &liquidity_cap.burn);
        Coin::destroy_preburn(preburn);
    }

    /// User methods

    public fun get_reserves<TokenX, TokenY>(): (u64, u64) {
        let token_pair = borrow_global<TokenPair<TokenX, TokenY>>(admin_address());
        let x_reserve = Coin::value(&token_pair.token_x_reserve);
        let y_reserve = Coin::value(&token_pair.token_y_reserve);
        (x_reserve, y_reserve)
    }

    public fun swap<TokenX, TokenY>(signer: &signer, x_in: Coin.T<TokenX>, y_out: u64, y_in: Coin.T<TokenY>, x_out: u64): (Coin.T<TokenX>, Coin.T<TokenY>) {
        let x_in_value = Coin::value(&x_in);
        let y_in_value = Coin::value(&y_in);
        assert(x_in_value > 0 || y_in_value > 0, 400);

        let (x_reserve, y_reserve) = get_reserves<TokenX, TokenY>();

        let token_pair = borrow_global_mut<TokenPair<TokenX, TokenY>>(admin_address());
        Coin::deposit(&mut token_pair.token_x_reserve, x_in);
        Coin::deposit(&mut token_pair.token_y_reserve, y_in);
        let x_swapped = Coin::withdraw(&mut token_pair.token_x_reserve, x_out);
        let y_swapped = Coin::withdraw(&mut token_pair.token_y_reserve, y_out);

        {
            let x_reserve_new = Coin::value(&token_pair.token_x_reserve);
            let y_reserve_new = Coin::value(&token_pair.token_y_reserve);
            let x_adjusted = x_reserve_new * 1000 - x_in_value * 3;
            let y_adjusted = y_reserve_new * 1000 - y_in_value * 3;
            assert(x_adjusted * y_adjusted >= x_reserve * y_reserve * 1000000, 500);
        }

        (x_swapped, y_swapped)
    }

    fun assert_admin(signer: &signer) {
        assert(Signer::address_of(signer) == admin_address(), 401);
    }
    fun admin_address() -> address {
        0x02
    }

}
}
