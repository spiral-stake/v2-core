import axios from "axios";
import BigNumber from "bignumber.js";
import { CollateralToken, InternalSwapData, Token } from "./types.ts";
import { InternalReswapData } from "./types.ts";
import { parseUnits } from "./formatUnits.ts";

const HOSTED_SDK_URL = "https://api-v2.pendle.finance/core";
const slippage = 0.01; // 1%
const chainId = 1;

type MethodReturnType<Data> = {
  tx: {
    data: string;
    to: string;
    value: string;
  };
  contractCallParams: any;
  data: Data;
};

export async function callSDK<Data>(path: string, params: Record<string, any> = {}) {
  const response = await axios.get<MethodReturnType<Data>>(HOSTED_SDK_URL + path, {
    params,
  });

  return response.data;
}

export async function getExternalSwapData(
  flashLeverageAddress: string,
  fromToken: Token,
  amount: string,
  collateralToken: CollateralToken
): Promise<InternalSwapData> {
  const params = {
    receiver: flashLeverageAddress,
    slippage,
    tokenIn: fromToken.address,
    tokenOut: collateralToken.address,
    amountIn: parseUnits(amount, fromToken.decimals),
    enableAggregator: true,
    aggregators: "odos, okx, paraswap",
  };

  const res = await callSDK<InternalSwapData>(
    `/v2/sdk/${chainId}/markets/${collateralToken.pendleMarket}/swap`,
    params
  );

  return {
    approxParams: res.contractCallParams[3],
    pendleSwap: res.contractCallParams[4].pendleSwap,
    tokenMintSy: res.contractCallParams[4].tokenMintSy,
    minPtOut: BigInt(res.contractCallParams[2]),
    swapData: res.contractCallParams[4].swapData,
    limitOrderData: res.contractCallParams[5],
  };
}

export async function getInternalSwapData(
  flashLeverageCoreAddress: string,
  collateralToken: CollateralToken,
  amountLeverageFlashLoan: string
): Promise<InternalSwapData> {
  const params = {
    receiver: flashLeverageCoreAddress,
    slippage,
    tokenIn: collateralToken.loanToken.address,
    tokenOut: collateralToken.address,
    amountIn: amountLeverageFlashLoan,
    enableAggregator: true,
    aggregators: "odos, okx, paraswap",
  };

  const res = await callSDK<InternalSwapData>(
    `/v2/sdk/${chainId}/markets/${collateralToken.pendleMarket}/swap`,
    params
  );

  return {
    approxParams: res.contractCallParams[3],
    pendleSwap: res.contractCallParams[4].pendleSwap,
    tokenMintSy: res.contractCallParams[4].tokenMintSy,
    minPtOut: BigInt(res.contractCallParams[2]),
    swapData: res.contractCallParams[4].swapData,
    limitOrderData: res.contractCallParams[5],
  };
}

export async function getInternalReswapData(
  flashLeverageCoreAddress: string,
  collateralToken: CollateralToken,
  loanTokenAddress: string,
  amountLeveragedCollateral: BigNumber
): Promise<InternalReswapData> {
  const params = {
    receiver: flashLeverageCoreAddress,
    slippage,
    tokenIn: collateralToken.address,
    tokenOut: loanTokenAddress,
    amountIn: amountLeveragedCollateral,
    enableAggregator: true,
    aggregators: "odos, okx, paraswap",
  };

  const res = await callSDK<InternalSwapData>(
    `/v2/sdk/${chainId}/markets/${collateralToken.pendleMarket}/swap`,
    params
  );

  return {
    pendleSwap: res.contractCallParams[3].pendleSwap,
    tokenRedeemSy: res.contractCallParams[3].tokenRedeemSy,
    minTokenOut: BigInt(res.contractCallParams[3].minTokenOut),
    swapData: res.contractCallParams[3].swapData,
    limitOrderData: res.contractCallParams[4],
  };
}
