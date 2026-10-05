// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ITikTakToeVerifier} from "./ITikTakToeVerifier.sol";
import {ITikTakToeGame} from "./ITikTakToeGame.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title Tic-tac-toe game and wrapped Ether escrow
/// @notice Authenticates legal play before accepting a Groth16 winning-board proof.
contract TikTakToeGame is
    ITikTakToeGame,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ERC20Upgradeable
{
    ITikTakToeVerifier public verifier;
    mapping(uint256 => Game) public games;
    uint256 public gameCount;

    // Appended storage preserves the existing Game layout. Existing live games must be
    // settled before upgrading: their funding and move authors cannot be recovered.
    mapping(uint256 => Progress) private _progress;
    uint256 public totalEscrow;
    uint256 public constant ACTION_TIMEOUT = 1 days;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ITikTakToeGame
    function initialize(address owner, address verifierAddress) public initializer {
        require(verifierAddress.code.length > 0, InvalidVerifier());
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
        __ERC20_init("Wrapped Tic-Tac-Toe Ether", "WTTT");
        verifier = ITikTakToeVerifier(verifierAddress);
    }

    /// @inheritdoc ITikTakToeGame
    function gameToken() external view returns (address) {
        return address(this);
    }

    /// @inheritdoc ITikTakToeGame
    function gameProgress(uint256 gameId) external view returns (Progress memory) {
        return _progress[gameId];
    }

    /// @inheritdoc ITikTakToeGame
    function moveCommitment(uint256 gameId, Move calldata move) external view returns (bytes32) {
        return _commitment(gameId, move);
    }

    /// @inheritdoc ITikTakToeGame
    function createGame(address opponent, uint256 stake) external returns (uint256) {
        require(stake > 0 && stake <= type(uint256).max / 2, MustStakeTokens());
        require(opponent != address(0) && opponent != address(this), InvalidOpponent());
        require(opponent != msg.sender, CannotPlayYourself());
        require(balanceOf(msg.sender) >= stake, InsufficientBalance());
        _transfer(msg.sender, address(this), stake);
        totalEscrow += stake;

        uint256 gameId = gameCount++;
        Game storage current = games[gameId];
        current.player0 = msg.sender;
        current.player1 = opponent;
        current.stake = stake;
        current.active = true;
        Progress storage progress = _progress[gameId];
        for (uint256 i = 0; i < 9; i++) {
            progress.board[i] = 2;
        }
        emit GameCreated(gameId, msg.sender, opponent, stake);
        return gameId;
    }

    /// @inheritdoc ITikTakToeGame
    function joinGame(uint256 gameId) external {
        Game storage current = games[gameId];
        Progress storage progress = _progress[gameId];
        require(current.active, GameNotActive());
        require(msg.sender == current.player1, NotAPlayer());
        require(!progress.joined, AlreadyJoined());
        require(balanceOf(msg.sender) >= current.stake, InsufficientBalance());
        progress.joined = true;
        progress.deadline = block.timestamp + ACTION_TIMEOUT;
        totalEscrow += current.stake;
        _transfer(msg.sender, address(this), current.stake);
        emit GameJoined(gameId, msg.sender);
    }

    /// @inheritdoc ITikTakToeGame
    function commitMove(uint256 gameId, bytes32 commitment) external {
        Game storage current = games[gameId];
        Progress storage progress = _progress[gameId];
        _requireLiveTurn(current, progress);
        require(progress.revealedCount == current.moveCount, MovesNotRevealed());
        require(current.moveCount < 9, InvalidMove());
        require(msg.sender == _player(current, current.moveCount % 2), NotYourTurn());
        require(commitment != bytes32(0), InvalidMove());
        current.moveCommitments.push(commitment);
        current.moveCount++;
        progress.deadline = block.timestamp + ACTION_TIMEOUT;
        emit MoveCommitted(gameId, current.moveCount, commitment);
    }

    /// @inheritdoc ITikTakToeGame
    function revealMove(uint256 gameId, Move calldata move) external {
        Game storage current = games[gameId];
        Progress storage progress = _progress[gameId];
        _requireLiveTurn(current, progress);
        require(progress.revealedCount < current.moveCount, InvalidMoveSequence());
        uint8 player = progress.revealedCount % 2;
        require(msg.sender == _player(current, player), NotYourTurn());
        require(move.player == player, PlayerMismatch());
        require(move.row < 3 && move.col < 3, InvalidMove());
        require(
            _commitment(gameId, move) == current.moveCommitments[progress.revealedCount],
            InvalidMoveSequence()
        );
        uint256 position = uint256(move.row) * 3 + move.col;
        require(progress.board[position] == 2, InvalidMove());
        progress.board[position] = player;
        progress.revealedCount++;
        progress.deadline = block.timestamp + ACTION_TIMEOUT;
        emit MoveRevealed(gameId, progress.revealedCount, move.row, move.col, player);

        if (_hasWon(progress.board, player)) {
            progress.outcome = player + 1;
        } else if (progress.revealedCount == 9) {
            progress.outcome = 3;
            _refundDraw(gameId, current);
        }
    }

    /// @inheritdoc ITikTakToeGame
    function revealAndClaimWin(
        uint256 gameId,
        Move[] calldata moves,
        uint256[2] memory proofA,
        uint256[2][2] memory proofB,
        uint256[2] memory proofC,
        uint256[11] memory publicSignals
    )
        external
    {
        Game storage current = games[gameId];
        Progress storage progress = _progress[gameId];
        require(current.active, GameNotActive());
        require(progress.joined, GameNotJoined());
        require(msg.sender == current.player0 || msg.sender == current.player1, NotAPlayer());
        // Public signals are [has_won, board (row-major), player]. A valid proof
        // of the detector returning zero is not a proof of victory.
        require(publicSignals[0] == 1, InvalidProof());
        require(progress.revealedCount == current.moveCount, MovesNotRevealed());
        require(progress.outcome == 1 || progress.outcome == 2, NoWinningBoard());
        uint256 player = progress.outcome - 1;
        require(
            publicSignals[10] == player && msg.sender == _player(current, player), PlayerMismatch()
        );
        require(moves.length == current.moveCount, InvalidMoveSequence());
        for (uint256 i = 0; i < moves.length; i++) {
            require(
                _commitment(gameId, moves[i]) == current.moveCommitments[i], InvalidMoveSequence()
            );
        }
        for (uint256 i = 0; i < 9; i++) {
            require(progress.board[i] == publicSignals[i + 1], InvalidMoveSequence());
        }
        require(verifier.verifyProof(proofA, proofB, proofC, publicSignals), InvalidProof());
        uint256 payout = _award(current, msg.sender);
        emit WinClaimed(gameId, msg.sender, payout);
    }

    /// @inheritdoc ITikTakToeGame
    function cancelGame(uint256 gameId) external {
        Game storage current = games[gameId];
        require(current.active, GameNotActive());
        require(msg.sender == current.player0 || msg.sender == current.player1, NotAPlayer());
        require(!_progress[gameId].joined, AlreadyJoined());
        current.active = false;
        totalEscrow -= current.stake;
        _transfer(address(this), current.player0, current.stake);
        emit GameCancelled(gameId, msg.sender);
    }

    /// @inheritdoc ITikTakToeGame
    function claimTimeout(uint256 gameId) external {
        Game storage current = games[gameId];
        Progress storage progress = _progress[gameId];
        require(current.active, GameNotActive());
        require(progress.joined, GameNotJoined());
        require(progress.outcome == 0, GameFinished());
        require(block.timestamp > progress.deadline, DeadlineNotPassed());
        // The revealed count identifies the player who owes either the next
        // commitment or its reveal. A commitment never passes the turn alone.
        address winner = _player(current, 1 - progress.revealedCount % 2);
        require(msg.sender == winner, NotAPlayer());
        uint256 payout = _award(current, winner);
        emit TimeoutClaimed(gameId, winner, payout);
    }

    /// @inheritdoc ITikTakToeGame
    function wrap() external payable {
        require(msg.value > 0, MustStakeTokens());
        _mint(msg.sender, msg.value);
        emit Wrapped(msg.sender, msg.value);
    }

    /// @inheritdoc ITikTakToeGame
    function unwrap(uint256 amount) external {
        require(amount > 0, MustStakeTokens());
        require(balanceOf(msg.sender) >= amount, InsufficientBalance());
        _burn(msg.sender, amount);
        emit Unwrapped(msg.sender, amount);
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, EtherTransferFailed());
    }

    function _requireLiveTurn(Game storage current, Progress storage progress) private view {
        require(current.active, GameNotActive());
        require(progress.joined, GameNotJoined());
        require(progress.outcome == 0, GameFinished());
        require(block.timestamp <= progress.deadline, ActionExpired());
    }

    function _player(Game storage current, uint256 player) private view returns (address) {
        return player == 0 ? current.player0 : current.player1;
    }

    function _commitment(uint256 gameId, Move calldata move) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid, address(this), gameId, move.row, move.col, move.player, move.salt
            )
        );
    }

    // Bounded to the eight lines of a 3x3 board. Needed to stop legal play at
    // the first win; the Groth16 proof still authenticates the final claim.
    function _hasWon(uint256[9] memory board, uint256 player) private pure returns (bool) {
        for (uint256 i = 0; i < 3; i++) {
            if (board[i * 3] == player && board[i * 3 + 1] == player && board[i * 3 + 2] == player)
            {
                return true;
            }
            if (board[i] == player && board[i + 3] == player && board[i + 6] == player) return true;
        }
        return (board[0] == player && board[4] == player && board[8] == player)
            || (board[2] == player && board[4] == player && board[6] == player);
    }

    function _award(Game storage current, address winner) private returns (uint256 payout) {
        current.active = false;
        current.winner = winner;
        payout = current.stake * 2;
        totalEscrow -= payout;
        _transfer(address(this), winner, payout);
    }

    function _refundDraw(uint256 gameId, Game storage current) private {
        current.active = false;
        totalEscrow -= current.stake * 2;
        _transfer(address(this), current.player0, current.stake);
        _transfer(address(this), current.player1, current.stake);
        emit GameDrawn(gameId);
    }

    /// @notice Only the owner may upgrade the implementation.
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Wraps received Ether at one token unit per wei.
    receive() external payable {
        _mint(msg.sender, msg.value);
        emit Wrapped(msg.sender, msg.value);
    }
}
