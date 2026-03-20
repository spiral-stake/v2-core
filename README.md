# Spiral Stake V2

Spiral Stake is a non-custodial leveraged yield protocol built on [Morpho Blue](https://morpho.org). It enables flash-loan-based leverage looping on correlated yield-bearing assets — wstETH/WETH, sUSDe/USDC, PT tokens, and more — with isolated per-user positions and on-chain fee accounting.

## Documentation

[docs.spiralstake.com](https://docs.spiralstake.com)

## Architecture

- **FlashLeverage** — Core contract handling leverage, deleverage, and position management via Morpho flash loans
- **UserProxy** — Minimal clone proxies isolating each position on Morpho
- **SwapManager** — Whitelisted router integration for collateral ↔ loan token swaps
- **FlashLeverageRouter** — Entry point for swapping any token into collateral before leveraging

## Setup

```bash
git clone --recurse-submodules <repo-url>
cd lib/morpho-blue && forge build && cd ../..
forge build --via-ir
```

## Testing

```bash
forge test --via-ir
```

## Security

- Audited by [Phage Security](https://phagesecurity.com/)
- Audited by [Cyfrin](https://cyfrin.io)
- AI security scan by [Spearbit](https://spearbit.com)
- Full test suite with adversarial attack scenarios

## License

GPL-3.0-or-later
