// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {MarketConfig} from "../src/core/structs/MarketConfig.sol";

struct ChainConfig {
    address morpho;
    address[] swapRouters;
    address treasury;
    address WETH;
    address USDC;
}

/**
 * @title TokenConfig
 * @dev Configuration contract for collateral token settings
 * @notice Contains all collateral token configurations for the Flash Leverage system
 */
contract Config {
    function getChainConfig() internal view returns (ChainConfig memory chain) {
        // Commons
        chain.treasury = 0xeB90258b1F74a846F7941514C7c02Bb03EB249D5;

        if (block.chainid == 31337 || block.chainid == 1) {
            chain.morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

            chain.swapRouters = new address[](2);
            chain.swapRouters[0] = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5; // Kyberswap Router
            chain.swapRouters[1] = 0x888888888889758F76e7103c6CbF23ABbF58F946; // Pendle Swap Router
        } else if (block.chainid == 137) {
            // Polygon
            chain.morpho = 0x1bF0c2541F820E775182832f06c0B7Fc27A25f67;

            chain.swapRouters = new address[](1);
            chain.swapRouters[0] = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5; // Kyberswap Router
        } else if (block.chainid == 747474) {
            // Katana
            chain.morpho = 0xD50F2DffFd62f94Ee4AEd9ca05C61d0753268aBc;

            chain.swapRouters = new address[](1);
            chain.swapRouters[0] = 0xAC4c6e212A361c968F1725b4d055b47E63F80b75; // Sushiswap
        } else if (block.chainid == 98866) {
            // Plume
            chain.morpho = 0x42b18785CE0Aed7BF7Ca43a39471ED4C0A3e0bB5;

            chain.swapRouters = new address[](1);
            chain.swapRouters[0] = 0x85EFA14c12F5fE42Ff9D7Da460A71088b26bEa31; // Eisen Router
        } else if (block.chainid == 999) {
            chain.morpho = 0x68e37dE8d93d3496ae143F2E900490f6280C57cD;

            chain.swapRouters = new address[](2);
            chain.swapRouters[0] = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5; // Kyberswap Router
            chain.swapRouters[1] = 0x888888888889758F76e7103c6CbF23ABbF58F946; // Pendle Swap Router
        }
    }

    function getMarketConfigs()
        internal
        view
        returns (MarketConfig[] memory marketConfigs)
    {
        if (block.chainid == 31337 || block.chainid == 1) {
            marketConfigs = new MarketConfig[](41);

            // weETH
            marketConfigs[0] = MarketConfig({
                marketId: 0x37e7484d642d90f14451f1910ba4b7b8e4c3ccdd0ec28f8b2bdb35479e472ba7,
                isCorrelated: true
            });
            // wstETH
            marketConfigs[1] = MarketConfig({
                marketId: 0xb8fc70e82bc5bb53e773626fcc6a23f7eefa036918d7ef216ecfb1950a94a85e,
                isCorrelated: true
            });
            // siUSD
            marketConfigs[2] = MarketConfig({
                marketId: 0xbbf7ce1b40d32d3e3048f5cf27eeaa6de8cb27b80194690aab191a63381d8c99,
                isCorrelated: true
            });
            // RLP
            marketConfigs[3] = MarketConfig({
                marketId: 0xe1b65304edd8ceaea9b629df4c3c926a37d1216e27900505c04f14b2ed279f33,
                isCorrelated: true
            });
            // stcUSD
            marketConfigs[4] = MarketConfig({
                marketId: 0xeb17955ea422baeddbfb0b8d8c9086c5be7a9cfdefb292119a102e981a30062e,
                isCorrelated: true
            });
            // sUSDS
            marketConfigs[5] = MarketConfig({
                marketId: 0x3274643db77a064abd3bc851de77556a4ad2e2f502f4f0c80845fa8f909ecf0b,
                isCorrelated: true
            });
            // sUSDe
            marketConfigs[6] = MarketConfig({
                marketId: 0x90ef0c5a0dc7c4de4ad4585002d44e9d411d212d2f6258e94948beecf8b4c0d5,
                isCorrelated: true
            });
            // sUSDD
            marketConfigs[7] = MarketConfig({
                marketId: 0x29ae8cad946d861464d5e829877245a863a18157c0cde2c3524434dafa34e476,
                isCorrelated: true
            });
            // syrupUSDT
            marketConfigs[8] = MarketConfig({
                marketId: 0xa4774e3e693fff2ebd1dcbbd69b1b0a5b9bb0ccc753bfda5dd07bdac97c4818a,
                isCorrelated: true
            });
            // wsrUSD
            marketConfigs[9] = MarketConfig({
                marketId: 0x1590cb22d797e226df92ebc6e0153427e207299916e7e4e53461389ad68272fb,
                isCorrelated: true
            });
            // stUSDS
            marketConfigs[10] = MarketConfig({
                marketId: 0x77e624dd9dd980810c2b804249e88f3598d9c7ec91f16aa5fbf6e3fdf6087f82,
                isCorrelated: true
            });
            // syrupUSDC
            marketConfigs[11] = MarketConfig({
                marketId: 0xc9629945524f3fde56c7e8854a6c3d48e76b9d97236abbe73c750fcc7aeb8501,
                isCorrelated: true
            });
            // wsrUSD
            marketConfigs[12] = MarketConfig({
                marketId: 0xa9f70093360419b4544f17a4553ac5847d896be23f020295bd95c24af4df700e,
                isCorrelated: true
            });
            // sUSDe
            marketConfigs[13] = MarketConfig({
                marketId: 0x88a18b2f4d94e7ad27a381b15531c06abf05a7c99dd5d3c3679875fed6f7e742,
                isCorrelated: true
            });
            // wsrUSD
            marketConfigs[14] = MarketConfig({
                marketId: 0x32e253d33f1594a67fc6ef51bf7a39cc4bf2d14904998dee769706fcde489ed9,
                isCorrelated: true
            });
            // sUSDS
            marketConfigs[15] = MarketConfig({
                marketId: 0xa5beccdffd156dfe8c0871f143648c512f0a34f37c8a4ae2ff31ebfe944641d1,
                isCorrelated: true
            });
            // sUSDe
            marketConfigs[16] = MarketConfig({
                marketId: 0xc9098061d437a9dd53b0070cb33df6fca1a0a5ead288588c88699b0420c1c078,
                isCorrelated: true
            });
            // reUSD
            marketConfigs[17] = MarketConfig({
                marketId: 0x4565ac05d38b19374ccbb04c17cca60ca9353cd41824f0803d0fc7704f60eaed,
                isCorrelated: true
            });
            // syzUSD
            marketConfigs[18] = MarketConfig({
                marketId: 0xf4e9fb49e95a34320aea8b5e0ef515391a72368c39bdcf8ad8910645fd6eab97,
                isCorrelated: true
            });
            // RLP
            marketConfigs[19] = MarketConfig({
                marketId: 0x4b86442549b52826e0fc11770ec5154450cb3c5c14dc751a761d81dcfbe7a7b2,
                isCorrelated: true
            });
            // sNUSD
            marketConfigs[20] = MarketConfig({
                marketId: 0xae60b71b407e0517ead445b7113a7ffa07ea4a9379d526ade541a3e9ec777cb4,
                isCorrelated: true
            });
            // syzUSD
            marketConfigs[21] = MarketConfig({
                marketId: 0x9be0fb56b4d52d3632683b632514a2304f6fe1103e081acc358ded09e8e9a1e7,
                isCorrelated: true
            });
            // upGAMMAusdc
            marketConfigs[22] = MarketConfig({
                marketId: 0xe9d96a2f8042486bfd8cfd22692e49cd355e8a51da2f427bdb2d3671fbe978ea,
                isCorrelated: true
            });
            // mAPOLLO
            marketConfigs[23] = MarketConfig({
                marketId: 0x031c7333014af51e4fd18031d14e4eaada58348cde3f6dc6ea8cca16f7387fb2,
                isCorrelated: true
            });
            // sUSN
            marketConfigs[24] = MarketConfig({
                marketId: 0x8924445a76b678c536df977ed9222fb0b23ee5311497dd0223fe6270bb20b4e6,
                isCorrelated: true
            });
            // upUSDC
            marketConfigs[25] = MarketConfig({
                marketId: 0xa0c6499787a7d046f91f2687558c021e2baae5a378885280a448183a926ef5f7,
                isCorrelated: true
            });
            // wsrUSD
            marketConfigs[26] = MarketConfig({
                marketId: 0x08bd0186c5d6ee272f973a307815ac9a8f5ed42bc8308d4b109f254011776c34,
                isCorrelated: true
            });
            // sUSDe
            marketConfigs[27] = MarketConfig({
                marketId: 0x39d11026eae1c6ec02aa4c0910778664089cdd97c3fd23f68f7cd05e2e95af48,
                isCorrelated: true
            });
            // savUSD
            marketConfigs[28] = MarketConfig({
                marketId: 0xe07d416323a1afbfe0bf2fe27ffb549ff565cf5c86d21b79fc60664038e597c9,
                isCorrelated: true
            });
            // jrUSDe
            marketConfigs[29] = MarketConfig({
                marketId: 0x54cebd0c5d5ad84f551a883991c39c470e081a20452eaef47eec2377ffae9f98,
                isCorrelated: true
            });
            // PT-iUSD-19FEB2026
            marketConfigs[30] = MarketConfig({
                marketId: 0xb4b257c2b8001847d361a55fcd30a7bd630750bf492b85b37c4646e42e8e0d8c,
                isCorrelated: true
            });
            // PT-reUSD-25JUN2026
            marketConfigs[31] = MarketConfig({
                marketId: 0x9bc98c2f20ac58287ef2c860eea53a2fdc27c17a7817ff1206c0b7840cc7cd79,
                isCorrelated: true
            });
            // PT-stcUSD-23JUL2026
            marketConfigs[32] = MarketConfig({
                marketId: 0x2fb3713487c7812e7309935b034f40228841666f6b048faf31fd2110ae674f20,
                isCorrelated: true
            });
            // PT-srUSDe-2APR2026
            marketConfigs[33] = MarketConfig({
                marketId: 0x27b9a0a5bfee98a31eb51e3850250d103a9f8e41673c782defc66aa943af0e65,
                isCorrelated: true
            });
            // PT-RLP-9APR2026
            marketConfigs[34] = MarketConfig({
                marketId: 0x1cfdc0154ae6b9f1887a8250f2582d55606e1a2008e65108fb83dd50a928593e,
                isCorrelated: true
            });
            // PT-cUSD-23JUL2026
            marketConfigs[35] = MarketConfig({
                marketId: 0x702b7ec7628de2622e51e1bb34a7e6ad9e95f3a25a2ed361e4ce621f23f5e642,
                isCorrelated: true
            });
            // PT-mAPOLLO-30APR2026
            marketConfigs[36] = MarketConfig({
                marketId: 0x3d353ef0436b85c3b12d53536c19b21c533c046b07c9d92d791a1510e7ef0b74,
                isCorrelated: true
            });
            // PT-siUSD-26MAR2026
            marketConfigs[37] = MarketConfig({
                marketId: 0xaac3ffcdf8a75919657e789fa72ab742a7bbfdf5bb0b87e4bbeb3c29bbbbb05c,
                isCorrelated: true
            });
            // PT-srUSDe-2APR2026
            marketConfigs[38] = MarketConfig({
                marketId: 0xb2f87218f0e2478ba7a2b8be9fe76cbd6f54f8654b9651d4bd1f0ea536674691,
                isCorrelated: true
            });
            // PT-jrUSDe-2APR2026
            marketConfigs[39] = MarketConfig({
                marketId: 0x2afd063a5af8e050069cfad4da95c81768b85b140bea2bd89e00407b15ce82c8,
                isCorrelated: true
            });
            // PT-mHYPER-30APR2026
            marketConfigs[40] = MarketConfig({
                marketId: 0xca432a8b0f33541cfe164d388823d05b607db43b690d4856f343eec3b42402c0,
                isCorrelated: true
            });
        } else if (block.chainid == 137) {
            marketConfigs = new MarketConfig[](2);
            // wstETH
            marketConfigs[0] = MarketConfig({
                marketId: 0xb8ae474af3b91c8143303723618b31683b52e9c86566aa54c06f0bc27906bcae,
                isCorrelated: true
            });
            // MaticX
            marketConfigs[1] = MarketConfig({
                marketId: 0xa932e0d8a9bf52d45b8feac2584c7738c12cf63ba6dff0e8f199e289fb5ca9bb,
                isCorrelated: true
            });
        } else if (block.chainid == 747474) {
            marketConfigs = new MarketConfig[](3);
            // wsrUSD
            marketConfigs[0] = MarketConfig({
                marketId: 0xd8a93a4cd16f843c385391e208a9a9f2fd75aedfcca05e4810e5fbfcaa6baec6,
                isCorrelated: true
            });
            // weETH
            marketConfigs[1] = MarketConfig({
                marketId: 0x1e74d36ffbda65b8a45d72754b349cdd5ce807c5fa814f91ba8e3cd27881c34b,
                isCorrelated: true
            });
            // wstETH
            marketConfigs[2] = MarketConfig({
                marketId: 0x22f9f76056c10ee3496dea6fefeaf2f98198ef597eda6f480c148c6d3aaa70db,
                isCorrelated: true
            });
        } else if (block.chainid == 98866) {
            marketConfigs = new MarketConfig[](4);
            // nALPHA
            marketConfigs[0] = MarketConfig({
                marketId: 0x7a96549cae736c913d12c78ee4c155c2d2f874031fce5acdd07bdbf23d7644c7,
                isCorrelated: true
            });
            // nBASIS
            marketConfigs[1] = MarketConfig({
                marketId: 0x970b184db9382337bf6b693017cf30936a26001fb26bac24e238c77629a75046,
                isCorrelated: true
            });
            // nCREDIT
            marketConfigs[2] = MarketConfig({
                marketId: 0xa05b28928ab7aea096978928cfb3545333b30b36695bf1510922ac1d6a2c044a,
                isCorrelated: true
            });
            // nTBILL
            marketConfigs[3] = MarketConfig({
                marketId: 0xcf3bb7b9935f60d79da7b7bc6405328e6f990b6894895f1df7acfb4c82bc4c5a,
                isCorrelated: true
            });
        } else if (block.chainid == 999) {
            marketConfigs = new MarketConfig[](5);
            // kHYPE
            marketConfigs[0] = MarketConfig({
                marketId: 0x64e7db7f042812d4335947a7cdf6af1093d29478aff5f1ccd93cc67f8aadfddc,
                isCorrelated: true
            });
            // wstHYPE
            marketConfigs[1] = MarketConfig({
                marketId: 0xbcae0d8e381f600b2919194434a0733899697a4c3b6715a5fa75acf8b84bd755,
                isCorrelated: true
            });
            // lstHYPE
            marketConfigs[2] = MarketConfig({
                marketId: 0x0e5172eeb1bbf076fccc101f4a47e6f2db42eb7c39e44bd015c64b5e63e3da3d,
                isCorrelated: true
            });
            // thBILL
            marketConfigs[3] = MarketConfig({
                marketId: 0xfbe436e9aa361487f0c3e4ff94c88aea72887a4482c6b8bcfec60a8584cdb05e,
                isCorrelated: true
            });
            // PT-kHYPE-19MAR2026
            marketConfigs[4] = MarketConfig({
                marketId: 0x6243736b94609da57ca7cb399df512cfae8a112fa5a325d08fd5f4234f5ccd2c,
                isCorrelated: true
            });
        }
    }

    function getCollateralTokenWhales()
        internal
        view
        returns (address[] memory tokenWhales)
    {
        if (block.chainid == 31337 || block.chainid == 1) {
            tokenWhales = new address[](4);
            tokenWhales[0] = 0x41db15f894D304AA2cae85f5D7a5994e4f1D3C12; // wstETH
            tokenWhales[1] = 0x289C204B35859bFb924B9C0759A4FE80f610671c; // siUSD
            tokenWhales[2] = 0x8Cc5a546408C6cE3C9eeB99788F9EC3b8FA6b9F3; // PT-reUSD
            tokenWhales[3] = 0xa427DEf3f920F718A89e5ab473c79C065ab10Ef4; // PT-reUSD
        } else if (block.chainid == 137) {
            tokenWhales = new address[](2);
            tokenWhales[0] = 0xf81bF14Ae234D1B1F13414Fd63Ca064D16b79ad4; // wstETH
            tokenWhales[1] = 0x03ec2cE18792cEff5F835711B294D568E8Cb078a; // MaticX
        }
    }
}
