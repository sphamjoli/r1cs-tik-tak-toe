// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {GameTestBase} from "./GameTest.t.sol";
import {TikTakToeGame} from "../src/TikTakToeGame.sol";
import {ITikTakToeGame} from "../src/ITikTakToeGame.sol";

/// @notice Bounded multi-game handler; ghost liabilities change only after successful actions.
contract GameHandler is Test {
    struct HandlerConfig {
        TikTakToeGame game;
        address alice;
        address bob;
        GameTestBase.ProofData proof;
    }

    TikTakToeGame private _game;
    address private _alice;
    address private _bob;
    GameTestBase.ProofData private _proof;
    uint256[8] private _slots;
    mapping(uint256 => ITikTakToeGame.Move) private _pending;
    uint256 public ghostEscrow;
    uint256 public successfulActions;
    uint256 public proofPayouts;
    uint256 public draws;

    constructor(HandlerConfig memory config) {
        _game = config.game;
        _alice = config.alice;
        _bob = config.bob;
        _proof = config.proof;
    }

    function _wrap(address actor, uint256 amount) private {
        vm.deal(actor, actor.balance + amount);
        vm.prank(actor);
        _game.wrap{value: amount}();
    }

    function create(uint256 seed, uint256 stakeSeed) external {
        uint256 slot = seed % 8;
        if (_slots[slot] != 0) {
            (,,,, bool active,) = _game.games(_slots[slot] - 1);
            if (active) return;
        }
        uint256 stake = _bound(stakeSeed, 1, 1 ether);
        _wrap(_alice, stake);
        vm.prank(_alice);
        uint256 id = _game.createGame(_bob, stake);
        _slots[slot] = id + 1;
        ghostEscrow += stake;
        successfulActions++;
    }

    function join(uint256 seed) external {
        (bool usable, uint256 id) = _active(seed);
        if (!usable || _game.gameProgress(id).joined) return;
        (,, uint256 stake,,,) = _game.games(id);
        _wrap(_bob, stake);
        vm.prank(_bob);
        _game.joinGame(id);
        ghostEscrow += stake;
        successfulActions++;
    }

    function cancel(uint256 seed) external {
        (bool usable, uint256 id) = _active(seed);
        if (!usable || _game.gameProgress(id).joined) return;
        (,, uint256 stake,,,) = _game.games(id);
        vm.prank(_alice);
        _game.cancelGame(id);
        ghostEscrow -= stake;
        successfulActions++;
    }

    function play(uint256 seed, uint256 positionSeed) external {
        (bool usable, uint256 id) = _active(seed);
        if (!usable) return;
        ITikTakToeGame.Progress memory progress = _game.gameProgress(id);
        if (!progress.joined || progress.outcome != 0 || block.timestamp > progress.deadline) {
            return;
        }
        (,, uint256 stake,,, uint8 count) = _game.games(id);
        address actor = progress.revealedCount % 2 == 0 ? _alice : _bob;
        if (count > progress.revealedCount) {
            vm.prank(actor);
            _game.revealMove(id, _pending[id]);
            (,,,, bool active,) = _game.games(id);
            if (!active) {
                ghostEscrow -= stake * 2;
                draws++;
            }
        } else {
            uint256 position = positionSeed % 9;
            for (uint256 i = 0; i < 9; i++) {
                if (progress.board[position] == 2) break;
                position = (position + 1) % 9;
            }
            ITikTakToeGame.Move memory move = ITikTakToeGame.Move(
                uint8(position / 3),
                uint8(position % 3),
                progress.revealedCount % 2,
                bytes32(positionSeed)
            );
            _pending[id] = move;
            bytes32 commitment = _game.moveCommitment(id, move);
            vm.prank(actor);
            _game.commitMove(id, commitment);
        }
        successfulActions++;
    }

    function timeout(uint256 seed) external {
        (bool usable, uint256 id) = _active(seed);
        if (!usable) return;
        ITikTakToeGame.Progress memory progress = _game.gameProgress(id);
        if (!progress.joined || progress.outcome != 0) return;
        (,, uint256 stake,,,) = _game.games(id);
        vm.warp(progress.deadline > block.timestamp ? progress.deadline + 1 : block.timestamp + 1);
        vm.prank(progress.revealedCount % 2 == 0 ? _bob : _alice);
        _game.claimTimeout(id);
        ghostEscrow -= stake * 2;
        successfulActions++;
    }

    // Exercises real proof settlement amid arbitrary outstanding games and deadlines.
    function proofWin(uint256 stakeSeed) external {
        uint256 stake = _bound(stakeSeed, 1, 1 ether);
        _wrap(_alice, stake);
        _wrap(_bob, stake);
        vm.prank(_alice);
        uint256 id = _game.createGame(_bob, stake);
        ghostEscrow += stake;
        vm.prank(_bob);
        _game.joinGame(id);
        ghostEscrow += stake;
        uint8[5] memory positions = [uint8(0), 3, 1, 4, 2];
        ITikTakToeGame.Move[] memory moves = new ITikTakToeGame.Move[](5);
        for (uint8 i = 0; i < 5; i++) {
            moves[i] = ITikTakToeGame.Move(
                positions[i] / 3, positions[i] % 3, i % 2, bytes32(uint256(i) + 1)
            );
            address actor = i % 2 == 0 ? _alice : _bob;
            bytes32 commitment = _game.moveCommitment(id, moves[i]);
            vm.prank(actor);
            _game.commitMove(id, commitment);
            vm.prank(actor);
            _game.revealMove(id, moves[i]);
        }
        vm.prank(_alice);
        _game.revealAndClaimWin(id, moves, _proof.a, _proof.b, _proof.c, _proof.publicSignals);
        ghostEscrow -= stake * 2;
        successfulActions++;
        proofPayouts++;
    }

    function transferAndUnwrap(uint256 seed, uint256 amountSeed) external {
        address actor = seed % 2 == 0 ? _alice : _bob;
        uint256 balance = _game.balanceOf(actor);
        if (balance == 0) return;
        uint256 amount = _bound(amountSeed, 1, balance);
        vm.prank(actor);
        if (seed % 3 == 0) {
            _game.transfer(address(_game), amount);
        } else {
            _game.unwrap(amount);
        }
        successfulActions++;
    }

    function _active(uint256 seed) private view returns (bool usable, uint256 id) {
        uint256 entry = _slots[seed % 8];
        if (entry == 0) return (false, 0);
        id = entry - 1;
        (,,,, usable,) = _game.games(id);
    }
}

contract GameInvariants is GameTestBase {
    GameHandler private handler;

    function setUp() public override {
        super.setUp();
        handler = new GameHandler(
            GameHandler.HandlerConfig(game, alice, bob, _loadProof("player0_wins_row0"))
        );
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = GameHandler.create.selector;
        selectors[1] = GameHandler.join.selector;
        selectors[2] = GameHandler.cancel.selector;
        selectors[3] = GameHandler.play.selector;
        selectors[4] = GameHandler.timeout.selector;
        selectors[5] = GameHandler.proofWin.selector;
        selectors[6] = GameHandler.transferAndUnwrap.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
        excludeContract(address(game));
        excludeContract(address(verifier));
    }

    function invariant_EscrowAndBackingAreConserved() public view {
        assertEq(game.totalEscrow(), handler.ghostEscrow());
        assertGe(game.balanceOf(address(game)), handler.ghostEscrow());
        assertGe(address(game).balance, game.totalSupply());
    }
}
