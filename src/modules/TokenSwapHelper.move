address 0x2 {
module TokenSwapHelper {
  public fun quote(amount_x: u128, reserve_x: u128, reserve_y: u128): u128 {
    assert(amount_x > 0, 400);
    assert(reserve_x > 0 && reserve_y > 0, 410);
    let amount_y = amount_x * reserve_y / reserve_x;
    amount_y
  }

  public fun get_amount_out(amount_in: u128, reserve_in: u128, reserve_out: u128): u128 {
    assert(amount_in > 0, 400);
    assert(reserve_in > 0 && reserve_out > 0, 410);
    let amount_in_with_fee = amount_in * 997;
    let numerator = amount_in_with_fee * reserve_out;
    let denominator = reserve_in * 1000 + amount_in_with_fee;
    numerator / denominator
  }

  public fun get_amount_in(amount_out: u128, reserve_in: u128, reserve_out: u128): u128 {
    assert(amount_out > 0, 400);
    assert(reserve_in > 0 && reserve_out > 0, 410);
    let numerator = reserve_in * amount_out * 1000;
    let denominator = reserve_out - amount_out * 997;
    numerator / denominator + 1
  }
}
}