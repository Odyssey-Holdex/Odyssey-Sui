# Trading Vault System - SUI Move Migration

This project contains the SUI Move migration of Solidity trading vault contracts. The system enables prediction market trading with deposits, withdrawals, and automated settlement.

## 🏗️ **Architecture Overview**

### **Core Modules:**

- **`types.move`** - Shared data structures and enums
- **`vault.move`** - Asset management and balance tracking
- **`order.move`** - Trading note creation and settlement
- **`example.move`** - Usage examples and integration helpers

### **Key Features:**

✅ **Multi-asset support** via generics (`Vault<T>`)  
✅ **Capability-based security** (no centralized owner)  
✅ **Automated settlement** with multiple outcome types  
✅ **Balance locking** for active trades  
✅ **Event emission** for transparency

## 🚀 **Quick Start**

### **1. Build the Project**

```bash
sui move build
```

### **2. Run Tests**

```bash
sui move test
```

### **3. Deploy to Devnet**

```bash
sui client publish --gas-budget 20000000
```

## 💻 **Usage Examples**

### **Initialize the System**

```move
use trading_vault::example;

// Initialize vault and order manager
let (vault_admin_cap, order_admin_cap, vault, order_manager) =
    example::initialize_trading_system(ctx);
```

### **Deposit Assets**

```move
// User deposits SUI tokens
let payment = coin::mint_for_testing<SUI>(1000, ctx);
example::example_deposit(&mut vault, payment, ctx);
```

### **Create Trading Note**

```move
// Create a BTC price prediction
let note_id = example::example_create_note(
    &mut order_manager,
    maker_address,
    100,        // bet amount
    50000,      // starting price ($500.00)
    Direction::UP,  // predict price will go up
    &clock,
    ctx
);
```

### **Settle Order**

```move
// Settle with final price after expiry
example::example_settle_note(
    &mut order_manager,
    note_id,
    52000,      // final price ($520.00)
    &clock,
    ctx
);
```

## 📊 **Data Structures**

### **TradableAsset**

```move
public struct TradableAsset {
    symbol: String,  // "BTC", "ETH", etc.
}
```

### **Trading Note**

```move
public struct Note {
    taker: address,          // Trader's address
    maker: address,          // Market maker's address
    asset: TradableAsset,    // Asset being traded
    direction: Direction,    // UP or DOWN
    amount: u64,             // Bet amount
    starting_price: u64,     // Price at creation
    spread: u64,             // Required price movement
    win_payout: u64,         // Payout if correct
    expiry_time: u64,        // Settlement deadline
    nonce: u64,              // Unique identifier
    refund_payout: u64,      // Payout if refunded
}
```

### **Outcome Types**

- **WIN** - Prediction correct, full payout
- **LOSS** - Prediction incorrect, no payout
- **REFUND** - Price moved but within refund zone
- **ALMOST_WIN** - Close to correct, partial payout

## 🔐 **Security Model**

### **Capabilities (vs Solidity's `onlyOwner`)**

| **Capability**  | **Permissions**                  | **Use Case**     |
| --------------- | -------------------------------- | ---------------- |
| `VaultAdminCap` | Configure vault settings         | Admin operations |
| `OrderCap`      | Adjust balances, transfer assets | Order settlement |

### **Access Control Flow**

```
VaultAdminCap → Configure vault settings
OrderCap → Called by order module for settlements
Public functions → Deposit/withdraw by users
```

## 🔄 **Migration Differences**

### **From Solidity to Move:**

| **Solidity**                  | **SUI Move**          | **Benefit**          |
| ----------------------------- | --------------------- | -------------------- |
| `mapping(address => uint256)` | `Table<address, u64>` | Dynamic storage      |
| `onlyOwner` modifier          | Capability system     | Granular permissions |
| `SafeERC20`                   | `Coin<T>` framework   | Type safety          |
| Interface contracts           | Native modules        | Direct calls         |
| Manual overflow checks        | Built-in safety       | Automatic protection |

### **Enhanced Features:**

- **Generic coin support** - Works with any `Coin<T>` type
- **Shared objects** - Multiple modules can interact safely
- **Rich event system** - Better monitoring capabilities
- **Object ownership** - Clear ownership semantics

## 🧪 **Testing**

### **Run All Tests**

```bash
sui move test
```

### **Test Coverage:**

- ✅ Vault deposit/withdrawal
- ✅ Note creation and validation
- ✅ Balance locking mechanisms
- ✅ Settlement outcome logic

## 🚀 **Deployment**

### **Testnet Deployment**

```bash
# Switch to testnet
sui client switch --env testnet

# Publish package
sui client publish --gas-budget 20000000

# Note the package ID for frontend integration
```

### **Mainnet Considerations**

- Audit all modules before mainnet deployment
- Test extensively on testnet first
- Consider upgrade policies for modules
- Implement proper monitoring and alerting

## 📚 **Advanced Usage**

### **Integration with Frontend**

```typescript
// TypeScript SDK integration example
const vault = new VaultClient(packageId)
await vault.deposit(coinAmount)
const note = await vault.createNote({
  maker: makerAddress,
  amount: betAmount,
  direction: 'UP',
  // ...other parameters
})
```

### **Custom Asset Support**

```move
// Create vault for custom coin type
let (admin_cap, order_cap, vault) = vault::initialize<MY_COIN>(ctx);
```

## 🤝 **Contributing**

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## 📄 **License**

This project maintains the same license as the original Solidity contracts.

---

**Migration completed successfully! 🎉**  
All original functionality preserved with enhanced security and SUI-native optimizations.
