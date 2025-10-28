# KipuBankV3 - Advanced Multi-Token Bank with Uniswap V3 Integration

## Overview

KipuBankV3 is an advanced decentralized finance (DeFi) banking contract that extends the functionality of previous KipuBank versions by integrating with Uniswap V3. This contract allows users to deposit any ERC-20 token supported by Uniswap V3, automatically converting it to USDC while maintaining all the core banking features.

## Key Features

### 🏦 Core Banking Features (Preserved from V2/V3)
- **Multi-token Support**: ETH, USDC, and any ERC-20 token with Chainlink price feeds
- **Bank Cap Management**: Global limit on total deposits with real-time enforcement
- **Withdrawal Limits**: Per-transaction limits based on USD value ($1000)
- **Price Oracle Integration**: Chainlink price feeds for accurate USD conversions
- **Admin Controls**: Role-based access control for token management and emergency functions
- **Reentrancy Protection**: Comprehensive security measures

### 🚀 New V3 Features
- **Arbitrary Token Deposits**: Deposit any ERC-20 token supported by Uniswap V3
- **Automatic Token Swapping**: Seamless conversion of deposited tokens to USDC
- **Uniswap V3 Integration**: Direct integration with UniversalRouter
- **Gas-Efficient Swaps**: Optimized swap execution using Uniswap V3 pools
- **Bank Cap Compliance**: Swaps respect the bank cap limit even after conversion

## Architecture

### Contract Structure
```
KipuBankV3
├── AccessControl (OpenZeppelin)
├── InternalHelperKipuBank (Base functionality)
├── Uniswap V3 Integration
│   ├── UniversalRouter
│   ├── IPermit2
│   ├── PoolKey & Currency types (for future V4 compatibility)
│   └── Swap execution logic
└── Enhanced token management
```

### Key Components

1. **UniversalRouter Integration**
   - Handles complex swap operations
   - Supports multiple DEX protocols
   - Gas-optimized execution

2. **Permit2 Support**
   - Efficient token approvals
   - Batch operations support
   - Enhanced security

3. **Bank Cap Enforcement**
   - Real-time cap checking
   - Pre-swap validation
   - ETH equivalent calculations

## Installation & Setup

### Prerequisites
- Foundry (latest version)
- Node.js (for testing)
- Git

### Installation Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/JPKP-Kuhn/KipuBankV3.git
   cd KipuBankV3
   ```

2. **Install dependencies**
   ```bash
   forge install
   ```

3. **Build the project**
   ```bash
   forge build
   ```

4. **Run tests**
   ```bash
   forge test
   ```

## Deployment Instructions

### Required Parameters

The contract constructor requires the following parameters:

```solidity
constructor(
    uint256 _bankcap,           // Bank capacity in ETH
    IChainLink _oracle,         // ETH/USD Chainlink oracle
    IUniversalRouter _universalRouter,  // UniversalRouter address
    IPermit2 _permit2,          // Permit2 contract address
    address _usdc,              // USDC token address
    address _poolManager        // Uniswap V4 PoolManager address
)
```

### Deployment Script Example

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/KipuBankV3.sol";

contract DeployKipuBankV3 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Mainnet addresses (example)
        address ethUsdOracle = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        address universalRouter = 0x3FC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD;
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        address usdc = 0xA0b86a33E6441b8c4C8C0e4A8e4A8e4A8e4A8e4A;
        address poolManager = 0x0000000000000000000000000000000000000000; // V4 PoolManager

        KipuBankV3 bank = new KipuBankV3(
            1000 ether,  // 1000 ETH bank cap
            IChainLink(ethUsdOracle),
            IUniversalRouter(universalRouter),
            IPermit2(permit2),
            usdc,
            poolManager
        );

        vm.stopBroadcast();
    }
}
```

### Deployment Commands

```bash
# Deploy to local network
forge script script/DeployKipuBankV3.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/DeployKipuBankV3.s.sol --rpc-url $TESTNET_RPC_URL --broadcast --verify

# Deploy to mainnet
forge script script/DeployKipuBankV3.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

## Usage Guide

### Basic Operations

#### 1. Deposit ETH
```solidity
// Deposit 1 ETH
bank.deposit{value: 1 ether}();
```

#### 2. Deposit USDC Directly
```solidity
// Deposit 100 USDC
IERC20(usdc).approve(address(bank), 100 * 1e6);
bank.depositToken(usdc, 100 * 1e6);
```

#### 3. Deposit Arbitrary Token (New V3 Feature)
```solidity
// Deposit any ERC-20 token and swap to USDC
IERC20(token).approve(address(bank), amount);
bank.depositArbitraryToken(
    token,           // Token to deposit
    amount,          // Amount to deposit
    minUsdcOut,      // Minimum USDC expected
    deadline         // Swap deadline
);
```

#### 4. Withdraw Funds
```solidity
// Withdraw ETH
bank.withdraw(amount);

