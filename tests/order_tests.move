// ==========
// Initialization Tests
// ==========

// cannot initialize with zero address treasury

// ==========
// Create Note Tests
// ==========

// can create note (including emit event)
// cannot create note if amount is zero
// cannot create note if taker is zero address
// cannot create note if maker is zero address
// cannot create note if almost win payout is more than win payout
// cannot create note if almost win payout is zero
// cannot create note if almost win spread is more than win spread
// cannot create note if taker balance less than amount
// cannot create note if maker balance is less than win amount
// cannot create note if expiry date not in future
// cannot create note if start date is more than expiry date
// cannot create note if payout is less or equal to bet amount
// cannot create note if refund payout is bigger than bet amount
// locks correct amount of collateral from maker and taker


// ==========
// Settle Note Tests
// ==========

// success settle note with win status when bet direction is up (check: emitted event, locked collateral)
// success settle note with win status when bet direction is down (check: emitted event, locked collateral)
// success settle note with lose status when bet direction is up (check: emitted event, locked collateral)
// success settle note with lose status when bet direction is down (check: emitted event, locked collateral)
// success settle note with refund status when bet direction is up (check: emitted event, locked collateral)
// success settle note with refund status when bet direction is down (check: emitted event, locked collateral)
// success settle note with almost win status when bet direction is up (check: emitted event, locked collateral)
// success settle note with almost win status when bet direction is down (check: emitted event, locked collateral)

// cuts fee from win amount when bet is won
// cuts fee from win amount when bet is lost
// doesn't cut fee when bet is refunded
// cuts fee when bet is almost win and payout is less than amount
// cuts fee when bet is almost win and payout is same as amount
// cuts fee when bet is almost win and payout is more than amount
// cuts fee based on refundPayout if refundPayout is set
// 

// cannot settle note if note is not available
// cannot settle same note twice
// cannot settle note if expiry date not passed
// cannot settle note if report timestamp is less expiry time
// cannot settle note if report timestamp is greater expiry time

// ==========
// Set Maker Fee Percentage Tests
// ==========

// success set fee percentage
// cannot set fee percentage greater than 1e18

// ==========
// Set Taker Fee Percentage Tests
// ==========

// success set fee percentage
// cannot set fee percentage greater than 1e18

