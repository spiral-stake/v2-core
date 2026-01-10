import BigNumber from "bignumber.js";

export interface Token {
  address: string;
  name: string;
  symbol: string;
  decimals: number;
}

export interface SwapData {
  extRouter: string;
  extCalldata: string;
}

export interface CollateralToken extends Token {
  loanToken: Token;
  pendleMarket: string;
}

export interface Position {
  id: number;
  owner: string;
  collateralToken: Token;
  collateralDeposited: BigNumber;
  stblUSDMinted: BigNumber;
  collateralValueInUsd: BigNumber;
  ltv?: BigNumber;
  borrowApy: BigNumber;
}

export interface LeveragePosition {
  open: boolean;
  owner: string;
  id: number; // user => LeveragePosition[index]
  collateralToken: CollateralToken;
  amountCollateral: BigNumber;
  amountLeveragedCollateral: BigNumber;
  sharesBorrowed: bigint;
  amountLoan: BigNumber;
  ltv: string;
}