// Withdraw USDC
bank.withdrawToken(usdc, amount);
```

### Admin Functions

#### Add New Token Support
```solidity
// Only TOKEN_MANAGER_ROLE can execute
bank.addToken(tokenAddress, chainlinkOracle);
```

#### Emergency Recovery
```solidity
// Only ADMIN_ROLE can execute
bank.adminRecoverBalance(user, newBalance);
bank.adminWithdrawFunds(token, recipient, amount);
```

## Security Features

### 1. Reentrancy Protection
- Custom reentrancy guard implementation
- CEI (Checks-Effects-Interactions) pattern
- SafeERC20 for token operations

### 2. Access Control
- Role-based permissions (ADMIN_ROLE, TOKEN_MANAGER_ROLE)
- Multi-signature support capability
- Emergency pause functionality

### 3. Oracle Security
- Staleness checks (1-hour maximum)
- Price validation (positive values only)
- Multiple oracle support

### 4. Bank Cap Enforcement
- Real-time cap checking
- Pre-transaction validation
- ETH equivalent calculations

## Gas Optimization

### 1. Efficient Storage Layout
- Packed structs where possible
- Minimal storage operations
- Optimized mappings

### 2. Batch Operations
- Permit2 integration for batch approvals
- UniversalRouter for complex operations
- Reduced external calls

### 3. Compiler Optimizations
- Solidity 0.8.26 with optimizer enabled
- Via-IR compilation
- 200 optimizer runs

## Testing

### Test Structure
```
test/
├── KipuBankV3.t.sol          # Main contract tests
├── Integration.t.sol         # Uniswap V4 integration tests
├── Security.t.sol            # Security and edge case tests
└── Gas.t.sol                 # Gas usage tests
```

### Running Tests
```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/KipuBankV3.t.sol

# Run with gas reporting
forge test --gas-report

# Run with coverage
forge coverage
```

## Important Design Decisions

### 1. USDC as Base Currency
- **Decision**: All arbitrary tokens are converted to USDC
- **Rationale**: USDC is the most liquid stablecoin with reliable price feeds
- **Trade-off**: Limits flexibility but ensures stability

### 2. UniversalRouter Integration
- **Decision**: Use UniversalRouter instead of direct PoolManager calls
- **Rationale**: Better gas efficiency and protocol abstraction
- **Trade-off**: Additional dependency but better maintainability

### 3. Bank Cap in ETH Equivalent
- **Decision**: Maintain bank cap in ETH equivalent for all tokens
- **Rationale**: Consistent with original design and easier to understand
- **Trade-off**: Requires price oracle dependency

### 4. Fixed Fee Tier (0.3%)
- **Decision**: Use 0.3% fee tier for all swaps
- **Rationale**: Most liquid pools typically use this fee tier
- **Trade-off**: May not be optimal for all token pairs

## Known Limitations

1. **Oracle Dependency**: Requires reliable Chainlink price feeds
2. **Liquidity Requirements**: Swaps depend on Uniswap V4 liquidity
3. **Gas Costs**: Complex operations may have higher gas costs
4. **Slippage**: Large swaps may experience significant slippage

## Future Enhancements

1. **Dynamic Fee Selection**: Choose optimal fee tier based on token pair
2. **Multi-hop Swaps**: Support for complex routing paths
3. **MEV Protection**: Integration with MEV protection services
4. **Cross-chain Support**: Multi-chain deployment capabilities

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For questions and support:
- Create an issue on GitHub
- Contact the development team
- Check the documentation wiki

## Changelog

### V3.0.0
- Added Uniswap V3 integration via UniversalRouter
- Implemented arbitrary token deposits
- Enhanced swap functionality
- Improved gas efficiency
- Updated to Solidity 0.8.26

### V3.x.x
- Multi-token support
- Chainlink oracle integration
- Admin controls
- Security enhancements

### V2.x.x
- Basic ETH banking functionality
- Withdrawal limits
- Bank cap management
