import dotenv from "dotenv";
import express, { Request, Response } from "express";
import { encodeFunctionData } from "viem";
import { getSwapData } from "./utils/swapAggregator";
import addresses from "./test-addresses/1.json";
import { abi as FLASH_LEVERAGE_ABI } from "../abi/FlashLeverage.sol/FlashLeverage.json";
import { CollateralToken } from "./utils/types";

dotenv.config();

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const getCollateralToken = (address: string): CollateralToken =>
  addresses.collateralTokens[address];

const handleError = (res: Response, error: unknown) => {
  console.log(error);
  res.status(500).send("Error");
};

app.get("/leverage", async (req: Request, res: Response) => {
  try {
    const {
      userAddress,
      desiredLtv,
      collateralTokenAddress,
      amountCollateral,
      amountLeverageFlashLoan,
    } = req.query;
    const collateralToken = getCollateralToken(collateralTokenAddress as string);

    const swapData = await getSwapData(
      addresses.flashLeverageAddress,
      collateralToken.loanToken.address,
      collateralToken.address,
      amountLeverageFlashLoan as string
    );

    res.send(
      encodeFunctionData({
        abi: FLASH_LEVERAGE_ABI,
        functionName: "leverage",
        args: [
          userAddress,
          {
            desiredLtv,
            collateralToken: collateralToken.address,
            loanToken: collateralToken.loanToken.address,
            amountCollateral,
            swapData,
            minTokenOut: "0",
          },
        ],
      })
    );
  } catch (error) {
    handleError(res, error);
  }
});

app.get("/deleverage", async (req: Request, res: Response) => {
  try {
    const { positionId, collateralTokenAddress, amountLeveragedCollateral } = req.query;
    const collateralToken = getCollateralToken(collateralTokenAddress as string);

    const swapData = await getSwapData(
      addresses.flashLeverageAddress,
      collateralToken.address,
      collateralToken.loanToken.address,
      amountLeveragedCollateral
    );

    res.send(
      encodeFunctionData({
        abi: FLASH_LEVERAGE_ABI,
        functionName: "deleverage",
        args: [positionId, { swapData, minTokenOut: "0" }],
      })
    );
  } catch (error) {
    handleError(res, error);
  }
});

const PORT = process.env.API_PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));

export default app;
