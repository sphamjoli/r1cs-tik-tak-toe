// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ITikTakToeGame
/// @author brianspha
/// @notice Interface for legal tic-tac-toe play with Groth16 winning-board proofs
/// @dev Players alternate commits and reveals. Boards are public. Funded games escrow
///      two stakes; a missed one-day action deadline forfeits the pot to the other player.
///      Draws refund both stakes. Ownership controls the UUPS upgrade authority.
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

    /// @notice Authenticated play and funding tracked separately from the existing Game layout.
    /// @param joined Whether player1 has deposited exactly one stake
    /// @param revealedCount Number of legal revealed moves (at most nine)
    /// @param outcome Zero while playing, one for player0 win, two for player1 win, three for draw
    /// @param deadline Latest timestamp for the current action, inclusive
    /// @param board Row-major cells (0=player0, 1=player1, 2=empty)
    struct Progress {
        bool joined;
        uint8 revealedCount;
        uint8 outcome;
        uint256 deadline;
        uint256[9] board;
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

    /// @notice Opponent must be a non-zero external participant.
    error InvalidOpponent();
    /// @notice Verifier must have deployed code.
    error InvalidVerifier();
    /// @notice The opponent already funded this game.
    error AlreadyJoined();
    /// @notice Both stakes must be deposited before play or settlement.
    error GameNotJoined();
    /// @notice The caller does not own this turn.
    error NotYourTurn();
    /// @notice Legal play has ended with a winning board or draw.
    error GameFinished();
    /// @notice The current action deadline has passed.
    error ActionExpired();
    /// @notice A timeout may only be claimed strictly after the deadline.
    error DeadlineNotPassed();
    /// @notice The revealed board has no winner.
    error NoWinningBoard();
    /// @notice Ether withdrawal failed and the burn was rolled back.
    error EtherTransferFailed();

    /// @notice Emitted when player1 funds a game.
    /// @param gameId Funded game
    /// @param player1 Funding participant
    event GameJoined(uint256 indexed gameId, address indexed player1);
    /// @notice Emitted for a legal revealed move.
    /// @param gameId Game identifier
    /// @param moveNumber One-based move number
    /// @param row Board row
    /// @param col Board column
    /// @param player Player identifier
    event MoveRevealed(
        uint256 indexed gameId, uint8 moveNumber, uint8 row, uint8 col, uint8 player
    );
    /// @notice Emitted after a draw refunds both stakes.
    /// @param gameId Settled game
    event GameDrawn(uint256 indexed gameId);
    /// @notice Emitted after a missed action forfeits the two-stake pot.
    /// @param gameId Settled game
    /// @param winner Participant not responsible for the missed action
    /// @param payout Wrapped Ether paid in token units
    event TimeoutClaimed(uint256 indexed gameId, address indexed winner, uint256 payout);

    /// @notice Initialises a fresh proxy once.
    /// @dev Upgrades of existing games require prior settlement; old commitment authors and
    ///      funding cannot be reconstructed. Invalid verifier addresses revert.
    /// @param owner Upgrade authority
    /// @param verifierAddress Deployed Groth16 detector verifier
    function initialize(address owner, address verifierAddress) external;

    /// @notice Returns funding, legal board and action deadline for a game.
    /// @param gameId Game identifier
    /// @return progress Recorded game progress; nonexistent games return zeroed fields
    function gameProgress(uint256 gameId) external view returns (Progress memory progress);

    /// @notice Computes the canonical domain-bound commitment for a move.
    /// @dev keccak256(abi.encode(chain ID, proxy address, game ID, uint8 row, uint8 col,
    ///      uint8 player, bytes32 salt)). Other games, chains and proxies use different domains.
    /// @param gameId Game identifier
    /// @param move Move and salt to commit
    /// @return commitment Canonical commitment hash
    function moveCommitment(
        uint256 gameId,
        Move calldata move
    )
        external
        view
        returns (bytes32 commitment);

    /// @notice Reveals the current player's pending commitment.
    /// @dev Requires both stakes, correct turn and player ID, matching commitment, an empty
    ///      cell and an unexpired action deadline. Reveals after a win are rejected. A draw
    ///      closes the game and refunds both stakes; otherwise the next action gets one day.
    /// @param gameId Game identifier
    /// @param move Coordinates, authenticated player ID and commitment salt
    function revealMove(uint256 gameId, Move calldata move) external;

    /// @notice Claims both stakes when the other player misses the action deadline.
    /// @dev Only the non-defaulting player may call, strictly after the deadline. A pending
    ///      reveal is owed by its committer. Winning boards cannot be settled by timeout.
    /// @param gameId Funded, active game with no winning board
    function claimTimeout(uint256 gameId) external;

    /// @notice Game is not active or has ended
    error GameNotActive();

    /// @notice Caller is not a participant in this game
    error NotAPlayer();

    /// @notice Player claiming win does not match proof
    error PlayerMismatch();

    /// @notice ZK proof verification failed
    error InvalidProof();

    /// @notice Cannot create game against yourself
    error CannotPlayYourself();

    /// @notice Must stake non-zero amount of tokens
    error MustStakeTokens();

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

    /// @notice Join an existing game by matching stake exactly once.
    /// @dev Starts player0's one-day action deadline; duplicate deposits revert.
    /// @param gameId Game to join
    function joinGame(uint256 gameId) external;

    /// @notice Commit to a move without revealing it
    /// @dev Use moveCommitment for the canonical chain-, proxy- and game-bound hash.
    ///      Requires both stakes, alternating turns, the prior reveal, fewer than nine moves
    ///      and an unexpired action deadline. A commit grants its owner one day to reveal.
    /// @param gameId Game identifier
    /// @param commitment Hash of move data
    function commitMove(uint256 gameId, bytes32 commitment) external;

    /// @notice Confirms the revealed transcript and claims victory with a ZK proof
    /// @dev All moves must already be legally revealed. Requires both stakes, a winning board,
    ///      has_won=1, matching commitments, recorded board and authenticated winning caller.
    ///      The proof must verify. Closes the game and pays exactly this game's two stakes.
    /// @param gameId Game identifier
    /// @param moves Array of revealed moves in chronological order
    /// @param a Proof component A
    /// @param b Proof component B
    /// @param c Proof component C
    /// @param publicSignals [has_won, nine row-major board cells, player ID]
    function revealAndClaimWin(
        uint256 gameId,
        Move[] calldata moves,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[11] memory publicSignals
    )
        external;

    /// @notice Cancel an unjoined game and refund its creator's stake.
    /// @dev Either named player may cancel before funding; unrelated games do not affect this.
    /// @param gameId Game to cancel
    function cancelGame(uint256 gameId) external;

    /// @notice Wrap ETH into game tokens at 1:1 ratio
    function wrap() external payable;

    /// @notice Unwrap game tokens back to ETH at 1:1 ratio
    /// @param amount Amount of tokens to unwrap
    function unwrap(uint256 amount) external;
}
