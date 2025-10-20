// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ITikTakToeGame
/// @author brianspha
/// @notice Interface for privacy-preserving tic-tac-toe with zero-knowledge proofs
/// @dev Implements commit-reveal scheme to ensure both players agree on move sequence
interface ITikTakToeGame {
    /// @notice Game state tracking players, stakes, moves, and outcome
    /// @param player0 Address of player 0 (game creator)
    /// @param player1 Address of player 1 (opponent)
    /// @param stake Amount staked by each player in game tokens
    /// @param winner Address of winner, zero address if game ongoing
    /// @param active Whether game accepts moves and claims
    /// @param moveCount Total number of committed moves
    /// @param moveCommitments Array of move commitment hashes
    struct Game {
        address player0;
        address player1;
        uint256 stake;
        address winner;
        bool active;
        uint8 moveCount;
        bytes32[] moveCommitments;
    }

    /// @notice Move data for commit-reveal scheme
    /// @param row Board row (0-2)
    /// @param col Board column (0-2)
    /// @param player Player making move (0 or 1)
    /// @param salt Random salt for commitment
    struct Move {
        uint8 row;
        uint8 col;
        uint8 player;
        bytes32 salt;
    }

    /// @notice Emitted when a new game is created
    /// @param gameId Unique identifier for the game
    /// @param player0 Address of game creator
    /// @param player1 Address of opponent
    /// @param stake Amount staked by player0 in game tokens
    event GameCreated(
        uint256 indexed gameId, address indexed player0, address indexed player1, uint256 stake
    );

    /// @notice Emitted when a player claims victory with valid proof
    /// @param gameId Game identifier
    /// @param winner Address receiving payout
    /// @param payout Total amount transferred to winner
    event WinClaimed(uint256 indexed gameId, address indexed winner, uint256 payout);

    /// @notice Emitted when a game is cancelled
    /// @param gameId Game identifier
    /// @param canceller Address that cancelled the game
    event GameCancelled(uint256 indexed gameId, address indexed canceller);

    /// @notice Emitted when ETH is wrapped into game tokens
    /// @param account Address receiving tokens
    /// @param amount Amount of tokens minted
    event Wrapped(address indexed account, uint256 amount);

    /// @notice Emitted when game tokens are unwrapped to ETH
    /// @param account Address receiving ETH
    /// @param amount Amount of ETH withdrawn
    event Unwrapped(address indexed account, uint256 amount);

    /// @notice Emitted when a move commitment is recorded
    /// @param gameId Game identifier
    /// @param moveNumber Sequential move number
    /// @param commitment Hash of move data
    event MoveCommitted(uint256 indexed gameId, uint8 moveNumber, bytes32 commitment);

    /// @notice Game is not active or has ended
    error GameNotActive();

    /// @notice Caller is not a participant in this game
    error NotAPlayer();

    /// @notice Winner has already been declared for this game
    error WinnerAlreadyDeclared();

    /// @notice Player claiming win does not match proof
    error PlayerMismatch();

    /// @notice ZK proof verification failed
    error InvalidProof();

    /// @notice Cannot create game against yourself
    error CannotPlayYourself();

    /// @notice Must stake non-zero amount of tokens
    error MustStakeTokens();

    /// @notice Stake amount does not match required amount
    error StakeMismatch();

    /// @notice Insufficient token balance for operation
    error InsufficientBalance();

    /// @notice Move parameters are invalid
    error InvalidMove();

    /// @notice Revealed moves do not match commitments
    error InvalidMoveSequence();

    /// @notice Moves must be revealed before claiming win
    error MovesNotRevealed();

    /// @notice Total number of games created
    /// @return Current game count
    function gameCount() external view returns (uint256);

    /// @notice Address of ERC20 token used for stakes
    /// @return Game token address
    function gameToken() external view returns (address);

    /// @notice Create a new game with token stake
    /// @param opponent Address of player1
    /// @param stake Amount of tokens to stake
    /// @return gameId Unique identifier for created game
    function createGame(address opponent, uint256 stake) external returns (uint256);

    /// @notice Join an existing game by matching stake
    /// @param gameId Game to join
    function joinGame(uint256 gameId) external;

    /// @notice Commit to a move without revealing it
    /// @dev Commitment is keccak256(row, col, player, salt)
    /// @param gameId Game identifier
    /// @param moveCommitment Hash of move data
    function commitMove(uint256 gameId, bytes32 moveCommitment) external;

    /// @notice Reveal all moves and claim victory with ZK proof
    /// @dev Verifies move sequence matches commitments and board state matches proof
    /// @param gameId Game identifier
    /// @param moves Array of revealed moves in chronological order
    /// @param a Proof component A
    /// @param b Proof component B
    /// @param c Proof component C
    /// @param publicSignals Board state (9 cells) + player ID + has_won flag
    function revealAndClaimWin(
        uint256 gameId,
        Move[] calldata moves,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[11] memory publicSignals
    )
        external;

    /// @notice Cancel an inactive game and refund stake
    /// @param gameId Game to cancel
    function cancelGame(uint256 gameId) external;

    /// @notice Wrap ETH into game tokens at 1:1 ratio
    function wrap() external payable;

    /// @notice Unwrap game tokens back to ETH at 1:1 ratio
    /// @param amount Amount of tokens to unwrap
    function unwrap(uint256 amount) external;
}
