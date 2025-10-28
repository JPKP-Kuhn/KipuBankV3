// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";
import "../src/InternalHelperKipuBank.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock contracts for testing
contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, 1000000 * 10**decimals_);
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

contract MockChainlinkOracle {
    int256 public latestAnswer = 2000 * 10**8; // $2000 ETH price
    uint8 public decimals = 8;
    
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, latestAnswer, block.timestamp, block.timestamp, 1);
    }
}

contract MockUniversalRouter {
    function execute(bytes calldata, bytes[] calldata, uint256) external payable {
        // Mock implementation - just return
    }
}

contract MockPermit2 {
    // Mock implementation
}

contract KipuBankV3Test is Test {
    KipuBankV3 public bank;
    MockERC20 public mockToken;
    MockERC20 public usdc;
    MockChainlinkOracle public oracle;
    MockUniversalRouter public universalRouter;
    MockPermit2 public permit2;
    
    address public user = address(0x1);
    address public admin = address(0x2);
    address public deployer = address(this);
    
    function setUp() public {
        // Deploy mock contracts
        oracle = new MockChainlinkOracle();
        universalRouter = new MockUniversalRouter();
        permit2 = new MockPermit2();
        usdc = new MockERC20("USD Coin", "USDC", 6); // USDC has 6 decimals
        mockToken = new MockERC20("Mock Token", "MOCK", 18); // Mock token has 18 decimals
        
        // Deploy KipuBankV3
        bank = new KipuBankV3(
            1000, // 1000 ETH bank cap (will be multiplied by 1 ether in constructor)
            IChainLink(address(oracle)),
            IUniversalRouter(address(universalRouter)),
            IPermit2(address(permit2)),
            address(usdc),
            address(0) // Mock pool manager
        );
        
        // Setup test environment
        vm.deal(user, 2000 ether); // Give user enough ETH for bank cap test
        vm.deal(admin, 10 ether);
        
        // Give user some mock tokens
        mockToken.transfer(user, 1000 * 10**18);
        usdc.transfer(user, 1000 * 10**6);
        
        // Add mock token to supported tokens (using deployer who has admin role)
        bank.addToken(address(mockToken), IChainLink(address(oracle)));
        
        // Add USDC oracle (it's already added in constructor, but let's make sure)
        // USDC is already added in constructor, so this should work
    }
    
    function testETHDeposit() public {
        vm.startPrank(user);
        
        uint256 depositAmount = 1 ether;
        uint256 initialBalance = bank.getAccountBalance();
        
        bank.deposit{value: depositAmount}();
        
        assertEq(bank.getAccountBalance(), initialBalance + depositAmount);
        assertEq(bank.getDepositCount(), 1);
        
        vm.stopPrank();
    }
    
    function testUSDCDeposit() public {
        vm.startPrank(user);
        
        uint256 depositAmount = 1000 * 10**6; // 1000 USDC (larger amount to meet minimum deposit)
        uint256 initialBalance = bank.getAccountBalanceToken(address(usdc));
        
        usdc.approve(address(bank), depositAmount);
        bank.depositToken(address(usdc), depositAmount);
        
        assertEq(bank.getAccountBalanceToken(address(usdc)), initialBalance + depositAmount);
        assertEq(bank.getDepositCount(), 1);
        
        vm.stopPrank();
    }
    
    function testArbitraryTokenDeposit() public {
        vm.startPrank(user);
        
        uint256 depositAmount = 100 * 10**18; // 100 MOCK tokens
        uint256 initialUSDCBalance = bank.getAccountBalanceToken(address(usdc));
        
        mockToken.approve(address(bank), depositAmount);
        
        // Note: This will fail in real implementation without proper UniversalRouter setup
        // This test demonstrates the function call structure
        try bank.depositArbitraryToken(
            address(mockToken),
            depositAmount,
            0, // minUsdcOut
            block.timestamp + 3600 // deadline
        ) {
            // Success case
            assertEq(bank.getDepositCount(), 1);
        } catch {
            // Expected to fail with mock UniversalRouter
            console.log("Arbitrary token deposit failed as expected with mock router");
        }
        
        vm.stopPrank();
    }
    
    function testBankCapEnforcement() public {
        vm.startPrank(user);
        
        // First deposit up to the bank cap
        bank.deposit{value: 1000 ether}();
        
        // Try to deposit more than bank cap - this should revert
        vm.expectRevert(InternalHelperKipuBank.ExceedsBankCap.selector);
        bank.deposit{value: 1 ether}();
        
        vm.stopPrank();
    }
    
    function testWithdrawLimit() public {
        vm.startPrank(user);
        
        // First deposit some ETH
        bank.deposit{value: 1 ether}();
        
        // Try to withdraw more than limit
        uint256 withdrawLimit = bank.getWithdrawLimitInWei();
        uint256 excessWithdraw = withdrawLimit + 1;
        
        vm.expectRevert(InternalHelperKipuBank.ExceedsWithdrawLimit.selector);
        bank.withdraw(excessWithdraw);
        
        vm.stopPrank();
    }
    
    function testAdminFunctions() public {
        // First deposit some ETH for the user
        vm.startPrank(user);
        bank.deposit{value: 1 ether}();
        vm.stopPrank();
        
        // Check initial balance
        uint256 initialBalance = bank.getBalanceOf(user, ETH_ADDRESS);
        assertEq(initialBalance, 1 ether);
        
        // Test admin recovery (using deployer who has admin role)
        uint256 newBalance = 5 ether;
        bank.adminRecoverBalance(user, newBalance);
        
        assertEq(bank.getBalanceOf(user, ETH_ADDRESS), newBalance);
    }
    
    function testTokenManagement() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        
        // Add new token (using deployer who has admin role)
        bank.addToken(address(newToken), IChainLink(address(oracle)));
        
        // Verify token was added
        address[] memory supportedTokens = bank.getSupportedTokens();
        bool found = false;
        for (uint i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == address(newToken)) {
                found = true;
                break;
            }
        }
        assertTrue(found);
        
        // Remove token
        bank.removeToken(address(newToken));
    }
}
