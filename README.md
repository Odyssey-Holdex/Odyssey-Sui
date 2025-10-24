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
# Make sure you are inside packages/ithaca_token folder
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

### **Test Coverage**

```bash
sui move test --coverage
sui move coverage summary
```

#### **Current Coverage Statistics**

The codebase maintains **89.08% overall test coverage** with 93 comprehensive unit tests:

| Module | Coverage | Status |
|--------|----------|--------|
| `types.move` | 100.00% | ✅ Full Coverage |
| `order.move` | 92.22% | ✅ Excellent |
| `maker_vault.move` | 82.81% | ⚠️ Good |
| `vault.move` | 81.55% | ⚠️ Good |

**Total: 93 tests, all passing**

#### **Why Not 90%+?**

The test suite does not reach 90% coverage due to **`migrate()` functions** present in all three main modules (vault, maker_vault, and order). These functions are designed for contract upgrades in production and cannot be meaningfully tested in a unit test environment:

- **Purpose**: Enable seamless contract upgrades without data loss
- **Invocation**: Only called during production upgrade scenarios
- **Testing**: Cannot be tested in isolated unit test environments
- **Impact**: 84 lines (28 per module × 3) with 0% coverage

**Adjusted Coverage (excluding migrate functions):**
- Total lines: 2,507 (excluding 84 migrate lines)
- Covered lines: 2,308
- **Effective coverage: 92.07%** ✅

#### **Test Coverage Breakdown**

Our test suite includes:

- **Core functionality tests**: Deposit, withdraw, registration, unregistration
- **Order lifecycle tests**: Note creation, settlement (WIN/LOSS/REFUND/ALMOST_WIN), fee calculations
- **Edge case tests**: Zero amounts, invalid addresses, insufficient balances, locked funds
- **Integration tests**: Multi-party interactions, settlement with fees, balance tracking
- **View function tests**: Balance queries, status checks, getter functions
- **Security tests**: Permission checks, validation logic, capability patterns

All critical business logic and user-facing functionality is thoroughly tested. The uncovered code consists primarily of:
- Migration functions (upgrade mechanism)
- Internal helper functions with edge cases (70-80% covered)
- Low-level transfer operations (called during settlement, partially covered)

## Security Audits
   
   - [Audit Report by Hashlock](https://odyssey.ithacaprotocol.io/odyssey-sui-audit.pdf) - September 2025
     - Audited commit: `9cd89fda4b92a3d06fff8cb34f965bcf1f73dd5c`
     - Status: All issues resolved


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
