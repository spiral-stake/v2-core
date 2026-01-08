# Spiral Stake - Stable Leveraged Yields

Spiral Stake is a non-custodial leveraged yield protocol designed exclusively for stablecoin holders, providing access to effortless stable leveraged yields. We make this possible by locking in fixed yield from staked stablecoins and then FlashLeveraging it at a safe LTV to deliver leveraged returns to users without compromising on security.

Building on the foundation established by Pendle PTs, which solved the fixed yield side of the equation, Spiral Stake completes the puzzle by solving the fixed borrow rate side — enabling stable, predictable leveraged yield products that function like high-yield fixed deposits with DeFi upside.

## Current Architecture

### Integrations

Pendle PTs - We exclusively support Pendle PTs as collateral tokens for leveraging, due to their ability to deliver a stable and predictable yield profile. This stability aligns with Spiral Stake’s mission to provide consistent, high-yield returns, shielding users from the volatility of broader market fluctuations.

Morpho Markets - Morpho serves as our primary lending protocol for the following strategic advantages:

1. Broad PT Compatibility - Morpho’s money markets support an extensive range of staked stablecoin PTs as collateral, offering users unparalleled flexibility.
2. Enhanced Capital Efficiency - Morpho provides superior interest rates and utilization efficiency compared to conventional lending protocols, optimizing returns for our users.

### Contracts

1. FlashLeverageCore - The core engine that handles the logic for our FlashLeverage mechanism
   Key Functions:
   a. leverage()
   b. deleverage()
   c. calcFlashLoanAmount()
   d. getCoreLeveragePosition()
   e. getSafeLtv

2. FlashLeverage - The user-facing contract that simplifies interaction and manages position registry
   Key Functions:
   a. leverage()
   b. swapAndLeverage()
   c. deleverage()
   d. getUserLeveragePositions()

### FlashLeverage Mechanism

The FlashLeverage mechanism eliminates the need for iterative borrowing loops by leveraging geometric progression mathematics. Instead of manually looping through deposit-borrow cycles, we calculate the optimal final position upfront.

#### Geometric Progression Formula:

The total leveraged position can be calculated as: Final Deposit = initial_input / (1 - LTV)

#### Example:

Consider depositing 1000 USDT with 75% LTV:

Traditional Approach: 24+ loops to reach ~4000 USDT deposit position
FlashLeverage Approach: Single transaction achieving the same result

Calculation:
Final Position = 1000 / (1 - 0.75) = 4000 USDT
Required Loan = 4000 - 1000 = 3000 USDT

Single-Step Execution:

1. Flash Loan: Borrow 3000 USDT (calculated optimal amount)
2. Total Capital: 1000 (initial) + 3000 (borrowed) = 4000 USDT
3. Deposit: Supply 4000 USDT to lending protocol
4. Borrow: Extract 3000 USDT (75% of 4000) from protocol
5. Repay: Return 3000 USDT to flash loan

Result: 4000 USDT earning interest with 3000 USDT borrowed position - identical to 24 manual loops but executed in a single atomic transaction with minimal gas costs and no intermediate slippage risk.
