// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {MarketConfig} from "../src/core/structs/MarketConfig.sol";

struct ChainConfig {
    address owner;
    address morpho;
    address publicAllocator;
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
        chain.owner = 0x47C9fD3AFd07ec00a2264c74FA4AC889f11454cc;

        if (block.chainid == 31337 || block.chainid == 1) {
            chain.morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
            chain.publicAllocator = 0xfd32fA2ca22c76dD6E550706Ad913FC6CE91c75D;

            chain.swapRouters = new address[](2);
            chain.swapRouters[0] = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5; // Kyberswap Router
            chain.swapRouters[1] = 0x888888888889758F76e7103c6CbF23ABbF58F946; // Pendle Swap Router
        } else if (block.chainid == 137) {
            // Polygon
            chain.morpho = 0x1bF0c2541F820E775182832f06c0B7Fc27A25f67;
            chain.publicAllocator = 0xfac15aff53ADd2ff80C2962127C434E8615Df0d3;

            chain.swapRouters = new address[](1);
            chain.swapRouters[0] = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5; // Kyberswap Router
        } else if (block.chainid == 747474) {
            // Katana
            chain.morpho = 0xD50F2DffFd62f94Ee4AEd9ca05C61d0753268aBc;
            chain.publicAllocator = 0x39EB6Da5e88194C82B13491Df2e8B3E213eD2412;

            chain.swapRouters = new address[](1);
            chain.swapRouters[0] = 0xAC4c6e212A361c968F1725b4d055b47E63F80b75; // Sushiswap
        } else if (block.chainid == 98866) {
            // Plume
            chain.morpho = 0x42b18785CE0Aed7BF7Ca43a39471ED4C0A3e0bB5;
            chain.publicAllocator = 0x58485338D93F4e3b4Bf2Af1C9f9C0aDF087AEf1C;

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
            marketConfigs = new MarketConfig[](53);

            // ============ Correlated Markets ============

            // sUSDS/USDT
            marketConfigs[0] = MarketConfig({
                marketId: 0x3274643db77a064abd3bc851de77556a4ad2e2f502f4f0c80845fa8f909ecf0b,
                isCorrelated: true
            });
            // sUSDe/PYUSD
            marketConfigs[1] = MarketConfig({
                marketId: 0x90ef0c5a0dc7c4de4ad4585002d44e9d411d212d2f6258e94948beecf8b4c0d5,
                isCorrelated: true
            });
            // wsrUSD/USDC
            marketConfigs[2] = MarketConfig({
                marketId: 0x1590cb22d797e226df92ebc6e0153427e207299916e7e4e53461389ad68272fb,
                isCorrelated: true
            });
            // syrupUSDC/RLUSD
            marketConfigs[3] = MarketConfig({
                marketId: 0xc0ae375fd761ff19b3f04de5534c0f1ec110f80e1c2ede27c42c1c43c3040394,
                isCorrelated: true
            });
            // wstETH/WETH
            marketConfigs[4] = MarketConfig({
                marketId: 0xb8fc70e82bc5bb53e773626fcc6a23f7eefa036918d7ef216ecfb1950a94a85e,
                isCorrelated: true
            });
            // AA_FalconXUSDC/USDC
            marketConfigs[5] = MarketConfig({
                marketId: 0xe83d72fa5b00dcd46d9e0e860d95aa540d5ec106da5833108a9f826f21f36f52,
                isCorrelated: true
            });
            // weETH/WETH
            marketConfigs[6] = MarketConfig({
                marketId: 0x37e7484d642d90f14451f1910ba4b7b8e4c3ccdd0ec28f8b2bdb35479e472ba7,
                isCorrelated: true
            });
            // LBTC/WBTC
            marketConfigs[7] = MarketConfig({
                marketId: 0xf6a056627a51e511ec7f48332421432ea6971fc148d8f3c451e14ea108026549,
                isCorrelated: true
            });
            // sUSDe/USDtb
            marketConfigs[8] = MarketConfig({
                marketId: 0x88a18b2f4d94e7ad27a381b15531c06abf05a7c99dd5d3c3679875fed6f7e742,
                isCorrelated: true
            });
            // wsrUSD/USDT
            marketConfigs[9] = MarketConfig({
                marketId: 0xa9f70093360419b4544f17a4553ac5847d896be23f020295bd95c24af4df700e,
                isCorrelated: true
            });
            // stcUSD/USDC
            marketConfigs[10] = MarketConfig({
                marketId: 0xeb17955ea422baeddbfb0b8d8c9086c5be7a9cfdefb292119a102e981a30062e,
                isCorrelated: true
            });
            // mF-ONE/USDC
            marketConfigs[11] = MarketConfig({
                marketId: 0xef2c308b5abecf5c8750a1aa82b47c558005feb7a03f4f8e1ad682d71ac8d0ba,
                isCorrelated: true
            });
            // stUSDS/USDC
            marketConfigs[12] = MarketConfig({
                marketId: 0xd570c19c0dc0fbe4ab7faf4a37c4150e1c141c8aada8ca3e1b4b6c1b712af93d,
                isCorrelated: true
            });
            // syrupUSDC/PYUSD
            marketConfigs[13] = MarketConfig({
                marketId: 0xc9629945524f3fde56c7e8854a6c3d48e76b9d97236abbe73c750fcc7aeb8501,
                isCorrelated: true
            });
            // sUSDS/AUSD
            marketConfigs[14] = MarketConfig({
                marketId: 0x09cf702bb8b6fe8c6effb6021744e365f598b89bc28f3ea7cd6c55115af825df,
                isCorrelated: true
            });
            // ETH+/WETH
            marketConfigs[15] = MarketConfig({
                marketId: 0x5f8a138ba332398a9116910f4d5e5dcd9b207024c5290ce5bc87bc2dbd8e4a86,
                isCorrelated: true
            });
            // sUSDD/USDT
            marketConfigs[16] = MarketConfig({
                marketId: 0x29ae8cad946d861464d5e829877245a863a18157c0cde2c3524434dafa34e476,
                isCorrelated: true
            });
            // sUSDat/AUSD
            marketConfigs[17] = MarketConfig({
                marketId: 0x582fdc4176da0ab5c65e086603ab9ecd9188e889e16efef6e35854cf14e15065,
                isCorrelated: true
            });
            // siUSD/msUSD
            marketConfigs[18] = MarketConfig({
                marketId: 0x64d2f82e674b764d618b630297813cd34bdc42a0fa66f92efa2ac8b1efe4bbd5,
                isCorrelated: true
            });
            // stcUSD/USDT
            marketConfigs[19] = MarketConfig({
                marketId: 0xdbf4bc065d4e76f4505a523f2bba5e5ccdca94c16d67c3a6ff1dadbcbb26d4aa,
                isCorrelated: true
            });
            // sUSN/USDC
            marketConfigs[20] = MarketConfig({
                marketId: 0x8924445a76b678c536df977ed9222fb0b23ee5311497dd0223fe6270bb20b4e6,
                isCorrelated: true
            });
            // upGAMMAusdc/AUSD
            marketConfigs[21] = MarketConfig({
                marketId: 0xe9d96a2f8042486bfd8cfd22692e49cd355e8a51da2f427bdb2d3671fbe978ea,
                isCorrelated: true
            });
            // savUSD/USDC
            marketConfigs[22] = MarketConfig({
                marketId: 0xe07d416323a1afbfe0bf2fe27ffb549ff565cf5c86d21b79fc60664038e597c9,
                isCorrelated: true
            });
            // siUSD/USDC
            marketConfigs[23] = MarketConfig({
                marketId: 0xbbf7ce1b40d32d3e3048f5cf27eeaa6de8cb27b80194690aab191a63381d8c99,
                isCorrelated: true
            });
            // savETH/WETH
            marketConfigs[24] = MarketConfig({
                marketId: 0xd98cd88ae5b336086b39fb1d62ba6171282e946105b010143f0e89f8fe7cff36,
                isCorrelated: true
            });
            // syrupUSDC/AUSD
            marketConfigs[25] = MarketConfig({
                marketId: 0xab3196447663a41382ba4b4d55eab3fa702ee2cf071db224fd72492953040056,
                isCorrelated: true
            });
            // syzUSD/USDC
            marketConfigs[26] = MarketConfig({
                marketId: 0xf4e9fb49e95a34320aea8b5e0ef515391a72368c39bdcf8ad8910645fd6eab97,
                isCorrelated: true
            });

            // ============ Pendle PT Markets (Correlated) ============

            // PT-apyUSD-18JUN2026/USDC
            marketConfigs[27] = MarketConfig({
                marketId: 0xa75bb490ecfee90c86a9d22ebc2dde42fb83478b3f18722b9fc6f5f668cab124,
                isCorrelated: true
            });
            // PT-reUSD-25JUN2026/USDC
            marketConfigs[28] = MarketConfig({
                marketId: 0x9bc98c2f20ac58287ef2c860eea53a2fdc27c17a7817ff1206c0b7840cc7cd79,
                isCorrelated: true
            });
            // PT-USDG-28MAY2026/USDC
            marketConfigs[29] = MarketConfig({
                marketId: 0x5cebfae10f5e88d33df2421923f3d9f32359429fda2f78edacc9b4fdb09b0553,
                isCorrelated: true
            });
            // PT-reUSD-25JUN2026/USDT
            marketConfigs[30] = MarketConfig({
                marketId: 0x3fea56ab83b05840dc83dc6b3d2f2fbd938147cbaa8126bac529e6c820058253,
                isCorrelated: true
            });
            // PT-sUSDE-7MAY2026/PYUSD
            marketConfigs[31] = MarketConfig({
                marketId: 0xcb12dcbc7c6c4f20ca1537a3cc1a41ec27501f85a3e322a710d9a16a88a28c0e,
                isCorrelated: true
            });
            // PT-apxUSD-18JUN2026/USDC
            marketConfigs[32] = MarketConfig({
                marketId: 0xed05fcc2893b78b3fa468d21b6e4d2925e7f2c64eb1f16279757c43f87502a99,
                isCorrelated: true
            });
            // PT-avUSD-14MAY2026/USDC
            marketConfigs[33] = MarketConfig({
                marketId: 0xf80a664057fe3cadcd9e83f27bb1effe5c15d1d2648acc7634daff1581951b5e,
                isCorrelated: true
            });
            // PT-savUSD-14MAY2026/USDC
            marketConfigs[34] = MarketConfig({
                marketId: 0xc978f01522ff64adafd91856065d602c56e326a0368b895bd9244d5998e60076,
                isCorrelated: true
            });
            // PT-srNUSD-28MAY2026/USDC
            marketConfigs[35] = MarketConfig({
                marketId: 0xc2bc5e1e304fb1ea103dcbee37ece3c7e9219fb4b2b19d8ffdf81c39f4fbf180,
                isCorrelated: true
            });
            // PT-sNUSD-4JUN2026/USDC
            marketConfigs[36] = MarketConfig({
                marketId: 0xb62aac664f81d19f21a158aa0373967ef60fd1ac8de4a9091bd225c007973ca6,
                isCorrelated: true
            });
            // PT-apxUSD-18JUN2026/apxUSD
            marketConfigs[37] = MarketConfig({
                marketId: 0xf3814af4869a6ce59ffef016e555dd4c1e92bf383b5ab89abe496044c6364746,
                isCorrelated: true
            });
            // PT-cUSD-23JUL2026/USDC
            marketConfigs[38] = MarketConfig({
                marketId: 0x702b7ec7628de2622e51e1bb34a7e6ad9e95f3a25a2ed361e4ce621f23f5e642,
                isCorrelated: true
            });
            // PT-mAPOLLO-30APR2026/USDC
            marketConfigs[39] = MarketConfig({
                marketId: 0x3d353ef0436b85c3b12d53536c19b21c533c046b07c9d92d791a1510e7ef0b74,
                isCorrelated: true
            });

            // ============ Non-Correlated Markets ============

            // cbBTC/USDC
            marketConfigs[40] = MarketConfig({
                marketId: 0x64d65c9a2d91c36d56fbc42d69e979335320169b3df63bf92789e2c8883fcc64,
                isCorrelated: false
            });
            // wstETH/USDT
            marketConfigs[41] = MarketConfig({
                marketId: 0xe7e9694b754c4d4f7e21faf7223f6fa71abaeb10296a4c43a54a7977149687d2,
                isCorrelated: false
            });
            // WBTC/USDC
            marketConfigs[42] = MarketConfig({
                marketId: 0x3a85e619751152991742810df6ec69ce473daef99e28a64ab2340d7b7ccfee49,
                isCorrelated: false
            });
            // wstETH/USDC
            marketConfigs[43] = MarketConfig({
                marketId: 0xb323495f7e4148be5643a4ea4a8221eef163e4bccfdedc2a6f4696baacbc86cc,
                isCorrelated: false
            });
            // WBTC/USDT
            marketConfigs[44] = MarketConfig({
                marketId: 0xa921ef34e2fc7a27ccc50ae7e4b154e16c9799d3387076c421423ef52ac4df99,
                isCorrelated: false
            });
            // weETH/PYUSD
            marketConfigs[45] = MarketConfig({
                marketId: 0x85d59152eeeab7ca024804895b358868d8dd1e134171be400d7792d5604a212c,
                isCorrelated: false
            });
            // cbBTC/USDT
            marketConfigs[46] = MarketConfig({
                marketId: 0x45671fb8d5dea1c4fbca0b8548ad742f6643300eeb8dbd34ad64a658b2b05bca,
                isCorrelated: false
            });
            // OETH/USDC
            marketConfigs[47] = MarketConfig({
                marketId: 0xb8fef900b383db2dbbf4458c7f46acf5b140f26d603a6d1829963f241b82510e,
                isCorrelated: false
            });
            // weETH/RLUSD
            marketConfigs[48] = MarketConfig({
                marketId: 0xea4bfb18df0ee6bffb7b3f0270899a8adb92ab6b684709634c8276128813cfd4,
                isCorrelated: false
            });
            // WBTC/EURC
            marketConfigs[49] = MarketConfig({
                marketId: 0xff527fe9c6516f9d82a3d51422ccb031d123266e6e26d4c22c942a948c180a75,
                isCorrelated: false
            });
            // weETH/USDC
            marketConfigs[50] = MarketConfig({
                marketId: 0x61765602144e91e5ac9f9e98b8584eae308f9951596fd7f5e0f59f21cd2bf664,
                isCorrelated: false
            });
            // cbBTC/EURCV
            marketConfigs[51] = MarketConfig({
                marketId: 0x82053fe2fc3a3d6cb856458948e9c3589e76f20f3a2079606739b517587267ce,
                isCorrelated: false
            });

            // Tokenised Stocks
            marketConfigs[52] = MarketConfig({
                marketId: 0xbf0432567b44ef5ce013ffcd7dd756c522252503f7986a406e780715b32c74fc,
                isCorrelated: false
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
            marketConfigs = new MarketConfig[](7);
            // Correlated Markets //

            // weETH
            marketConfigs[0] = MarketConfig({
                marketId: 0x1e74d36ffbda65b8a45d72754b349cdd5ce807c5fa814f91ba8e3cd27881c34b,
                isCorrelated: true
            });

            // Non-correlated Markets

            // vbwbtc-vbusdc
            marketConfigs[1] = MarketConfig({
                marketId: 0xcd2dc555dced7422a3144a4126286675449019366f83e9717be7c2deb3daae3e,
                isCorrelated: false
            });

            // weeth-vbusdt
            marketConfigs[2] = MarketConfig({
                marketId: 0xa6ce59291d90ae348b2fa956cc66f31df605a3304a9325e494c94e2cf5b0485a,
                isCorrelated: false
            });

            // vbWBTC/vbUSDT
            marketConfigs[3] = MarketConfig({
                marketId: 0xd4ab732112fa9087c9c3c3566cd25bc78ee7be4f1b8bdfe20d6328debb818656,
                isCorrelated: false
            });

            // weETH/vbUSDT
            marketConfigs[4] = MarketConfig({
                marketId: 0xbb4fb94ca819744df6a8f3932fffad47d31e8d76d3c48216878295c4cf588caf,
                isCorrelated: false
            });

            // vbETH/vbUSDT
            marketConfigs[5] = MarketConfig({
                marketId: 0x9e03fc0dc3110daf28bc6bd23b32cb20b150a6da151856ead9540d491069db1c,
                isCorrelated: false
            });

            //vbETH/vbUSDC
            marketConfigs[6] = MarketConfig({
                marketId: 0x2fb14719030835b8e0a39a1461b384ad6a9c8392550197a7c857cf9fcbd6c534,
                isCorrelated: false
            });

            // Future listings (swap route unavailable ATM)
            // yvvbETH/vbUSDC
            // yvvbUSDC/vbUSDT
            // yvvbUSDT/vbUSDC
            // yvAUSD/vbUSDC
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
}
