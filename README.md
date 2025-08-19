# Odyssey SUI Packages

This project contains the SUI Move version of existing Solidity Odyssey contracts. The system enables prediction market trading with deposits, withdrawals, and automated settlement.

## 🏗️ **Architecture Overview**

### **Core Modules:**

- **`types.move`** - Shared data structures and enums
- **`vault.move`** - Asset management and balance tracking
- **`order.move`** - Trading note creation and settlement
- **`maker_vault.move`** - Maker vault for managing maker balances

## 🚀 **Quick Start**

### **1. Build the Project**

```bash
sui move build
```

### **2. Run Tests**

```bash
sui move test
```

### **3. Environment Setup**

Create a `.env` file in the root directory with the following variables:

```bash
PRIVATE_KEY=your_private_key_here
NETWORK=testnet|mainnet
```

**Example:**
```bash
PRIVATE_KEY=0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
NETWORK=testnet
```

> **⚠️ Security Note:** Never commit your `.env` file to version control.

## 🚀 **Deployment**

### **Deploy to Testnet/Mainnet**

The deployment consists of 2 steps:
1. **Packages deployment** - Deploy the Move contracts
2. **System initialization** - Set up the initial system state

> **Note:** You can skip the first step and initialize the system using existing deployed packages by setting `PUBLISH_NEW_PACKAGE` to `false` in the `deploy.ts` script.

```bash
pnpm run deploy 
```

### **Deploy ITHACA Token (Optional)**

To initialize the system, you need two token types:
- **USDC token type** (existing on testnet)
- **ITHACA token type** (custom token for this project)

This repository includes a pre-configured ITHACA token deployment. If you want to deploy a new ITHACA token:

```bash
cd packages/ithaca_token
pnpm run deploy
```

> **Note:** The `.env` file with `PRIVATE_KEY` and `NETWORK` is also required for ITHACA token deployment.

#### **Mint ITHACA Tokens**

To mint ITHACA tokens to a specific address:

```bash
pnpm run mint -a <ADDRESS> -n <AMOUNT>
```

**Example:**
```bash
pnpm run mint -a 0x1234567890abcdef -n 1000
```

> **Note:** The `.env` file with `PRIVATE_KEY` and `NETWORK` is required for minting operations.

## 📁 **Project Structure**

```
odyssey-sui/
├── sources/                 # Move contract source files
│   ├── types.move          # Shared data structures
│   ├── vault.move          # Asset management
│   ├── order.move          # Trading functionality
│   └── maker_vault.move    # Maker vault management
├── packages/
│   └── ithaca_token/       # ITHACA token implementation
├── scripts/
│   └── deploy.ts           # Deployment script
└── tests/                  # Test files
```

## 🔧 **Development**

### **Prerequisites**

- [Sui CLI](https://docs.sui.io/build/install)
- [Node.js](https://nodejs.org/) (v16 or higher)
- [pnpm](https://pnpm.io/) package manager

### **Install Dependencies**

```bash
pnpm install
```

### **Run All Tests**

```bash
pnpm test
```

## 📚 **Documentation**

For detailed information about the Move contracts and their functionality, refer to the inline documentation in the source files:

- `sources/types.move` - Data structure definitions
- `sources/vault.move` - Vault operations and balance management
- `sources/order.move` - Order creation and settlement logic
- `sources/maker_vault.move` - Maker vault operations

## 🤝 **Contributing**

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## 📄 **License**

This project is licensed under the MIT License.
