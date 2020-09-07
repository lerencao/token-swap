//! account: admin, 0x2
//! account: liquidier
//! account: exchanger

//! new-transaction
//! sender: admin
module Token1 {
  struct Token1 {}
}
// check: EXECUTED

//! new-transaction
//! sender: admin

// register a token pair STC/Token1
script {
use {{admin}}::TokenSwap;
use {{admin}}::Token1;
use 0x1::Token;
use 0x1::STC;
fun main(signer: &signer) {
  Token::register_token<Token1::Token1>(
      signer,
      1000000, // scaling_factor = 10^6
      1000,    // fractional_part = 10^3
  );
  TokenSwap::register_swap_pair<STC::STC, Token1::Token1>(signer);
}
}
// check: EXECUTED

//! new-transaction
//! sender: liquidier
script{
use {{admin}}::Token1;
use 0x1::Account;
fun main(signer: &signer) {
  Account::accept_token<Token1::Token1>(signer);
}
}
// check: EXECUTED

//! new-transaction
//! sender: admin
// mint some token1 to liquidier
script{
use {{admin}}::Token1;

use 0x1::Account;
use 0x1::Token;
fun main(signer: &signer) {
  let token = Token::mint<Token1::Token1>(signer, 100000000);
  Account::deposit_to(signer, {{liquidier}}, token);
  assert(Account::balance<Token1::Token1>({{liquidier}}) == 100000000, 42);
}
}

//! new-transaction
//! sender: liquidier
script{
  use 0x1::STC;
  use {{admin}}::Token1;
  use {{admin}}::TokenSwap;
  use {{admin}}::LiquidityToken::LiquidityToken;
  use 0x1::Account;


  fun main(signer: &signer) {
      Account::accept_token<LiquidityToken<STC::STC, Token1::Token1>>(signer);
      // STC/Token1 = 1:10
      let stc_amount = 1000000;
      let token1_amount = 10000000;
      let stc = Account::withdraw<STC::STC>(signer, stc_amount);
      let token1 = Account::withdraw<Token1::Token1>(signer, token1_amount);
      let liquidity_token = TokenSwap::mint<STC::STC, Token1::Token1>(stc, token1);
      Account::deposit(signer, liquidity_token);

      let (x, y) = TokenSwap::get_reserves<STC::STC, Token1::Token1>();
      assert(x == stc_amount, 111);
      assert(y == token1_amount, 112);
  }
}
// check: EXECUTED

//! new-transaction
//! sender: exchanger
script {
  use 0x1::STC;
  use {{admin}}::Token1;
  use {{admin}}::TokenSwap;
  use {{admin}}::TokenSwapHelper;
  use 0x1::Account;
  use 0x1::Token;
  fun main(signer: &signer) {
      Account::accept_token<Token1::Token1>(signer);

      let stc_amount = 100000;
      let stc = Account::withdraw<STC::STC>(signer, stc_amount);
      let amount_out = {
          let (x, y) = TokenSwap::get_reserves<STC::STC, Token1::Token1>();
          TokenSwapHelper::get_amount_out(stc_amount, x, y)
      };
      let (stc_token, token1_token) = TokenSwap::swap<STC::STC, Token1::Token1>(stc, amount_out, Token::zero<Token1::Token1>(), 0);
      Token::destroy_zero(stc_token);
      Account::deposit(signer, token1_token);
  }
}

//! new-transaction
//! sender: liquidier
script{
  use 0x1::STC;
  use 0x1::Account;
  use 0x1::Signer;
  use {{admin}}::Token1;
  use {{admin}}::TokenSwap;
  use {{admin}}::LiquidityToken::LiquidityToken;

  // use 0x1::Debug;

  fun main(signer: &signer) {
      let liquidity_balance = Account::balance<LiquidityToken<STC::STC, Token1::Token1>>(Signer::address_of(signer));
      let liquidity = Account::withdraw<LiquidityToken<STC::STC, Token1::Token1>>(signer, liquidity_balance);
      let (stc, token1) = TokenSwap::burn<STC::STC, Token1::Token1>(liquidity);
      Account::deposit(signer, stc);
      Account::deposit(signer, token1);

      let (x, y) = TokenSwap::get_reserves<STC::STC, Token1::Token1>();
      assert(x == 0, 111);
      assert(y == 0, 112);
  }
}
// check: EXECUTED
