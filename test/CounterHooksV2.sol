// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Counter} from "../src/Counter.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PositionConfig} from "v4-periphery/src/libraries/PositionConfig.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

contract CounterHooksV2 is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Counter hook;

    PoolId poolId;

    uint256 tokenId;
    PositionConfig config;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.AFTER_SWAP_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("Counter.sol:Counter", constructorArgs, flags);

        // Flag represent the address of the hook including the corredct flag
        hook = Counter(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();

        // Hookless pool doesn't expect any Initialization data
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provive full range of liquidity
        // PositionConfig: Defines the parameters for the liquidity position
        // poolKey: Identifies the specific pool
        // tickLower and tickUpper:
        // Define the price range for the position (here, it's set to the full range)
        config = PositionConfig({
            poolKey: key,
            tickLower: TickMath.minUsableTick(key.tickSpacing),
            tickUpper: TickMath.maxUsableTick(key.tickSpacing)
        });

        // NOTE: mint function internally call modifyLiquidities. which calls the hooks associate with it.
        // Create a new liquidity position in a pool and provide liquidity to V4 "key": receive NFT for ownership
        // @audit-info Always recommended to interact with V4 Periphery
        (tokenId, ) = posm.mint(
            config, // => The position configuration
            10_000e18, // => The amount of liquidity to provide
            MAX_SLIPPAGE_ADD_LIQUIDITY, // Maximum allowed slippage for currency0
            MAX_SLIPPAGE_ADD_LIQUIDITY, // Maximum allowed slippage for currency1
            address(this), // The receipient of the NFT that represent the ownership of the position
            block.timestamp, // the deadline
            ZERO_BYTES
        ); // Additional data (empty in this case)
    }

    // Test Counter hooks
    function test_Counter_Hooks() public {
        // Initial assertions for each hooks

        //assert hook.beforeAddLiquidityCount(poolId) == 1 since I add liquidity in the setupfunction
        assertEq(hook.beforeAddLiquidityCount(poolId), 1); // incremented ++  inside the hook

        // assert hooks.beforeRemoveLiquidityCount == 0 since: I didn't remove liquidity yet
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        // assert hook.afterSwapCount equal to 0: No swap hasbeen done
        assertEq(hook.afterSwapCount(poolId), 0);

        // assert hook.beforeSwapCount equal to 0: No swap hasbeen done
        assertEq(hook.beforeSwapCount(poolId), 0);

        // console.log
        console.log(
            "balance address(this) in currency one",
            currency0.balanceOf(address(this))
        );

        // Test to perfome a swap
        // set ZeroforOne to true;
        bool zeroForOne = true;

        // specifiy the amount to swap: // negative number indicates exact input swap!
        int256 amountToSwap = -1e18;

        // perfom the swap
        // BalanceDelta Library for getting the amount0 and amount1 deltas from the BalanceDelta type
        BalanceDelta swapDelta = swap(
            key,
            zeroForOne,
            amountToSwap,
            ZERO_BYTES
        );

        // Post swap assertions
        // assert beforeSwapCount(poolId) == 1: Swapped occured
        assertEq(hook.beforeSwapCount(poolId), 1);
        assertEq(hook.afterSwapCount(poolId), 1);

        // assert that balanceDelta of the pool for ZeroForOne(token 0 to token 1 was added to the pool)
        // AssetEq swapDelta.amount0 == amountToswap
        assertEq(int256(swapDelta.amount0()), amountToSwap);
    }

    // TODO: testLiquidityHooks()
}
