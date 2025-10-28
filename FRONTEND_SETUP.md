# Scaffold-ETH 2 Integration Guide for KipuBankV4

## Overview

This guide explains how to set up Scaffold-ETH 2 to build a frontend UI for your KipuBankV4 Foundry project.

## Architecture

Your project structure will look like this:
```
KipuBankV3/
├── src/                    # Foundry contracts
├── test/                   # Foundry tests
├── script/                 # Foundry scripts
├── frontend/               # Scaffold-ETH 2 frontend (new)
│   ├── packages/
│   │   ├── nextjs/        # Next.js app
│   │   └── contracts/     # Contract ABIs
└── ...
```

## Setup Steps

### 1. Install Scaffold-ETH 2

```bash
# From your project root
git clone https://github.com/scaffold-eth/scaffold-eth-2.git frontend-temp
cd frontend-temp
yarn install

# Copy the packages structure
cp -r packages ../frontend
cd .. && rm -rf frontend-temp
cd frontend
```

### 2. Configure Scaffold-ETH 2 to Use Foundry

#### Update `foundry.toml` in project root:
```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
# Add this line to output ABIs to frontend
abi = true
```

#### Create `.env.local` in frontend:
```bash
cp .env.example .env.local
```

Update with your contract addresses after deployment.

### 3. Import Your Contract ABI

The ABI will be automatically available in `out/KipuBank.sol/KipuBank.json` after running `forge build`.

Copy your contract ABI to the frontend:
```bash
# Create contracts config
mkdir -p packages/contracts/src/abis
cp ../out/KipuBank.sol/KipuBank.json packages/contracts/src/abis/
```

### 4. Create Contract Configuration

Update `packages/contracts/src/deployments.ts` to include your contract address.

### 5. Build Frontend Components

Create UI components for:
- Deposit ETH
- Deposit ERC-20 tokens
- Deposit arbitrary tokens (with swap)
- Withdraw ETH
- Withdraw tokens
- View balances
- View bank cap and limits

## Quick Start Alternative (Recommended)

Instead of cloning the full Scaffold-ETH repo, you can create a minimal Next.js + wagmi setup:

```bash
# Create Next.js app with TypeScript
npx create-next-app@latest frontend --typescript --tailwind --app

# Install wagmi and viem
cd frontend
npm install wagmi viem @tanstack/react-query
```

This is lighter and easier to customize for your specific needs.

## Recommended Approach

For your Foundry project, I recommend a **minimal Next.js + wagmi setup** because:

1. ✅ Lighter weight - only what you need
2. ✅ Full control over the UI
3. ✅ Easy to integrate with Foundry ABIs
4. ✅ Modern React patterns (hooks, TypeScript)
5. ✅ Tailwind CSS for styling

Would you like me to:
1. Set up a minimal Next.js frontend?
2. Create React hooks for your contract functions?
3. Build UI components for deposits/withdrawals?

## Key Integration Points

### Reading Contract ABIs
```typescript
import KipuBankABI from "../abis/KipuBank.json";
```

### Contract Interaction (wagmi)
```typescript
import { useContractWrite, useContractRead } from 'wagmi';

const { write: depositETH } = useContractWrite({
  address: KIPU_BANK_ADDRESS,
  abi: KipuBankABI,
  functionName: 'deposit',
  value: parseEther('1'),
});
```

### Reading Balances
```typescript
const { data: balance } = useContractRead({
  address: KIPU_BANK_ADDRESS,
  abi: KipuBankABI,
  functionName: 'getAccountBalance',
  args: [],
});
```

## Environment Variables

Create `frontend/.env.local`:
```
NEXT_PUBLIC_CHAIN_ID=11155111  # Sepolia
NEXT_PUBLIC_KIPU_BANK_ADDRESS=0x...
NEXT_PUBLIC_UNIVERSAL_ROUTER=0x...
NEXT_PUBLIC_USDC_ADDRESS=0x...
```

## Next Steps

1. **Choose approach**: Full Scaffold-ETH 2 or minimal Next.js setup
2. **Set up frontend structure**
3. **Create hooks for contract interactions**
4. **Build UI components**
5. **Connect to wallet (MetaMask)**

Let me know which approach you prefer and I'll set it up!

