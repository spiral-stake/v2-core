import dotenv from "dotenv";
import express from "express";
import { getInternalReswapData, getInternalSwapData } from "./utils/swapAggregator";
import addresses from "./test-addresses/1.json";
import { encodeFunctionData } from "viem";
import { abi as FLASH_LEVERAGE_CORE_ABI } from "../abi/FlashLeverageCore.sol/FlashLeverageCore.json";

// This server setup is for providing external swap data in the form of final encoded function data

dotenv.config();
const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.get("/leverage", async (req: any, res: any): Promise<string> => {
  try {
    const {
      userAddress,
      desiredLtv,
      collateralTokenAddress,
      amountCollateral,
      amountLeverageFlashLoan,
    } = req.query;

    const collateralToken = addresses.collateralTokens[collateralTokenAddress];

    const internalSwapData = await getInternalSwapData(
      addresses.flashLeverageCoreAddress,
      collateralToken,
      amountLeverageFlashLoan
    );

    return res.send(
      encodeFunctionData({
        abi: FLASH_LEVERAGE_CORE_ABI,
        functionName: "leverage",
        args: [
          userAddress,
          {
            desiredLtv: desiredLtv,
            collateralToken: collateralToken.address,
            loanToken: collateralToken.loanToken.address,
            amountCollateral: amountCollateral,
            ...internalSwapData,
          },
        ],
      })
    );
  } catch (error) {
    console.log(error.message);
    res.send("Error");
  }
});

app.get("/unleverage", async (req: any, res: any): Promise<string> => {
  try {
    const {
      userAddress,
      desiredLtv,
      collateralTokenAddress,
      sharesToBurn,
      amountCollateralToWithdraw,
    } = req.query;

    const collateralToken = addresses.collateralTokens[collateralTokenAddress];

    const internalReswapData = await getInternalReswapData(
      addresses.flashLeverageCoreAddress,
      collateralToken,
      collateralToken.loanToken.address,
      amountCollateralToWithdraw
    );

    return res.send(
      encodeFunctionData({
        abi: FLASH_LEVERAGE_CORE_ABI,
        functionName: "unleverage",
        args: [
          userAddress,
          {
            desiredLtv: desiredLtv,
            collateralToken: collateralToken.address,
            loanToken: collateralToken.loanToken.address,
            sharesToBurn: sharesToBurn,
            amountCollateralToWithdraw: amountCollateralToWithdraw,
            ...internalReswapData,
          },
        ],
      })
    );
  } catch (error) {
    console.log(error);
    res.send("Error");
  }
});

const PORT = process.env.API_PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

export default app;
