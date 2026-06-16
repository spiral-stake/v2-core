// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {CommonBase} from "forge-std/Base.sol";
import {MarketConfig} from "../src/core/structs/MarketConfig.sol";

struct ChainConfig {
    address owner;
    address morpho;
    address publicAllocator;
    address[] swapRouters;
    address treasury;
}

/**
 * @title TokenConfig
 * @dev Configuration contract for collateral token settings
 * @notice Contains all collateral token configurations for the Flash Leverage system
 */
contract Config is CommonBase {
    function getChainConfig() internal view returns (ChainConfig memory chain) {
        // Commons
        chain.treasury = vm.envAddress("TREASURY");
        chain.owner = msg.sender;

        if (block.chainid == 31337 || block.chainid == 1) {
            chain.morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
            chain.publicAllocator = 0xfd32fA2ca22c76dD6E550706Ad913FC6CE91c75D;

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
            marketConfigs = new MarketConfig[](84);

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

            // PT-reUSD-25JUN2026/USDC
            marketConfigs[27] = MarketConfig({
                marketId: 0x9bc98c2f20ac58287ef2c860eea53a2fdc27c17a7817ff1206c0b7840cc7cd79,
                isCorrelated: true
            });
            // PT-reUSD-25JUN2026/USDT
            marketConfigs[28] = MarketConfig({
                marketId: 0x3fea56ab83b05840dc83dc6b3d2f2fbd938147cbaa8126bac529e6c820058253,
                isCorrelated: true
            });
            // PT-cUSD-23JUL2026/USDC
            marketConfigs[29] = MarketConfig({
                marketId: 0x702b7ec7628de2622e51e1bb34a7e6ad9e95f3a25a2ed361e4ce621f23f5e642,
                isCorrelated: true
            });

            // ============ Non-Correlated Markets ============

            // cbBTC/USDC
            marketConfigs[30] = MarketConfig({
                marketId: 0x64d65c9a2d91c36d56fbc42d69e979335320169b3df63bf92789e2c8883fcc64,
                isCorrelated: false
            });
            // wstETH/USDT
            marketConfigs[31] = MarketConfig({
                marketId: 0xe7e9694b754c4d4f7e21faf7223f6fa71abaeb10296a4c43a54a7977149687d2,
                isCorrelated: false
            });
            // WBTC/USDC
            marketConfigs[32] = MarketConfig({
                marketId: 0x3a85e619751152991742810df6ec69ce473daef99e28a64ab2340d7b7ccfee49,
                isCorrelated: false
            });
            // wstETH/USDC
            marketConfigs[33] = MarketConfig({
                marketId: 0xb323495f7e4148be5643a4ea4a8221eef163e4bccfdedc2a6f4696baacbc86cc,
                isCorrelated: false
            });
            // WBTC/USDT
            marketConfigs[34] = MarketConfig({
                marketId: 0xa921ef34e2fc7a27ccc50ae7e4b154e16c9799d3387076c421423ef52ac4df99,
                isCorrelated: false
            });
            // weETH/PYUSD
            marketConfigs[35] = MarketConfig({
                marketId: 0x85d59152eeeab7ca024804895b358868d8dd1e134171be400d7792d5604a212c,
                isCorrelated: false
            });
            // cbBTC/USDT
            marketConfigs[36] = MarketConfig({
                marketId: 0x45671fb8d5dea1c4fbca0b8548ad742f6643300eeb8dbd34ad64a658b2b05bca,
                isCorrelated: false
            });
            // OETH/USDC
            marketConfigs[37] = MarketConfig({
                marketId: 0xb8fef900b383db2dbbf4458c7f46acf5b140f26d603a6d1829963f241b82510e,
                isCorrelated: false
            });
            // weETH/RLUSD
            marketConfigs[38] = MarketConfig({
                marketId: 0xea4bfb18df0ee6bffb7b3f0270899a8adb92ab6b684709634c8276128813cfd4,
                isCorrelated: false
            });
            // cbBTC/RLUSD
            marketConfigs[39] = MarketConfig({
                marketId: 0xffd010618ed3cb39bb2c5de0e3e58d3d2ec9f52187a180f29723c31756a939bc,
                isCorrelated: false
            });
            // LBTC/PYUSD
            marketConfigs[40] = MarketConfig({
                marketId: 0x6a7e36eb088bd501d73f7ab4c5b8671358559341a78ce521c9e499dc0bc642b9,
                isCorrelated: false
            });
            // weETH/USDT
            marketConfigs[41] = MarketConfig({
                marketId: 0xc2c53d2b868e163da71de14a5113cc2743fc9b5ad7488334720ed2846566a8f6,
                isCorrelated: false
            });
            // cbBTC/EURCV
            marketConfigs[42] = MarketConfig({
                marketId: 0x82053fe2fc3a3d6cb856458948e9c3589e76f20f3a2079606739b517587267ce,
                isCorrelated: false
            });
            // WBTC/EURCV
            marketConfigs[43] = MarketConfig({
                marketId: 0xb7a75cabc2e8eadd0bc661340a9e359d9828bed6d5cbbcd64188bca8c01e399e,
                isCorrelated: false
            });
            // wstETH/RLUSD
            marketConfigs[44] = MarketConfig({
                marketId: 0x88abdf8693e663144c3544b9442e9b04520016d6ebc57aa76424c00ab1683c9d,
                isCorrelated: false
            });
            // weETH/USDC
            marketConfigs[45] = MarketConfig({
                marketId: 0x61765602144e91e5ac9f9e98b8584eae308f9951596fd7f5e0f59f21cd2bf664,
                isCorrelated: false
            });

            // ============ New Correlated Markets ============

            // wstETH/WETH (2nd market)
            marketConfigs[46] = MarketConfig({
                marketId: 0xd0e50cdac92fe2172043f5e0c36532c6369d24947e40968f34a5e8819ca9ec5d,
                isCorrelated: true
            });
            // msY/USDC
            marketConfigs[47] = MarketConfig({
                marketId: 0x23a7d0ff682b323363fb8ba58327ed87001f6306e09b7fd7413bbe4698e749c8,
                isCorrelated: true
            });
            // apyUSD/USDC
            marketConfigs[48] = MarketConfig({
                marketId: 0x9c28c8fa039a8df548a7f27adf062d751b0f2e9b9131931810535543adb23291,
                isCorrelated: true
            });
            // apxUSD/apyUSD
            marketConfigs[49] = MarketConfig({
                marketId: 0xe23380494e365453f72f736f2d941959ae945773eb67a06cf4f538c7c4201264,
                isCorrelated: true
            });
            // reUSD/USDC
            marketConfigs[50] = MarketConfig({
                marketId: 0x4565ac05d38b19374ccbb04c17cca60ca9353cd41824f0803d0fc7704f60eaed,
                isCorrelated: true
            });
            // muBOND/USDC
            marketConfigs[51] = MarketConfig({
                marketId: 0x6cf7e63f37d7f2ca2b86d1415eeedd4173b30f9974e8a706016e1f798b479b03,
                isCorrelated: true
            });
            // PRIME/PYUSD
            marketConfigs[52] = MarketConfig({
                marketId: 0x41c41d0c9aadbf4751f5ee215ed5a16954a4b34e1b70fca5393d4b08858fa3fa,
                isCorrelated: true
            });
            // stUSDS/USDS
            marketConfigs[53] = MarketConfig({
                marketId: 0x77e624dd9dd980810c2b804249e88f3598d9c7ec91f16aa5fbf6e3fdf6087f82,
                isCorrelated: true
            });
            // USP/USDC
            marketConfigs[54] = MarketConfig({
                marketId: 0x5d41b8d23ccf6d9e9f7e2b1b357d92bba6ef0367d6ef8ceda965f73e52108461,
                isCorrelated: true
            });
            // syrupUSDT/USDT
            marketConfigs[55] = MarketConfig({
                marketId: 0xa4774e3e693fff2ebd1dcbbd69b1b0a5b9bb0ccc753bfda5dd07bdac97c4818a,
                isCorrelated: true
            });
            // upUSDC/USDC
            marketConfigs[56] = MarketConfig({
                marketId: 0xa0c6499787a7d046f91f2687558c021e2baae5a378885280a448183a926ef5f7,
                isCorrelated: true
            });
            // EUTBL/EURCV
            marketConfigs[57] = MarketConfig({
                marketId: 0xaa7231d6bee28b578efe38b52e801d5d3067023853342fc06ded437d2a80ef98,
                isCorrelated: true
            });
            // stUSDS/USDT
            marketConfigs[58] = MarketConfig({
                marketId: 0x710f02caee4555b8ff75b7d48e5b52adc48898dc0c670b977fb1ea83bf4e7d8a,
                isCorrelated: true
            });
            // rETH/WETH
            marketConfigs[59] = MarketConfig({
                marketId: 0x251b7cbc2c33ba4eabe3b7163ad0fdd3cfb97de80d8377f0f48b8d31aee7606f,
                isCorrelated: true
            });
            // sNUSD/USDC
            marketConfigs[60] = MarketConfig({
                marketId: 0xae60b71b407e0517ead445b7113a7ffa07ea4a9379d526ade541a3e9ec777cb4,
                isCorrelated: true
            });

            // ============ New Pendle PT Markets (Correlated) ============

            // PT-USDat-27AUG2026/AUSD
            marketConfigs[61] = MarketConfig({
                marketId: 0x9464b3d42133c10c8b216d3d9429b43e98c2f3856a87940ef18b8bdd3e7bd831,
                isCorrelated: true
            });

            // ============ New Non-Correlated Markets ============

            // cbBTC/PYUSD
            marketConfigs[62] = MarketConfig({
                marketId: 0xd8a8e6667f58aa9229e8979bd619742b1660ee856c200a93e407dbccb7222323,
                isCorrelated: false
            });
            // cbBTC/USDT (2nd market)
            marketConfigs[63] = MarketConfig({
                marketId: 0x4fe72543c5c95cd6b5f3cb516cd235ba882e2e705fe3424db6f99dfe5811d0d3,
                isCorrelated: false
            });
            // wstETH/USDC (3rd market)
            marketConfigs[64] = MarketConfig({
                marketId: 0x7e585a933ffe8443c371b4f8cfeb4430f5f6a14c2f32a898c26662c67a1cb8b8,
                isCorrelated: false
            });
            // kBTC/RLUSD
            marketConfigs[65] = MarketConfig({
                marketId: 0x15bb2a6af0c909eed19fb1f2ceeead34ecbdcba626de752c6b09389ee14eec32,
                isCorrelated: false
            });
            // XAUt/USDT
            marketConfigs[66] = MarketConfig({
                marketId: 0xb7843fe78e7e7fd3106a1b939645367967d1f986c2e45edb8932ad1896450877,
                isCorrelated: false
            });
            // wstETH/PYUSD
            marketConfigs[67] = MarketConfig({
                marketId: 0xf5c5df23559b0fb56560a7578ea17d81e245153ba64b8132df026c9358864d27,
                isCorrelated: false
            });

            // ============ New Correlated Markets - 2026-05-27 ============

            // srRoyUSDC/USDC
            marketConfigs[68] = MarketConfig({
                marketId: 0xacc49fbf58feb1ac971acce68f8adc177c43682d6a7087bbd4991a05cb7a2c67,
                isCorrelated: true
            });
            // sDOLA/frxUSD
            marketConfigs[69] = MarketConfig({
                marketId: 0x4affe8d17d001e243cac3b414ab52112b1574103ef550d410e16c7815ae44580,
                isCorrelated: true
            });
            // sUSDe/DAI
            marketConfigs[70] = MarketConfig({
                marketId: 0x39d11026eae1c6ec02aa4c0910778664089cdd97c3fd23f68f7cd05e2e95af48,
                isCorrelated: true
            });
            // fxSAVE/USDC
            marketConfigs[71] = MarketConfig({
                marketId: 0x43e925e52d7873fa8acac90dd5f246087d55b3a34c344b71884a6352491ff459,
                isCorrelated: true
            });

            // ============ New PT Markets - 2026-05-27 ============

            // PT-USDat-27AUG2026/USDC
            marketConfigs[72] = MarketConfig({
                marketId: 0x69ef7fd17b42cd7df6d885aee1b11380837afbc1664b25587041cf193b31617b,
                isCorrelated: true
            });
            // PT-srUSDat-27AUG2026/USDC
            marketConfigs[73] = MarketConfig({
                marketId: 0x42c2b592fc759fad461fb5c80d5ea214a496f70d8594398d69af68c2f3798de6,
                isCorrelated: true
            });
            // PT-stcUSD-23JUL2026/USDC
            marketConfigs[74] = MarketConfig({
                marketId: 0x2fb3713487c7812e7309935b034f40228841666f6b048faf31fd2110ae674f20,
                isCorrelated: true
            });
            // PT-cUSD-23JUL2026/USDT
            marketConfigs[75] = MarketConfig({
                marketId: 0xfd039edc69eac5eaab4a10463fdbcaca75d6eddb1f0e00248d73fc977fb2554b,
                isCorrelated: true
            });

            // ============ New Correlated Markets - 2026-06-08 ============

            // PRIME/USDC
            marketConfigs[76] = MarketConfig({
                marketId: 0x755f954513d31d5f24aaf3d0cdc5e913a28383f8ea8ff85be9ffffa7371fb64d,
                isCorrelated: true
            });

            // ============ New Correlated Markets - 2026-06-14 ============

            // USD3/USDC
            marketConfigs[77] = MarketConfig({
                marketId: 0xe3df58f9d3011b7481ff36b939fa5f8da642f34ea5792d25d3958dbf1efa26d7,
                isCorrelated: true
            });
            // sDOLA/USDC
            marketConfigs[78] = MarketConfig({
                marketId: 0x9972be1fc530a3f5a34db25ee8ab4962cc4099cb65b2db22897c92cc9d22f59f,
                isCorrelated: true
            });

            // ============ New PT Markets - 2026-06-14 ============

            // PT-USD3-17DEC2026/USDC
            marketConfigs[79] = MarketConfig({
                marketId: 0xf8c5aa31ea6b2a068a9eddb46dd110cae57bf0f12be9583a3f9a818effecba89,
                isCorrelated: true
            });
            // PT-apxUSD-5NOV2026/USDC
            marketConfigs[80] = MarketConfig({
                marketId: 0x908b037029b5c0671ba3b362eaf289c3199560d1d4632e6cb527cc7240fa006e,
                isCorrelated: true
            });
            // PT-apyUSD-5NOV2026/USDC
            marketConfigs[81] = MarketConfig({
                marketId: 0xb37c30f34bff11c81ee8400133965f450a5f7c5d81ba2cf5740076f49eabc95c,
                isCorrelated: true
            });
            // PT-sUSDD-27AUG2026/USDC
            marketConfigs[82] = MarketConfig({
                marketId: 0xf02d2e8f427a2b91785b3d09690ef9d3811bf674ba97b00bafc7665004a6dd97,
                isCorrelated: true
            });
            // PT-stcUSD-23JUL2026/USDT
            marketConfigs[83] = MarketConfig({
                marketId: 0x5eaaebc81e9e27972ab458811d1b60828e8ab51ef6620f9b3918fd7e68eecec1,
                isCorrelated: true
            });
        }
    }
}
