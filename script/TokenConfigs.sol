// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";

/**
 * @title TokenConfigs
 * @dev Configuration contract for collateral token settings
 * @notice Contains all collateral token configurations for the Flash Leverage system
 */
contract TokenConfigs {
    /**
     * @dev Returns all collateral token configurations
     * @return tokenConfigs Array of CollateralTokenConfig structs
     */
    function getTokenConfigs()
        external
        pure
        returns (CollateralTokenConfig[] memory tokenConfigs)
    {
        tokenConfigs = new CollateralTokenConfig[](11);

        // PT-sUSDe
        // USDS
        tokenConfigs[0] = CollateralTokenConfig({
            collateralToken: 0xe6A934089BBEe34F832060CE98848359883749B3,
            morphoMarketId: 0xa79d8028dec527565028fd9fc075b02b498f2b69a1d519dff543ba99b812ff6b,
            pendleMarket: 0xb6aC3d5da138918aC4E84441e924a20daA60dBdd
        });
        // USDC (Insufficient Liquidity)
        // tokenConfigs[0] = CollateralTokenConfig({
        //     collateralToken: 0xe6A934089BBEe34F832060CE98848359883749B3,
        //     morphoMarketId: 0x05702edf1c4709808b62fe65a7d082dccc9386f858ae460ef207ec8dd1debfa2,
        //     pendleMarket: 0xb6aC3d5da138918aC4E84441e924a20daA60dBdd
        // });

        // PT-USDe
        // USDS
        tokenConfigs[1] = CollateralTokenConfig({
            collateralToken: 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7,
            morphoMarketId: 0x8cdb63a27a48ac27fadc0f158a732104bcc4e10bb61c9a5095ea7c127204e26c,
            pendleMarket: 0x4eaA571EaFCD96f51728756BD7F396459BB9B869
        });
        // // USDC
        // tokenConfigs[1] = CollateralTokenConfig({
        //     collateralToken: 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7,
        //     morphoMarketId: 0x534e7046c3aebaa0c6c363cdbeb9392fc87af71cc16862479403a198fe04b206,
        //     pendleMarket: 0x4eaA571EaFCD96f51728756BD7F396459BB9B869
        // });
        // // USDT
        // tokenConfigs[2] = CollateralTokenConfig({
        //     collateralToken: 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7,
        //     morphoMarketId: 0x89c30faadb4d3e748583fe5862b257a9d408f9b64d8e79d4d94b3bd8f2592c1c,
        //     pendleMarket: 0x4eaA571EaFCD96f51728756BD7F396459BB9B869
        // });

        // PT-pUSDe
        // USDC
        tokenConfigs[2] = CollateralTokenConfig({
            collateralToken: 0xF3f491e5608f8B8a6Fd9E9d66a4a4036d7FD282C,
            morphoMarketId: 0x645fba729787a172a49f1661c53a4de57d69c522ba9bb3f2d1fcef0923f9189a,
            pendleMarket: 0xf4C449d6a2D1840625211769779ADA42857d04dD
        });

        // PT-USR
        // USDC (Insufficient Liquidity)
        tokenConfigs[3] = CollateralTokenConfig({
            collateralToken: 0x23e0D07095DAec91B6Ae016cA9F08222dCc64c49,
            morphoMarketId: 0x6920dba94e92cec814cb2be2d5817e6d959ca750c71bd6973402c8a2372ea21b,
            pendleMarket: 0x10e3E052bDee38C468ad092c87D330b59AF6BbeB
        });

        // PT-rUSD
        // USDC
        tokenConfigs[4] = CollateralTokenConfig({
            collateralToken: 0xdcFDf8434e8FDfFF2dD7dfC9299877e813348EE7,
            morphoMarketId: 0xcf90e73ee616097c10278bfedc410a1addc3fd4c5c80b93ef248b91bbd4c062c,
            pendleMarket: 0x04EEb15A3A96b679eEd0a5F490ef89Ec5477F045
        });
        // // rUSD
        // tokenConfigs[5] = CollateralTokenConfig({
        //     collateralToken: 0xdcFDf8434e8FDfFF2dD7dfC9299877e813348EE7,
        //     morphoMarketId: 0x6d388ff5d62b779fc3579c8449b5dd84a893df668a9a64d2aded1bee36887b57,
        //     pendleMarket: 0x04EEb15A3A96b679eEd0a5F490ef89Ec5477F045
        // });

        // PT-slvlUSD (Unlev probem)
        // USDC
        tokenConfigs[5] = CollateralTokenConfig({
            collateralToken: 0x2CA5f2C4300450D53214B00546795c1c07B89acB,
            morphoMarketId: 0x4005ba6eb7d2221fe58102bd320aa6d83c47b212771bc950ab71c5074d9ab0ec,
            pendleMarket: 0xC88FF954d42d3e11D43B62523B3357847C29377c
        });

        // PT-cUSD
        // USDC
        tokenConfigs[6] = CollateralTokenConfig({
            collateralToken: 0x545A490f9ab534AdF409A2E682bc4098f49952e3,
            morphoMarketId: 0x802ec6e878dc9fe6905b8a0a18962dcca10440a87fa2242fbf4a0461c7b0c789,
            pendleMarket: 0x307c15f808914Df5a5DbE17E5608f84953fFa023
        });

        // PT-stcUSD
        // USDC
        tokenConfigs[7] = CollateralTokenConfig({
            collateralToken: 0xC3c7E5E277d31CD24a3Ac4cC9af3B6770F30eA33,
            morphoMarketId: 0x03f715ef1ae508ab3e1faf4dffdbf2a077d1f0ad10c5aad42cf4438d5e3328af,
            pendleMarket: 0xCC781b043933c10a04409b22aaDa3a3D1A7f29D4
        });

        // PT-cUSDL
        // USDC
        tokenConfigs[8] = CollateralTokenConfig({
            collateralToken: 0xDBf6feC5A012A13c456Bac3B67C3B9CF2830A122,
            morphoMarketId: 0xee8b6a54d60c18af9085cef5f90fb3de887f4ebe3f84e21c8222740c1de6d79e,
            pendleMarket: 0x56C4200915D74A7cae45dFa57aB33725B0439193
        });

        // PT-cUSDO
        // USDC
        tokenConfigs[9] = CollateralTokenConfig({
            collateralToken: 0xB10DA2F9147f9cf2B8826877Cd0c95c18A0f42dc,
            morphoMarketId: 0x8a71a66ac828c2b6d4f8accce5859aba0822b502f3833bec4aff09479affffdb,
            pendleMarket: 0x3F53eb4c57c7E7118BE8566bCd503EA502639581
        });
        // // USDT
        // tokenConfigs[10] = CollateralTokenConfig({
        //     collateralToken: 0xB10DA2F9147f9cf2B8826877Cd0c95c18A0f42dc,
        //     morphoMarketId: 0x7fd694cd13880ce994c61e8f8991ce0c9e321e3d50f548dd62a1b6e610d29f32,
        //     pendleMarket: 0x3F53eb4c57c7E7118BE8566bCd503EA502639581
        // });

        // PT-fxSAVE
        // USDC
        tokenConfigs[10] = CollateralTokenConfig({
            collateralToken: 0x21aacE56a8F21210b7E76d8eF1a77253Db85BF0a,
            morphoMarketId: 0x934b5427f2dbcddaddb59e04b8bbb41ef30fb7481eef95366ffa5da4290f1359,
            pendleMarket: 0x9bc2fb257e00468fE921635fe5a73271F385d0EB
        });
    }

    function getTokenWhales()
        external
        pure
        returns (address[] memory tokenWhales)
    {
        tokenWhales = new address[](11);

        tokenWhales[0] = 0xF087C34d81A552D2b82Fe67b8ac3e707a0aDc561; // PT-sUSDE
        tokenWhales[1] = 0x8c31AF1388666aD031c45f25B31017eAAD4C5239; // PT-USDe
        tokenWhales[2] = 0xfF43C5727FbFC31Cb96e605dFD7546eb8862064C; // PT-pUSDe
        tokenWhales[3] = 0x66a4327C7D280aC317A23145a6DEEF1460EE29aC; // PT-USR (bal 100)
        tokenWhales[4] = 0x5a407865411253E5A991d3e49E8Bc7A1FdBE82B0; // PT-rUSD (bal 9000)
        tokenWhales[5] = 0xeA286206550DA203F0eb582185d9C969306B70e3; // PT-slvlUSD
        tokenWhales[6] = 0x68e7E72938db36a5CBbCa7b52c71DBBaaDfB8264; // PT-cUSD
        tokenWhales[7] = 0x1fDDD2218dEf78EE99bd2A5cBD8c5F263fbAe632; // PT-stcUSD
        tokenWhales[8] = 0xc3A1bab8fef2767db914b8c22d0617933a91E3b0; // PT-cUSDL
        tokenWhales[9] = 0x3c9Ea5C4Fec2A77E23Dd82539f4414266Fe8f757; // PT-cUSDO
        tokenWhales[10] = 0xf3aC4D503991Ed1aBa52B03F7cB4e7B4210AB92C; // PT-fxSave
    }
}
