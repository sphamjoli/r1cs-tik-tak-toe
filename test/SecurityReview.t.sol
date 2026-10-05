// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {GameTestBase} from "./GameTest.t.sol";
import {TikTakToeGame} from "../src/TikTakToeGame.sol";
import {ITikTakToeGame} from "../src/ITikTakToeGame.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Regression checks against the real Groth16 verifier and funded proxy.
contract SecurityReviewTest is GameTestBase {
    function _create(bool joined) internal returns (uint256 id) {
        vm.prank(alice);
        game.wrap{value: 20 ether}();
        vm.prank(bob);
        game.wrap{value: 20 ether}();
        vm.prank(alice);
        id = game.createGame(bob, 5 ether);
        if (joined) {
            vm.prank(bob);
            game.joinGame(id);
        }
    }

    function _move(
        uint8 position,
        uint8 player
    )
        internal
        pure
        returns (ITikTakToeGame.Move memory)
    {
        return
            ITikTakToeGame.Move(position / 3, position % 3, player, bytes32(uint256(position) + 1));
    }

    function _play(uint256 id, ITikTakToeGame.Move memory move) internal {
        address actor = move.player == 0 ? alice : bob;
        bytes32 commitment = game.moveCommitment(id, move);
        vm.prank(actor);
        game.commitMove(id, commitment);
        vm.prank(actor);
        game.revealMove(id, move);
    }

    function _winningGame()
        internal
        returns (uint256 id, ITikTakToeGame.Move[] memory moves, ProofData memory proof)
    {
        id = _create(true);
        moves = _loadMoves("player0_wins_row0");
        for (uint256 i = 0; i < moves.length; i++) {
            _play(id, moves[i]);
        }
        proof = _loadProof("player0_wins_row0");
    }

    function test_RejectsNonWinningProofThatRealVerifierAccepts() public {
        uint256 id = _create(true);
        ProofData memory proof = _loadProof("no_win");
        assertEq(proof.publicSignals[0], 0);
        assertTrue(verifier.verifyProof(proof.a, proof.b, proof.c, proof.publicSignals));
        ITikTakToeGame.Move[] memory moves = new ITikTakToeGame.Move[](0);
        vm.prank(alice);
        vm.expectRevert(ITikTakToeGame.InvalidProof.selector);
        game.revealAndClaimWin(id, moves, proof.a, proof.b, proof.c, proof.publicSignals);
        assertEq(game.totalEscrow(), 10 ether);
    }

    function test_RejectsUnfundedClaimDespiteOtherGameDeposits() public {
        uint256 id = _create(false);
        _create(true);
        ProofData memory proof = _loadProof("no_win");
        ITikTakToeGame.Move[] memory moves = new ITikTakToeGame.Move[](0);
        vm.prank(alice);
        vm.expectRevert(ITikTakToeGame.GameNotJoined.selector);
        game.revealAndClaimWin(id, moves, proof.a, proof.b, proof.c, proof.publicSignals);
        assertEq(game.totalEscrow(), 15 ether);
    }

    function test_RejectsDuplicateJoinWithoutTakingExtraStake() public {
        uint256 id = _create(true);
        uint256 beforeBalance = game.balanceOf(bob);
        vm.prank(bob);
        vm.expectRevert(ITikTakToeGame.AlreadyJoined.selector);
        game.joinGame(id);
        assertEq(game.balanceOf(bob), beforeBalance);
        assertEq(game.balanceOf(address(game)), 10 ether);
        assertEq(game.totalEscrow(), 10 ether);
    }

    function test_CancelsOwnUnjoinedEscrowDespiteUnrelatedDeposits() public {
        uint256 id = _create(false);
        _create(true);
        uint256 beforeBalance = game.balanceOf(alice);
        vm.prank(alice);
        game.cancelGame(id);
        (,,,, bool active,) = game.games(id);
        assertFalse(active);
        assertEq(game.balanceOf(alice), beforeBalance + 5 ether);
        assertEq(game.totalEscrow(), 10 ether);
        assertEq(game.balanceOf(address(game)), 10 ether);
    }

    function test_CannotCancelFundedGame() public {
        uint256 id = _create(true);
        vm.prank(alice);
        vm.expectRevert(ITikTakToeGame.AlreadyJoined.selector);
        game.cancelGame(id);
    }

    function test_RejectsUnfundedCommit() public {
        uint256 id = _create(false);
        vm.prank(alice);
        vm.expectRevert(ITikTakToeGame.GameNotJoined.selector);
        game.commitMove(id, bytes32(uint256(1)));
    }

    function test_AlternatingAuthenticatedTurnsRequireReveal() public {
        uint256 id = _create(true);
        ITikTakToeGame.Move memory move = _move(0, 0);
        bytes32 commitment = game.moveCommitment(id, move);
        vm.prank(bob);
        vm.expectRevert(ITikTakToeGame.NotYourTurn.selector);
        game.commitMove(id, commitment);
        vm.prank(alice);
        game.commitMove(id, commitment);
        vm.prank(bob);
        vm.expectRevert(ITikTakToeGame.MovesNotRevealed.selector);
        game.commitMove(id, commitment);
        vm.prank(bob);
        vm.expectRevert(ITikTakToeGame.NotYourTurn.selector);
        game.revealMove(id, move);
        vm.prank(alice);
        game.revealMove(id, move);
        vm.prank(alice);
        vm.expectRevert(ITikTakToeGame.NotYourTurn.selector);
        game.commitMove(id, commitment);
    }

    function test_CannotRevealOpponentsMark() public {
        uint256 id = _create(true);
        ITikTakToeGame.Move memory move = _move(0, 1);
        bytes32 commitment = game.moveCommitment(id, move);
        vm.prank(alice);
        game.commitMove(id, commitment);
        vm.prank(alice);
        vm.expectRevert(ITikTakToeGame.PlayerMismatch.selector);
        game.revealMove(id, move);
        _assertTimedOutTo(id, bob);
    }

    function test_InvalidCoordinatesAndOverwrittenCellsFail() public {
        uint256 id = _create(true);
        _play(id, _move(0, 0));
        ITikTakToeGame.Move memory move = _move(0, 1);
        bytes32 commitment = game.moveCommitment(id, move);
        vm.prank(bob);
        game.commitMove(id, commitment);
        vm.prank(bob);
        vm.expectRevert(ITikTakToeGame.InvalidMove.selector);
        game.revealMove(id, move);
        _assertTimedOutTo(id, alice);

        id = _create(true);
        move = _move(9, 0);
        commitment = game.moveCommitment(id, move);
        vm.prank(alice);
        game.commitMove(id, commitment);
        vm.prank(alice);
        vm.expectRevert(ITikTakToeGame.InvalidMove.selector);
        game.revealMove(id, move);
    }

    function test_RejectsBadSalt() public {
        uint256 id = _create(true);
        ITikTakToeGame.Move memory move = _move(0, 0);
        bytes32 commitment = game.moveCommitment(id, move);
        vm.prank(alice);
        game.commitMove(id, commitment);
        move.salt = bytes32(uint256(999));
        vm.prank(alice);
        vm.expectRevert(ITikTakToeGame.InvalidMoveSequence.selector);
        game.revealMove(id, move);
    }

    function test_NoPlayOrTimeoutAfterFirstWin() public {
        (uint256 id,,) = _winningGame();
        vm.prank(bob);
        vm.expectRevert(ITikTakToeGame.GameFinished.selector);
        game.commitMove(id, bytes32(uint256(1)));
        vm.warp(game.gameProgress(id).deadline + 1);
        vm.prank(bob);
        vm.expectRevert(ITikTakToeGame.GameFinished.selector);
        game.claimTimeout(id);
    }

    function test_DrawRefundsBothAndRejectsTenthCommit() public {
        uint256 id = _create(true);
        uint8[9] memory positions = [uint8(0), 1, 2, 4, 3, 5, 7, 6, 8];
        for (uint8 i = 0; i < 9; i++) {
            _play(id, _move(positions[i], i % 2));
        }
        (,,, address winner, bool active, uint8 count) = game.games(id);
        assertFalse(active);
        assertEq(winner, address(0));
        assertEq(count, 9);
        assertEq(game.gameProgress(id).outcome, 3);
        assertEq(game.balanceOf(alice), 20 ether);
        assertEq(game.balanceOf(bob), 20 ether);
        assertEq(game.totalEscrow(), 0);
        vm.prank(bob);
        vm.expectRevert(ITikTakToeGame.GameNotActive.selector);
        game.commitMove(id, bytes32(uint256(1)));
    }

    function _assertTimedOutTo(uint256 id, address winner) internal {
        vm.warp(game.gameProgress(id).deadline + 1);
        uint256 beforeBalance = game.balanceOf(winner);
        uint256 beforeEscrow = game.totalEscrow();
        vm.prank(winner);
        game.claimTimeout(id);
        assertEq(game.balanceOf(winner), beforeBalance + 10 ether);
        assertEq(game.totalEscrow(), beforeEscrow - 10 ether);
        (,,, address actualWinner, bool active,) = game.games(id);
        assertEq(actualWinner, winner);
        assertFalse(active);
        vm.prank(winner);
        vm.expectRevert(ITikTakToeGame.GameNotActive.selector);
        game.claimTimeout(id);
    }

    function test_TimeoutBeforeCommitPaysNonDefaultingPlayer() public {
        uint256 id = _create(true);
        _assertTimedOutTo(id, bob);
    }

    function test_TimeoutAfterRevealBelongsToOtherTurn() public {
        uint256 id = _create(true);
        _play(id, _move(0, 0));
        _assertTimedOutTo(id, alice);
    }

    function test_DeadlineBoundaryAndExpiredRevealCannotResetIt() public {
        uint256 id = _create(true);
        ITikTakToeGame.Move memory move = _move(0, 0);
        bytes32 commitment = game.moveCommitment(id, move);
        vm.warp(game.gameProgress(id).deadline);
        vm.prank(bob);
        vm.expectRevert(ITikTakToeGame.DeadlineNotPassed.selector);
        game.claimTimeout(id);
        vm.prank(alice);
        game.commitMove(id, commitment);
        vm.warp(game.gameProgress(id).deadline + 1);
        vm.prank(alice);
        vm.expectRevert(ITikTakToeGame.ActionExpired.selector);
        game.revealMove(id, move);
        vm.prank(alice);
        vm.expectRevert(ITikTakToeGame.NotAPlayer.selector);
        game.claimTimeout(id);
        vm.prank(bob);
        game.claimTimeout(id);
        assertEq(game.totalEscrow(), 0);
    }

    function test_WinningClaimRejectsForgedBoardPlayerTranscriptAndProof() public {
        (uint256 id, ITikTakToeGame.Move[] memory moves, ProofData memory proof) = _winningGame();
        vm.startPrank(alice);
        proof.publicSignals[1] = 2;
        vm.expectRevert(ITikTakToeGame.InvalidMoveSequence.selector);
        game.revealAndClaimWin(id, moves, proof.a, proof.b, proof.c, proof.publicSignals);
        proof.publicSignals[1] = 0;
        proof.publicSignals[10] = 1;
        vm.expectRevert(ITikTakToeGame.PlayerMismatch.selector);
        game.revealAndClaimWin(id, moves, proof.a, proof.b, proof.c, proof.publicSignals);
        proof.publicSignals[10] = 0;
        moves[0].salt = bytes32(uint256(999));
        vm.expectRevert(ITikTakToeGame.InvalidMoveSequence.selector);
        game.revealAndClaimWin(id, moves, proof.a, proof.b, proof.c, proof.publicSignals);
        moves[0].salt = bytes32(uint256(1));
        ProofData memory other = _loadProof("player0_wins_col0");
        proof.a = other.a;
        vm.expectRevert(ITikTakToeGame.InvalidProof.selector);
        game.revealAndClaimWin(id, moves, proof.a, proof.b, proof.c, proof.publicSignals);
        vm.stopPrank();
        assertEq(game.totalEscrow(), 10 ether);
    }

    function test_OnlyRecordedWinnerMayClaim() public {
        (uint256 id, ITikTakToeGame.Move[] memory moves, ProofData memory proof) = _winningGame();
        vm.prank(bob);
        vm.expectRevert(ITikTakToeGame.PlayerMismatch.selector);
        game.revealAndClaimWin(id, moves, proof.a, proof.b, proof.c, proof.publicSignals);
    }

    function testFuzz_EscrowIsolation(uint96 firstStake, uint96 secondStake) public {
        uint256 first = bound(uint256(firstStake), 1, 100 ether);
        uint256 second = bound(uint256(secondStake), 1, 100 ether);
        vm.prank(alice);
        game.wrap{value: first + second}();
        vm.prank(bob);
        game.wrap{value: second}();
        vm.startPrank(alice);
        uint256 unjoined = game.createGame(bob, first);
        uint256 joined = game.createGame(bob, second);
        vm.stopPrank();
        vm.prank(bob);
        game.joinGame(joined);
        assertEq(game.totalEscrow(), first + second * 2);
        vm.prank(alice);
        game.cancelGame(unjoined);
        assertEq(game.totalEscrow(), second * 2);
        assertEq(game.balanceOf(address(game)), game.totalEscrow());
        vm.warp(game.gameProgress(joined).deadline + 1);
        vm.prank(bob);
        game.claimTimeout(joined);
        assertEq(game.totalEscrow(), 0);
        assertEq(game.balanceOf(address(game)), 0);
        assertEq(game.balanceOf(alice), first);
        assertEq(game.balanceOf(bob), second * 2);
        assertEq(address(game).balance, game.totalSupply());
    }

    function test_CommitmentDomainSeparatesGameChainAndProxy() public {
        uint256 id = _create(true);
        ITikTakToeGame.Move memory move = _move(0, 0);
        bytes32 commitment = game.moveCommitment(id, move);
        assertEq(
            commitment,
            keccak256(
                abi.encode(
                    block.chainid, address(game), id, move.row, move.col, move.player, move.salt
                )
            )
        );
        assertNotEq(commitment, game.moveCommitment(id + 1, move));
        vm.chainId(block.chainid + 1);
        assertNotEq(commitment, game.moveCommitment(id, move));
        TikTakToeGame other = TikTakToeGame(
            payable(
                address(
                    new ERC1967Proxy(
                        address(new TikTakToeGame()),
                        abi.encodeCall(TikTakToeGame.initialize, (owner, address(verifier)))
                    )
                )
            )
        );
        assertNotEq(game.moveCommitment(id, move), other.moveCommitment(id, move));
    }

    function test_InitialisationAndUpgradeAuthority() public {
        uint256 id = _create(true);
        vm.expectRevert();
        game.initialize(owner, address(verifier));
        TikTakToeGame implementation = new TikTakToeGame();
        vm.expectRevert();
        implementation.initialize(owner, address(verifier));
        vm.prank(alice);
        vm.expectRevert();
        game.upgradeToAndCall(address(implementation), "");
        vm.prank(owner);
        game.upgradeToAndCall(address(implementation), "");
        assertEq(game.owner(), owner);
        assertTrue(game.gameProgress(id).joined);
        assertEq(game.totalEscrow(), 10 ether);
        _play(id, _move(0, 0));
    }

    function test_UnwrapCallbackCannotSpendBurnedTokensAndFailureRollsBack() public {
        WithdrawalRecipient recipient = new WithdrawalRecipient(game);
        vm.deal(address(this), 2 ether);
        recipient.deposit{value: 1 ether}();
        vm.expectRevert(ITikTakToeGame.EtherTransferFailed.selector);
        recipient.withdraw(1 ether, true);
        assertEq(game.balanceOf(address(recipient)), 1 ether);
        assertEq(address(game).balance, 1 ether);
        recipient.withdraw(1 ether, false);
        assertTrue(recipient.reentryRejected());
        assertEq(game.balanceOf(address(recipient)), 0);
        assertEq(address(recipient).balance, 1 ether);
        assertEq(game.totalSupply(), 0);
        assertEq(address(game).balance, 0);
    }

    function test_RejectsZeroOpponentAndVerifier() public {
        vm.prank(alice);
        game.wrap{value: 5 ether}();
        vm.prank(alice);
        vm.expectRevert(ITikTakToeGame.InvalidOpponent.selector);
        game.createGame(address(0), 5 ether);
        TikTakToeGame implementation = new TikTakToeGame();
        vm.expectRevert(ITikTakToeGame.InvalidVerifier.selector);
        new ERC1967Proxy(
            address(implementation), abi.encodeCall(TikTakToeGame.initialize, (owner, address(0)))
        );
    }
}

/// @notice Exercises a hostile Ether recipient at the withdrawal boundary.
contract WithdrawalRecipient {
    TikTakToeGame private immutable _game;
    bool private _refuseEther;
    uint256 private _amount;
    bool public reentryRejected;

    constructor(TikTakToeGame game) {
        _game = game;
    }

    function deposit() external payable {
        _game.wrap{value: msg.value}();
    }

    function withdraw(uint256 amount, bool refuseEther) external {
        _refuseEther = refuseEther;
        _amount = amount;
        _game.unwrap(amount);
    }

    receive() external payable {
        require(!_refuseEther);
        try _game.unwrap(_amount) {
            reentryRejected = false;
        } catch {
            reentryRejected = true;
        }
    }
}
