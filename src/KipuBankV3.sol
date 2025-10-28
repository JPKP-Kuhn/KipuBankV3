// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@universal-router/interfaces/IUniversalRouter.sol";
import "@permit2/interfaces/IPermit2.sol";
import "@v4-core/types/PoolKey.sol";
import "@v4-core/types/Currency.sol";
import "./InternalHelperKipuBank.sol";

/// @title KipuBankV3
/// @notice Advanced multi-token bank with Uniswap V3 integration for arbitrary token deposits
/// @dev Supports ETH, USDC, and any ERC-20 token supported by Uniswap V3
/// @author JPKP-Kuhn
contract KipuBankV3 is AccessControl, InternalHelperKipuBank {
    using SafeERC20 for IERC20;
    
    // ============================================
    // Roles
    // ============================================
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");

    // ============================================
    // Constants
    // ============================================
    
    uint256 public constant WITHDRAW_LIMIT_USD = 1000 * 1e18;
    uint256 public constant minimumDeposit = 0.001 ether;

    // ============================================
    // State Variables
    // ============================================
    
    /// @notice Total count of deposits and withdraws
    uint256 public depositCount;
    uint256 public withdrawCount;

    /// @notice Global limit for deposits
    uint256 public immutable bankCap;

    /// @notice Per-transaction native (wei) cap for ETH withdrawals
    uint256 public nativePerTxCapWei;

    /// @notice Total balance in ETH equivalent
    uint256 public totalBalance;

    /// @notice Multi-token balance: user => token => balance
    mapping(address => mapping(address => uint256)) private accountsBalance;

    /// @notice Array of supported tokens for enumeration
    address[] public supportedTokens;

    /// @notice token => index of token in supportedToken, for O(1) search
    mapping(address => uint256) private tokenIndex;

    /// @notice Reentrancy lock
    bool private locked;

    /// @notice UniversalRouter instance for Uniswap V4 integration
    IUniversalRouter public immutable universalRouter;

    /// @notice Permit2 instance for token approvals
    IPermit2 public immutable permit2;

    /// @notice USDC token address for swaps
    address public immutable usdc;

    /// @notice Uniswap V4 PoolManager for direct swaps
    address public immutable poolManager;

    // ============================================
    // Modifiers
    // ============================================

    /// @dev Modifier to prevent reentrancy attacks
    modifier noReentrancy() {
        if (locked) revert ReentrancyDetected();
        locked = true;
        _;
        locked = false;
    }

    // ============================================
    // Events
    // ============================================

    event DepositOk(address indexed user, uint256 value, uint256 newBalance, bytes feedback);
    event WithdrawOk(address indexed user, uint256 value, uint256 newBalance, bytes feedback);
    event DepositTokenOk(address indexed user, address indexed token, uint256 value, uint256 newBalance, bytes feedback);
    event WithdrawTokenOk(address indexed user, address indexed token, uint256 value, uint256 newBalance, bytes feedback);
    event DepositArbitraryTokenOk(address indexed user, address indexed token, uint256 inputAmount, uint256 usdcReceived, uint256 newBalance, bytes feedback);
    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event adminRecovery(address indexed user, uint256 oldBalance, uint256 newBalance, bytes feedback);
    event NativePerTxCapUpdated(uint256 oldCap, uint256 newCap);

    // ============================================
    // Constructor
    // ============================================
    
    /// @param _bankcap Bank capacity in ETH
    /// @param _oracle ETH/USD Chainlink oracle address
    /// @param _universalRouter UniversalRouter contract address
    /// @param _permit2 Permit2 contract address
    /// @param _usdc USDC token address
    /// @param _poolManager Uniswap V4 PoolManager address
    constructor(
        uint256 _bankcap, 
        IChainLink _oracle,
        IUniversalRouter _universalRouter,
        IPermit2 _permit2,
        address _usdc,
        address _poolManager
    ) 
        InternalHelperKipuBank(_oracle) 
    {
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(TOKEN_MANAGER_ROLE, msg.sender);
        
        bankCap = _bankcap * 1 ether;
        universalRouter = _universalRouter;
        permit2 = _permit2;
        usdc = _usdc;
        poolManager = _poolManager;

        // Add ETH as default supported token
        tokenOracles[ETH_ADDRESS] = _oracle;
        supportedTokens.push(ETH_ADDRESS);
        isSupportedToken[ETH_ADDRESS] = true;
        tokenIndex[ETH_ADDRESS] = 1; // 1-based indexing

        // Add USDC as supported token with oracle
        tokenOracles[_usdc] = _oracle; // Using same oracle for USDC (should be USDC/USD oracle in production)
        supportedTokens.push(_usdc);
        isSupportedToken[_usdc] = true;
        tokenIndex[_usdc] = 2; // 1-based indexing
    }

    // ============================================
    // Counter Functions
    // ============================================

    function _incrementDeposit() private {
        depositCount++;
    }

    function getDepositCount() external view returns (uint256) {
        return depositCount;
    }

    function _incrementWithdraw() private {
        withdrawCount++;
    }

    function getWithdrawCount() external view returns (uint256) {
        return withdrawCount;
    }

    // ============================================
    // Balance Query Functions
    // ============================================

    /// @notice Get ETH balance for the caller
    function getAccountBalance() external view returns (uint256) {
        return accountsBalance[msg.sender][ETH_ADDRESS];
    }
    
    /// @notice Get balance for a specific token
    /// @param token Token address (use ETH_ADDRESS for ETH)
    function getAccountBalanceToken(address token) external view returns (uint256) {
        return accountsBalance[msg.sender][token];
    }
    
    /// @notice Get balance for a specific user and token
    /// @param user User address
    /// @param token Token address (use ETH_ADDRESS for ETH)
    function getBalanceOf(address user, address token) external view checkSupportedToken(token) returns (uint256) {
        return accountsBalance[user][token];
    }

    // ============================================
    // Withdrawal Limit Functions
    // ============================================

    /// @notice Calculate withdraw limit in Wei for ETH
    function getWithdrawLimitInWei() public view returns (uint256) {
        uint256 price = getEthUSD();
        uint8 decimals = getDecimals();

        uint256 limitWei = (WITHDRAW_LIMIT_USD * (10 ** uint256(decimals))) / price;
        return limitWei;
    }

    /// @notice Calculate withdraw limit in token units for a specific token
    /// @param token Token address
    function getWithdrawLimitInToken(address token) public view checkSupportedToken(token) returns (uint256) {
        uint256 price = getTokenPriceUSD(token);
        uint8 decimals = getTokenOracleDecimals(token);

        uint8 tokenDecimals = _getTokenDecimals(token);

        // Calculate limit: (WITHDRAW_LIMIT_USD * oracle_decimals / price) adjusted for token decimals
        uint256 limitInToken = (WITHDRAW_LIMIT_USD * (10 ** uint256(decimals))) / price;

        // Adjust for token decimals (assuming WITHDRAW_LIMIT_USD is in 18 decimals)
        if (tokenDecimals < 18) {
            limitInToken = limitInToken / (10 ** (18 - tokenDecimals));
        } else if (tokenDecimals > 18) {
            limitInToken = limitInToken * (10 ** (tokenDecimals - 18));
        }

        return limitInToken;
    }

    // ============================================
    // ETH Deposit & Withdraw Functions
    // ============================================

    /// @notice Deposit ETH
    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        if (msg.value < minimumDeposit) revert MinimunDepositRequired();
        if (totalBalance + msg.value > bankCap) revert ExceedsBankCap();
        
        // Effects
        accountsBalance[msg.sender][ETH_ADDRESS] += msg.value;
        totalBalance += msg.value;
        _incrementDeposit();

        emit DepositOk(msg.sender, msg.value, accountsBalance[msg.sender][ETH_ADDRESS], "Deposit Success!");
    }

    /// @notice Withdraw ETH
    /// @dev Follows CEI pattern: checks, effects, interactions
    function withdraw(uint256 _value) external noReentrancy {
        if (_value == 0) revert ZeroAmount();

        uint256 withdrawLimit = getWithdrawLimitInWei();
        if (_value > withdrawLimit) revert ExceedsWithdrawLimit();

        // Check native per-transaction cap
        if (nativePerTxCapWei != 0 && _value > nativePerTxCapWei) revert ExceedsWithdrawLimit();

        if (_value > accountsBalance[msg.sender][ETH_ADDRESS]) revert InsufficientBalance();

        // Effects
        accountsBalance[msg.sender][ETH_ADDRESS] -= _value;
        totalBalance -= _value;
        _incrementWithdraw();

        // Interaction
        (bool success, ) = msg.sender.call{value: _value}("");
        if (!success) revert TransferFailed();

        // Emit event
        emit WithdrawOk(msg.sender, _value, accountsBalance[msg.sender][ETH_ADDRESS], "Withdraw Success!");
    }

    // ============================================
    // ERC-20 Token Deposit & Withdraw Functions
    // ============================================

    /// @notice Deposit ERC-20 tokens
    /// @param token Token address to deposit
    /// @param amount Amount of tokens to deposit
    function depositToken(address token, uint256 amount) external noReentrancy checkSupportedToken(token) {
        if (amount == 0) revert ZeroAmount();
        
        // Check minimum deposit (converted to token units)
        uint256 minDepositInToken = _convertEthToToken(minimumDeposit, token);
        if (amount < minDepositInToken) revert MinimunDepositRequired();
        
        // Convert token amount to ETH equivalent for bank cap check
        uint256 ethEquivalent = _convertTokenToEth(amount, token);
        if (totalBalance + ethEquivalent > bankCap) revert ExceedsBankCap();
        
        // Interactions - transfer tokens from user to contract using SafeERC20
        uint256 before = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - before;
        
        // Effects - update balances after successful transfer
        accountsBalance[msg.sender][token] += received;
        totalBalance += _convertTokenToEth(received, token);
        _incrementDeposit();
        
        emit DepositTokenOk(msg.sender, token, received, accountsBalance[msg.sender][token], "Token Deposit Success!");
    }
    
    /// @notice Withdraw ERC-20 tokens
    /// @param token Token address to withdraw
    /// @param amount Amount of tokens to withdraw
    function withdrawToken(address token, uint256 amount) external noReentrancy checkSupportedToken(token) {
        if (amount == 0) revert ZeroAmount();
        
        uint256 withdrawLimit = getWithdrawLimitInToken(token);
        if (amount > withdrawLimit) revert ExceedsWithdrawLimit();
        
        if (amount > accountsBalance[msg.sender][token]) revert InsufficientBalance();
        
        // Effects - update balances before transfer
        accountsBalance[msg.sender][token] -= amount;
        uint256 ethEquivalent = _convertTokenToEth(amount, token);
        totalBalance -= ethEquivalent;
        _incrementWithdraw();
        
        // Interactions - transfer tokens to user using SafeERC20
        IERC20(token).safeTransfer(msg.sender, amount);
        
        emit WithdrawTokenOk(msg.sender, token, amount, accountsBalance[msg.sender][token], "Token Withdraw Success!");
    }

    // ============================================
    // Uniswap V4 Integration Functions
    // ============================================

    /// @notice Deposit any ERC-20 token and swap it to USDC
    /// @param token Token address to deposit
    /// @param amount Amount of tokens to deposit
    /// @param minUsdcOut Minimum USDC amount expected from swap
    /// @param deadline Deadline for the swap
    function depositArbitraryToken(
        address token,
        uint256 amount,
        uint256 minUsdcOut,
        uint256 deadline
    ) external noReentrancy {
        if (amount == 0) revert ZeroAmount();
        if (token == address(0) || token == ETH_ADDRESS) revert InvalidAddress();
        if (token == usdc) revert InvalidAddress(); // Use depositToken for USDC directly
        
        // Check minimum deposit (converted to token units)
        uint256 minDepositInToken = _convertEthToToken(minimumDeposit, token);
        if (amount < minDepositInToken) revert MinimunDepositRequired();
        
        // Transfer tokens from user to contract
        uint256 before = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - before;
        
        // Estimate USDC output (approximate, using oracle prices for validation)
        // Note: This is an approximation for cap checking, actual amount may vary
        uint256 estimatedEthEquivalent = _convertTokenToEth(received, token);
        
        // Check bank cap BEFORE swap (using estimated conversion)
        if (totalBalance + estimatedEthEquivalent > bankCap) revert ExceedsBankCap();
        
        // Approve UniversalRouter to spend tokens
        IERC20(token).forceApprove(address(universalRouter), received);
        
        // Execute swap to USDC
        uint256 usdcReceived = _swapExactInputSingle(token, usdc, received, minUsdcOut, deadline);
        
        // Convert actual USDC received to ETH equivalent for bank cap check (final validation)
        uint256 actualEthEquivalent = _convertTokenToEth(usdcReceived, usdc);
        
        // Final check: ensure swap didn't exceed cap (should not happen, but safety check)
        if (totalBalance + actualEthEquivalent > bankCap) revert ExceedsBankCap();
        
        // Effects - update balances after successful swap
        accountsBalance[msg.sender][usdc] += usdcReceived;
        totalBalance += actualEthEquivalent;
        _incrementDeposit();
        
        emit DepositArbitraryTokenOk(msg.sender, token, received, usdcReceived, accountsBalance[msg.sender][usdc], "Arbitrary Token Deposit Success!");
    }

    /// @notice Internal function to encode Uniswap V3 path
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param fee Fee tier (e.g., 3000 for 0.3%)
    /// @return path Encoded path bytes
    function _encodeV3Path(address tokenIn, address tokenOut, uint24 fee) internal pure returns (bytes memory path) {
        // Uniswap V3 path format: token0 (20 bytes) + fee (3 bytes) + token1 (20 bytes) = 43 bytes
        // Tokens must be sorted: token0 < token1 (for pool identification)
        // But for the path, we keep the order as tokenIn -> tokenOut
        path = new bytes(43);
        assembly {
            // Store tokenIn at position 0
            mstore(add(path, 32), shl(96, tokenIn))
            // Store fee at position 20 (3 bytes)
            mstore(add(path, 52), shl(232, fee))
            // Store tokenOut at position 23
            mstore(add(path, 55), shl(96, tokenOut))
        }
    }

    /// @notice Internal function to execute exact input single swap using UniversalRouter
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address (should be USDC)
    /// @param amountIn Amount of input tokens
    /// @param minAmountOut Minimum amount of output tokens expected
    /// @param deadline Deadline for the swap
    /// @return amountOut Actual amount of output tokens received
    function _swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        // Encode Uniswap V3 path: tokenIn -> fee -> tokenOut
        bytes memory path = _encodeV3Path(tokenIn, tokenOut, uint24(3000)); // 0.3% fee tier
        
        // Prepare UniversalRouter commands and inputs
        // V3_SWAP_EXACT_IN = 0x00
        bytes memory commands = abi.encodePacked(uint8(0x00));
        
        // Encode swap parameters for V3_SWAP_EXACT_IN
        // Parameters: (address recipient, uint256 amountIn, uint256 amountOutMin, bytes path, bool payerIsUser)
        bytes memory swapParams = abi.encode(
            address(this),    // recipient
            amountIn,         // amountIn
            minAmountOut,     // amountOutMinimum
            path,             // path (token0 + fee + token1)
            false             // payerIsUser (false because we're paying from contract balance)
        );
        
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = swapParams;
        
        // Record USDC balance before swap
        uint256 usdcBefore = IERC20(tokenOut).balanceOf(address(this));
        
        // Execute swap via UniversalRouter
        universalRouter.execute(commands, inputs, deadline);
        
        // Calculate actual amount received
        amountOut = IERC20(tokenOut).balanceOf(address(this)) - usdcBefore;
        
        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut);
        
        return amountOut;
    }

    // ============================================
    // Admin Functions
    // ============================================

    /// @notice Admin recovery for ETH balance
    /// @param user User address
    /// @param newBalance New balance in wei
    function adminRecoverBalance(address user, uint256 newBalance) external onlyRole(ADMIN_ROLE) {
        uint256 oldBalance = accountsBalance[user][ETH_ADDRESS];
        accountsBalance[user][ETH_ADDRESS] = newBalance;
        totalBalance += newBalance - oldBalance;
        emit adminRecovery(user, oldBalance, newBalance, "Recovery success!");
    }
    
    /// @notice Admin recovery for specific token balance
    /// @param user User address
    /// @param token Token address
    /// @param newBalance New balance for the user
    function adminRecoverTokenBalance(
        address user, 
        address token, 
        uint256 newBalance
    ) 
        external 
        onlyRole(ADMIN_ROLE)
        checkSupportedToken(token)
    {
        uint256 oldBalance = accountsBalance[user][token];
        accountsBalance[user][token] = newBalance;
        
        // Adjust totalBalance (convert to ETH equivalent)
        if (token == ETH_ADDRESS) {
            totalBalance += newBalance - oldBalance;
        } else {
            uint256 oldEthEquiv = _convertTokenToEth(oldBalance, token);
            uint256 newEthEquiv = _convertTokenToEth(newBalance, token);
            totalBalance = totalBalance - oldEthEquiv + newEthEquiv;
        }
        
        emit adminRecovery(user, oldBalance, newBalance, "Token Recovery Success!");
    }
    
    /// @notice Admin can withdraw tokens from contract (emergency recovery)
    /// @param token Token address (use ETH_ADDRESS for ETH)
    /// @param recipient Recipient address
    /// @param amount Amount to withdraw
    function adminWithdrawFunds(
        address token, 
        address recipient, 
        uint256 amount
    ) 
        external 
        onlyRole(ADMIN_ROLE)
        noReentrancy
    {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();
        
        if (token == ETH_ADDRESS) {
            // Withdraw ETH
            (bool success, ) = recipient.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Withdraw ERC-20 using SafeERC20
            IERC20(token).safeTransfer(recipient, amount);
        }
    }
    
    /// @notice Set native per-transaction cap for ETH withdrawals
    /// @param cap Cap in wei (0 to disable)
    function setNativePerTxCapWei(uint256 cap) external onlyRole(ADMIN_ROLE) {
        uint256 oldCap = nativePerTxCapWei;
        nativePerTxCapWei = cap;
        emit NativePerTxCapUpdated(oldCap, cap);
    }

    // ============================================
    // Token Management Functions
    // ============================================

    /// @notice Add support for a new ERC-20 token
    /// @param token Token address
    /// @param tokenOracle Chainlink oracle for token/USD price feed
    function addToken(address token, IChainLink tokenOracle) 
        external 
        onlyRole(TOKEN_MANAGER_ROLE) 
    {
        if (token == address(0) || token == ETH_ADDRESS) revert InvalidAddress();
        if (address(tokenOracle) == address(0)) revert InvalidAddress();
        if (isSupportedToken[token]) revert TokenAlreadySupported();
        
        tokenOracles[token] = tokenOracle;
        supportedTokens.push(token);
        isSupportedToken[token] = true;
        tokenIndex[token] = supportedTokens.length; // 1-based indexing
        
        emit TokenAdded(token, address(tokenOracle), "Token Added Success!");
    }
    
    /// @notice Remove support for a token
    /// @param token Token address to remove
    function removeToken(address token) 
        external 
        onlyRole(TOKEN_MANAGER_ROLE) 
    {
        if (token == ETH_ADDRESS) revert InvalidAddress();
        if (!isSupportedToken[token]) revert TokenNotSupported();
        
        uint indexToRemove = tokenIndex[token] - 1;
        uint lastIndex = supportedTokens.length - 1;

        // If not the last element, move the last element to the removed position
        if (indexToRemove != lastIndex) {
            address lastToken = supportedTokens[lastIndex];
            supportedTokens[indexToRemove] = lastToken;
            tokenIndex[lastToken] = indexToRemove + 1; // Update moved token's index
        }

        // Remove from supportedTokens array
        supportedTokens.pop();

        isSupportedToken[token] = false;
        delete tokenOracles[token];
        delete tokenIndex[token];
        
        emit TokenRemoved(token, "Token Removed Success!");
    }
    
    /// @notice Get list of all supported tokens
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    // ============================================
    // Fallback Functions
    // ============================================

    fallback() external { 
        revert("Invalid Call");
    }

    receive() external payable {
        revert("Direct ETH not accepted. Use deposit()");
    }
}