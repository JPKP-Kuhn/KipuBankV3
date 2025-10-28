// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/KipuBankV3.sol";

contract DeployKipuBankV3 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Example addresses - replace with actual addresses for your target network
        address ethUsdOracle = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // ETH/USD Chainlink Oracle (Mainnet)
        address universalRouter = 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD; // UniversalRouter (Mainnet)
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Permit2 (Mainnet)
        address usdc = 0xa0B86a33e6441b8C4c8c0E4A8e4A8e4A8e4a8e4a; // USDC (Mainnet) - Replace with actual USDC address
        address poolManager = 0x0000000000000000000000000000000000000000; // V4 PoolManager - Replace with actual address

        console.log("Deploying KipuBankV3...");
        console.log("Bank Cap: 1000 ETH");
        console.log("ETH/USD Oracle:", ethUsdOracle);
        console.log("UniversalRouter:", universalRouter);
        console.log("Permit2:", permit2);
        console.log("USDC:", usdc);
        console.log("PoolManager:", poolManager);

        KipuBankV3 bank = new KipuBankV3(
            1000 ether,  // 1000 ETH bank cap
            IChainLink(ethUsdOracle),
            IUniversalRouter(universalRouter),
            IPermit2(permit2),
            usdc,
            poolManager
        );

        console.log("KipuBankV3 deployed at:", address(bank));

        vm.stopBroadcast();
    }
}

