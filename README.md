# Spiral Stake V2

Spiral Stake is leverage execution layer for digital assets. Built on [Morpho Blue](https://morpho.org). It enables flashloan based leverage on correlated & non-correlated markets with isolated user positions.

## Documentation

[docs.spiralstake.com](https://docs.spiralstake.com)

## Architecture

- **FlashLeverage** — Core contract handling leverage, deleverage, and position management via Morpho flash loans
- **UserProxy** — Minimal clone proxies isolating each position on Morpho
- **SwapManager** — Whitelisted router integration for collateral ↔ loan token swaps
- **FlashLeverageRouter** — Entry point for swapping any token into collateral before leveraging

## Setup

```bash
git clone --recurse-submodules https://github.com/spiral-stake/v2-core.git
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
- Audited by [Sherlock](https://sherlock.xyz)
- Full test suite with adversarial attack scenarios

## License

GPL-3.0-or-later
