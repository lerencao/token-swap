address 0x2 {
module Staker {
    resource struct Staked<StakeToken, RewardToken> { }
}

module RewardPool {
    use 0x1::Token;
    use 0x1::Block;
    use 0x1::Signer;
    use 0x1::Vector;
    use 0x1::Option;

    /// Pool data
    resource struct T<StakeToken, RewardToken> {
        remaining_rewards: Token::Token<RewardToken>,
        // init once
        duration: u64,
        period_finish: u64,
        reward_rate: u128,
        last_update_time: u64,
        reword_per_token_stored: u128,
        stakes: Token::Token<StakeToken>,
    }

    resource struct Staked<StakeToken, RewardToken> {
        staked: vector<Staking>,
    }

    struct Staking {
        pool_address: address,
        stake: u128,
        reward_info: RewardInfo,
    }

    struct RewardInfo {
        reward_per_token_paid: u128,
        reward: u128,
    }

    /// Called by any one who want to create a reward pool.
    public fun initialize<StakeToken, RewardToken>(
        signer: &signer,
        rewards: Token::Token<RewardToken>,
        duration: u64,
    ) acquires T {
        // init the pool
        let pool = T<StakeToken, RewardToken> {
            remaining_rewards: Token::zero<RewardToken>(),
            duration,
            period_finish: 0,
            reward_rate: 0,
            last_update_time: 0,
            reword_per_token_stored: 0,
            stakes: Token::zero(),
        };
        move_to(signer, pool);
        // dispatch the reward to pool
        notify_rewards<StakeToken, RewardToken>(Signer::address_of(signer), rewards);
    }

    fun notify_rewards<StakeToken, RewardToken>(
        pool_address: address,
        rewards: Token::Token<RewardToken>,
    ) acquires T {
        let pool = borrow_global_mut<T<StakeToken, RewardToken>>(pool_address);
        let reward_share = Token::share<RewardToken>(&rewards);
        let block_number = Block::get_current_block_number();
        let new_reward_rate = if (block_number >= pool.period_finish) {
            reward_share / (pool.duration as u128)
        } else {
            let leftover = (pool.period_finish - block_number as u128) * pool.reward_rate;
            reward_share + leftover / (pool.duration as u128)
        };
        pool.reward_rate = new_reward_rate;
        pool.last_update_time = block_number;
        pool.period_finish = block_number + pool.duration;
        Token::deposit(&mut pool.remaining_rewards, rewards);
    }

    ////////// User parts. ////////
    public fun enter_pool<StakeToken, RewardToken>(signer: &signer) {
        move_to(signer, Staked<StakeToken, RewardToken> { staked: Vector::empty() });
    }

    /// Stake some token into rewardpool to earn reward token
    public fun stake<StakeToken, RewardToken>(
        signer: &signer,
        reward_pool: address,
        to_stake: Token::Token<StakeToken>,
    ) acquires T, Staked {
        assert(Token::share(&to_stake) > 0, 1000);
        if (!exists<Staked<StakeToken, RewardToken>>(Signer::address_of(signer))) {
            enter_pool<StakeToken, RewardToken>(signer);
        };
        let location = {
            let user_staked = borrow_global_mut<Staked<StakeToken, RewardToken>>(
                Signer::address_of(signer),
            );
            let location = locate_staking(&user_staked.staked, reward_pool);
            // add a Staking record if it's first stake into the this pool.
            if (Option::is_none(&location)) {
                Vector::push_back(
                    &mut user_staked.staked,
                    Staking {
                        pool_address: reward_pool,
                        stake: 0,
                        reward_info: RewardInfo { reward_per_token_paid: 0, reward: 0 },
                    },
                );
                Vector::length(&user_staked.staked) - 1
            } else {
                Option::extract(&mut location)
            }
        };
        let user_staked = borrow_global_mut<Staked<StakeToken, RewardToken>>(
            Signer::address_of(signer),
        );
        let staking = Vector::borrow_mut(&mut user_staked.staked, location);
        let pool = borrow_global_mut<T<StakeToken, RewardToken>>(reward_pool);
        _stake(pool, staking, to_stake);
    }

    /// Calculate reward earned.
    public fun earned<StakeToken, RewardToken>(reward_pool: address, account: address): u128
    acquires T, Staked {
        let user_staked = borrow_global<Staked<StakeToken, RewardToken>>(account);
        let location = locate_staking(&user_staked.staked, reward_pool);
        assert(Option::is_some(&location), 1000);
        let location = Option::extract(&mut location);
        let pool = borrow_global<T<StakeToken, RewardToken>>(reward_pool);
        _earned<StakeToken, RewardToken>(Vector::borrow(&user_staked.staked, location), pool)
    }

    public fun staking_info<StakeToken, RewardToken>(
        account: address,
        reward_pool: address,
    ): Option::Option<Staking> acquires Staked {
        let staked = borrow_global<Staked<StakeToken, RewardToken>>(account);
        let location = locate_staking(&staked.staked, reward_pool);
        if (Option::is_some(&location)) {
            Option::some(*Vector::borrow(&staked.staked, Option::extract(&mut location)))
        } else {
            Option::none()
        }
    }

    fun _stake<StakeToken, RewardToken>(
        pool: &mut T<StakeToken, RewardToken>,
        staking: &mut Staking,
        to_stake: Token::Token<StakeToken>,
    ) {
        // we should update reward before update state
        _update_reward(pool, staking);
        // update user's stake info and move the staking token to pool.
        staking.stake = staking.stake + Token::share(&to_stake);
        Token::deposit(&mut pool.stakes, to_stake);
    }

    fun locate_staking(staked: &vector<Staking>, pool_address: address): Option::Option<u64> {
        let stake_len = Vector::length(staked);
        let i = 0;
        while (i < stake_len){
            let staking = Vector::borrow(staked, i);
            if (staking.pool_address == pool_address) {
                return Option::some(i)
            };
            i = i + 1;
        };
        Option::none()
    }

    fun _update_reward<StakeToken, RewardToken>(
        reward_pool: &mut T<StakeToken, RewardToken>,
        user_stake: &mut Staking,
    ) {
        // assert(user_stake.pool_address == reward_pool, 400);
        // update reward pool first.
        let reward_per_token = _reward_per_token<StakeToken, RewardToken>(reward_pool);
        let last_time_reward_applicable = _last_time_reward_applicable<StakeToken, RewardToken>(
            reward_pool,
        );
        reward_pool.reword_per_token_stored = reward_per_token;
        reward_pool.last_update_time = last_time_reward_applicable;
        // then update user reward info.
        let earned = _earned<StakeToken, RewardToken>(user_stake, reward_pool);
        user_stake.reward_info.reward = earned;
        user_stake.reward_info.reward_per_token_paid = _reward_per_token(reward_pool);
    }

    fun _earned<StakeToken, RewardToken>(
        user_stake: &Staking,
        reward_pool: &T<StakeToken, RewardToken>,
    ): u128 {
        let reward_per_token = _reward_per_token<StakeToken, RewardToken>(reward_pool);
        // TODO: merge into one
        let not_reward = reward_per_token - user_stake.reward_info.reward_per_token_paid;
        user_stake.stake * not_reward + user_stake.reward_info.reward
    }

    fun _reward_per_token<StakeToken, RewardToken>(pool: &T<StakeToken, RewardToken>): u128 {
        let total_staked = Token::share(&pool.stakes);
        if (total_staked == 0) {
            pool.reword_per_token_stored
        } else {
            let duration_from_last_time = _last_time_reward_applicable<StakeToken, RewardToken>(
                pool,
            ) - pool.last_update_time;
            let reword_per_token_from_last = (duration_from_last_time as u128) * pool.reward_rate /
                total_staked;
            pool.reword_per_token_stored + reword_per_token_from_last
        }
    }

    public fun _last_time_reward_applicable<StakeToken, RewardToken>(
        pool: &T<StakeToken, RewardToken>,
    ): u64 {
        let block_number = Block::get_current_block_number();
        if (block_number > pool.period_finish) {
            pool.period_finish
        } else {
            block_number
        }
    }
}
}