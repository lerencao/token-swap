address 0x02 {
    module Math {
        // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
        public fun sqrt(u128 y): u64 {
            if y < 4 {
                if y == 0 {
                    return 0u64;
                } else {
                    return 1u64;
                }
            } else {
                let z = y;
                let x = y / 2 + 1;
                while (x < z) {
                    z = x;
                    x = (y / x + x) / 2;
                }
                return (z as u64);
            }
        }
    }
}