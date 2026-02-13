// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";

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
        }
    }

    function getCollateralTokens()
        internal
        view
        returns (CollateralTokenConfig[] memory tokenConfigs)
    {
        if (block.chainid == 31337 || block.chainid == 1) {
            tokenConfigs = new CollateralTokenConfig[](41);

            // ETH Tokens
            tokenConfigs[0] = CollateralTokenConfig({
                collateralToken: 0x2d3C279E5FcDF5b793c0a75ed90738D7369B0b83,
                morphoMarketId: 0x2fb3713487c7812e7309935b034f40228841666f6b048faf31fd2110ae674f20,
                isCorrelated: true
            });

            tokenConfigs[32] = CollateralTokenConfig({
                collateralToken: 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee,
                morphoMarketId: 0x37e7484d642d90f14451f1910ba4b7b8e4c3ccdd0ec28f8b2bdb35479e472ba7,
                isCorrelated: true
            });

            tokenConfigs[1] = CollateralTokenConfig({
                collateralToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                morphoMarketId: 0xb8fc70e82bc5bb53e773626fcc6a23f7eefa036918d7ef216ecfb1950a94a85e,
                isCorrelated: true
            });

            // Staked Stables
            tokenConfigs[2] = CollateralTokenConfig({
                collateralToken: 0xDBDC1Ef57537E34680B898E1FEBD3D68c7389bCB,
                morphoMarketId: 0xbbf7ce1b40d32d3e3048f5cf27eeaa6de8cb27b80194690aab191a63381d8c99,
                isCorrelated: true
            });

            tokenConfigs[3] = CollateralTokenConfig({
                collateralToken: 0x4956b52aE2fF65D74CA2d61207523288e4528f96,
                morphoMarketId: 0xe1b65304edd8ceaea9b629df4c3c926a37d1216e27900505c04f14b2ed279f33,
                isCorrelated: true
            });

            tokenConfigs[4] = CollateralTokenConfig({
                collateralToken: 0x88887bE419578051FF9F4eb6C858A951921D8888,
                morphoMarketId: 0xeb17955ea422baeddbfb0b8d8c9086c5be7a9cfdefb292119a102e981a30062e,
                isCorrelated: true
            });

            tokenConfigs[5] = CollateralTokenConfig({
                collateralToken: 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD,
                morphoMarketId: 0x3274643db77a064abd3bc851de77556a4ad2e2f502f4f0c80845fa8f909ecf0b,
                isCorrelated: true
            });

            tokenConfigs[6] = CollateralTokenConfig({
                collateralToken: 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497,
                morphoMarketId: 0x90ef0c5a0dc7c4de4ad4585002d44e9d411d212d2f6258e94948beecf8b4c0d5,
                isCorrelated: true
            });

            tokenConfigs[7] = CollateralTokenConfig({
                collateralToken: 0xC5d6A7B61d18AfA11435a889557b068BB9f29930,
                morphoMarketId: 0x29ae8cad946d861464d5e829877245a863a18157c0cde2c3524434dafa34e476,
                isCorrelated: true
            });

            tokenConfigs[8] = CollateralTokenConfig({
                collateralToken: 0x356B8d89c1e1239Cbbb9dE4815c39A1474d5BA7D,
                morphoMarketId: 0xa4774e3e693fff2ebd1dcbbd69b1b0a5b9bb0ccc753bfda5dd07bdac97c4818a,
                isCorrelated: true
            });

            tokenConfigs[9] = CollateralTokenConfig({
                collateralToken: 0xd3fD63209FA2D55B07A0f6db36C2f43900be3094,
                morphoMarketId: 0x1590cb22d797e226df92ebc6e0153427e207299916e7e4e53461389ad68272fb,
                isCorrelated: true
            });

            tokenConfigs[10] = CollateralTokenConfig({
                collateralToken: 0x99CD4Ec3f88A45940936F469E4bB72A2A701EEB9,
                morphoMarketId: 0x77e624dd9dd980810c2b804249e88f3598d9c7ec91f16aa5fbf6e3fdf6087f82,
                isCorrelated: true
            });

            tokenConfigs[11] = CollateralTokenConfig({
                collateralToken: 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b,
                morphoMarketId: 0xc9629945524f3fde56c7e8854a6c3d48e76b9d97236abbe73c750fcc7aeb8501,
                isCorrelated: true
            });

            tokenConfigs[12] = CollateralTokenConfig({
                collateralToken: 0xd3fD63209FA2D55B07A0f6db36C2f43900be3094,
                morphoMarketId: 0xa9f70093360419b4544f17a4553ac5847d896be23f020295bd95c24af4df700e,
                isCorrelated: true
            });

            tokenConfigs[13] = CollateralTokenConfig({
                collateralToken: 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497,
                morphoMarketId: 0x88a18b2f4d94e7ad27a381b15531c06abf05a7c99dd5d3c3679875fed6f7e742,
                isCorrelated: true
            });

            tokenConfigs[14] = CollateralTokenConfig({
                collateralToken: 0xd3fD63209FA2D55B07A0f6db36C2f43900be3094,
                morphoMarketId: 0x32e253d33f1594a67fc6ef51bf7a39cc4bf2d14904998dee769706fcde489ed9,
                isCorrelated: true
            });

            tokenConfigs[15] = CollateralTokenConfig({
                collateralToken: 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD,
                morphoMarketId: 0xa5beccdffd156dfe8c0871f143648c512f0a34f37c8a4ae2ff31ebfe944641d1,
                isCorrelated: true
            });

            tokenConfigs[16] = CollateralTokenConfig({
                collateralToken: 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497,
                morphoMarketId: 0xc9098061d437a9dd53b0070cb33df6fca1a0a5ead288588c88699b0420c1c078,
                isCorrelated: true
            });

            tokenConfigs[17] = CollateralTokenConfig({
                collateralToken: 0x5086bf358635B81D8C47C66d1C8b9E567Db70c72,
                morphoMarketId: 0x4565ac05d38b19374ccbb04c17cca60ca9353cd41824f0803d0fc7704f60eaed,
                isCorrelated: true
            });

            tokenConfigs[18] = CollateralTokenConfig({
                collateralToken: 0x6DFF69eb720986E98Bb3E8b26cb9E02Ec1a35D12,
                morphoMarketId: 0xf4e9fb49e95a34320aea8b5e0ef515391a72368c39bdcf8ad8910645fd6eab97,
                isCorrelated: true
            });

            tokenConfigs[19] = CollateralTokenConfig({
                collateralToken: 0x4956b52aE2fF65D74CA2d61207523288e4528f96,
                morphoMarketId: 0x4b86442549b52826e0fc11770ec5154450cb3c5c14dc751a761d81dcfbe7a7b2,
                isCorrelated: true
            });

            tokenConfigs[20] = CollateralTokenConfig({
                collateralToken: 0x08EFCC2F3e61185D0EA7F8830B3FEc9Bfa2EE313,
                morphoMarketId: 0xae60b71b407e0517ead445b7113a7ffa07ea4a9379d526ade541a3e9ec777cb4,
                isCorrelated: true
            });

            tokenConfigs[21] = CollateralTokenConfig({
                collateralToken: 0x6DFF69eb720986E98Bb3E8b26cb9E02Ec1a35D12,
                morphoMarketId: 0x9be0fb56b4d52d3632683b632514a2304f6fe1103e081acc358ded09e8e9a1e7,
                isCorrelated: true
            });

            tokenConfigs[22] = CollateralTokenConfig({
                collateralToken: 0x998D7b14c123c1982404562b68edDB057b0477cB,
                morphoMarketId: 0xe9d96a2f8042486bfd8cfd22692e49cd355e8a51da2f427bdb2d3671fbe978ea,
                isCorrelated: true
            });

            tokenConfigs[23] = CollateralTokenConfig({
                collateralToken: 0x7CF9DEC92ca9FD46f8d86e7798B72624Bc116C05,
                morphoMarketId: 0x031c7333014af51e4fd18031d14e4eaada58348cde3f6dc6ea8cca16f7387fb2,
                isCorrelated: true
            });

            tokenConfigs[24] = CollateralTokenConfig({
                collateralToken: 0xE24a3DC889621612422A64E6388927901608B91D,
                morphoMarketId: 0x8924445a76b678c536df977ed9222fb0b23ee5311497dd0223fe6270bb20b4e6,
                isCorrelated: true
            });

            tokenConfigs[25] = CollateralTokenConfig({
                collateralToken: 0x80E1048eDE66ec4c364b4F22C8768fc657FF6A42,
                morphoMarketId: 0xa0c6499787a7d046f91f2687558c021e2baae5a378885280a448183a926ef5f7,
                isCorrelated: true
            });

            tokenConfigs[26] = CollateralTokenConfig({
                collateralToken: 0xd3fD63209FA2D55B07A0f6db36C2f43900be3094,
                morphoMarketId: 0x08bd0186c5d6ee272f973a307815ac9a8f5ed42bc8308d4b109f254011776c34,
                isCorrelated: true
            });

            tokenConfigs[27] = CollateralTokenConfig({
                collateralToken: 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497,
                morphoMarketId: 0x39d11026eae1c6ec02aa4c0910778664089cdd97c3fd23f68f7cd05e2e95af48,
                isCorrelated: true
            });

            tokenConfigs[28] = CollateralTokenConfig({
                collateralToken: 0xb8D89678E75a973E74698c976716308abB8a46A4,
                morphoMarketId: 0xe07d416323a1afbfe0bf2fe27ffb549ff565cf5c86d21b79fc60664038e597c9,
                isCorrelated: true
            });

            tokenConfigs[29] = CollateralTokenConfig({
                collateralToken: 0xC58D044404d8B14e953C115E67823784dEA53d8F,
                morphoMarketId: 0x54cebd0c5d5ad84f551a883991c39c470e081a20452eaef47eec2377ffae9f98,
                isCorrelated: true
            });

            // PTs (Principal Tokens)
            tokenConfigs[30] = CollateralTokenConfig({
                collateralToken: 0xEC4402d1389E749C14A7caEef3e4c1f861e09Bc8,
                morphoMarketId: 0xb4b257c2b8001847d361a55fcd30a7bd630750bf492b85b37c4646e42e8e0d8c,
                isCorrelated: true
            });

            // PT-reUSD - Stablecoin PT from pendle (with 6 decimals)
            tokenConfigs[31] = CollateralTokenConfig({
                collateralToken: 0x3EAA0F0f0A5d3D595ae4e4b0D27f439d01c3E7b2,
                morphoMarketId: 0x9bc98c2f20ac58287ef2c860eea53a2fdc27c17a7817ff1206c0b7840cc7cd79,
                isCorrelated: true
            });

            tokenConfigs[32] = CollateralTokenConfig({
                collateralToken: 0x2d3C279E5FcDF5b793c0a75ed90738D7369B0b83,
                morphoMarketId: 0x2fb3713487c7812e7309935b034f40228841666f6b048faf31fd2110ae674f20,
                isCorrelated: true
            });

            tokenConfigs[33] = CollateralTokenConfig({
                collateralToken: 0x9Bf45ab47747F4B4dD09B3C2c73953484b4eB375,
                morphoMarketId: 0x27b9a0a5bfee98a31eb51e3850250d103a9f8e41673c782defc66aa943af0e65,
                isCorrelated: true
            });

            tokenConfigs[34] = CollateralTokenConfig({
                collateralToken: 0x29fD7180E5cCEd14Ad148c7997e6B6857a8BE86e,
                morphoMarketId: 0x1cfdc0154ae6b9f1887a8250f2582d55606e1a2008e65108fb83dd50a928593e,
                isCorrelated: true
            });

            tokenConfigs[35] = CollateralTokenConfig({
                collateralToken: 0x928FB6ED39100a92B2480f5cbB93453f98D9F4cE,
                morphoMarketId: 0x702b7ec7628de2622e51e1bb34a7e6ad9e95f3a25a2ed361e4ce621f23f5e642,
                isCorrelated: true
            });

            tokenConfigs[36] = CollateralTokenConfig({
                collateralToken: 0x64b393288AB2a0Fe7Af6b73A9159493E60aB0605,
                morphoMarketId: 0x3d353ef0436b85c3b12d53536c19b21c533c046b07c9d92d791a1510e7ef0b74,
                isCorrelated: true
            });

            tokenConfigs[37] = CollateralTokenConfig({
                collateralToken: 0xaF76B3AF3477E4a2cD0B7F80c3152108c19a25e5,
                morphoMarketId: 0xaac3ffcdf8a75919657e789fa72ab742a7bbfdf5bb0b87e4bbeb3c29bbbbb05c,
                isCorrelated: true
            });

            tokenConfigs[38] = CollateralTokenConfig({
                collateralToken: 0x9Bf45ab47747F4B4dD09B3C2c73953484b4eB375,
                morphoMarketId: 0xb2f87218f0e2478ba7a2b8be9fe76cbd6f54f8654b9651d4bd1f0ea536674691,
                isCorrelated: true
            });

            tokenConfigs[39] = CollateralTokenConfig({
                collateralToken: 0xd0609Ac13000d88B0BEbf5Bb21074916eDd92Bb1,
                morphoMarketId: 0x2afd063a5af8e050069cfad4da95c81768b85b140bea2bd89e00407b15ce82c8,
                isCorrelated: true
            });

            tokenConfigs[40] = CollateralTokenConfig({
                collateralToken: 0xD87169640666649F1E6F92034dcA9e4Ae748dE69,
                morphoMarketId: 0xca432a8b0f33541cfe164d388823d05b607db43b690d4856f343eec3b42402c0,
                isCorrelated: true
            });
        } else if (block.chainid == 137) {
            tokenConfigs = new CollateralTokenConfig[](2);
            // wstETH/WETH
            tokenConfigs[0] = CollateralTokenConfig({
                collateralToken: 0x03b54A6e9a984069379fae1a4fC4dBAE93B3bCCD,
                morphoMarketId: 0xb8ae474af3b91c8143303723618b31683b52e9c86566aa54c06f0bc27906bcae,
                isCorrelated: true
            });

            // MaticX/WPOL
            tokenConfigs[1] = CollateralTokenConfig({
                collateralToken: 0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6,
                morphoMarketId: 0xa932e0d8a9bf52d45b8feac2584c7738c12cf63ba6dff0e8f199e289fb5ca9bb,
                isCorrelated: true
            });
        } else if (block.chainid == 747474) {
            tokenConfigs = new CollateralTokenConfig[](3);
            // wsrUSD/vbUSDC - staked ETH
            tokenConfigs[0] = CollateralTokenConfig({
                collateralToken: 0x4809010926aec940b550D34a46A52739f996D75D,
                morphoMarketId: 0xd8a93a4cd16f843c385391e208a9a9f2fd75aedfcca05e4810e5fbfcaa6baec6,
                isCorrelated: true
            });

            // weeETH/vbETH - staked ETH
            tokenConfigs[1] = CollateralTokenConfig({
                collateralToken: 0x9893989433e7a383Cb313953e4c2365107dc19a7,
                morphoMarketId: 0x1e74d36ffbda65b8a45d72754b349cdd5ce807c5fa814f91ba8e3cd27881c34b,
                isCorrelated: true
            });

            // wstETH/ - staked ETH
            tokenConfigs[2] = CollateralTokenConfig({
                collateralToken: 0x7Fb4D0f51544F24F385a421Db6e7D4fC71Ad8e5C,
                morphoMarketId: 0x22f9f76056c10ee3496dea6fefeaf2f98198ef597eda6f480c148c6d3aaa70db,
                isCorrelated: true
            });
        } else if (block.chainid == 98866) {
            tokenConfigs = new CollateralTokenConfig[](4);

            // nALPHA / pUSD
            tokenConfigs[0] = CollateralTokenConfig({
                collateralToken: 0x593cCcA4c4bf58b7526a4C164cEEf4003C6388db,
                morphoMarketId: 0x7a96549cae736c913d12c78ee4c155c2d2f874031fce5acdd07bdbf23d7644c7,
                isCorrelated: true
            });

            // nBASIS / pUSD
            tokenConfigs[1] = CollateralTokenConfig({
                collateralToken: 0x11113Ff3a60C2450F4b22515cB760417259eE94B,
                morphoMarketId: 0x970b184db9382337bf6b693017cf30936a26001fb26bac24e238c77629a75046,
                isCorrelated: true
            });

            // nCREDIT / pUSD
            tokenConfigs[2] = CollateralTokenConfig({
                collateralToken: 0xA5f78B2A0Ab85429d2DfbF8B60abc70F4CeC066c,
                morphoMarketId: 0xa05b28928ab7aea096978928cfb3545333b30b36695bf1510922ac1d6a2c044a,
                isCorrelated: true
            });

            // nTBILL / pUSD
            tokenConfigs[3] = CollateralTokenConfig({
                collateralToken: 0xE72Fe64840F4EF80E3Ec73a1c749491b5c938CB9,
                morphoMarketId: 0xcf3bb7b9935f60d79da7b7bc6405328e6f990b6894895f1df7acfb4c82bc4c5a,
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
