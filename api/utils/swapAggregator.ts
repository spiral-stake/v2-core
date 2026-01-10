import axios from "axios";
import BigNumber from "bignumber.js";

const HOSTED_SDK_URL = "https://api-v2.pendle.finance/core";
const CHAIN_ID = 1;
const SLIPPAGE = 0.01;

async function callSDK(path: string, params: Record<string, any>) {
  const { data } = await axios.get(`${HOSTED_SDK_URL}${path}`, { params });
  return data;
}

export const getSwapData = async (
  receiver: string,
  tokenIn: string,
  tokenOut: string,
  amountIn: string | BigNumber
) => {
  const res = await callSDK(`/v2/sdk/${CHAIN_ID}/convert`, {
    receiver,
    slippage: SLIPPAGE,
    tokensIn: tokenIn,
    tokensOut: tokenOut,
    amountsIn: amountIn,
    enableAggregator: true,
    aggregators: "kyberswap, okx",
  });

  return {
    extRouter: res.routes[0].tx.to,
    extCalldata: res.routes[0].tx.data,
  };
};
