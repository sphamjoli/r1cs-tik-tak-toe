// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITikTakToeVerifier} from "./ITikTakToeVerifier.sol";
import {ITikTakToeGame} from "./ITikTakToeGame.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract
    /// @param owner The address that will receive ownership
    /// @param _verifier The address of the deployed Groth16 verifier
    function initialize(address owner, address _verifier) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
        __ERC20_init("Wrapped Tic-Tac-Toe Ether", "WTTT");
        verifier = ITikTakToeVerifier(_verifier);
    }

    /// @inheritdoc ITikTakToeGame
    function gameToken() external view returns (address) {
        return address(this);
    }

    /// @inheritdoc ITikTakToeGame
    function createGame(address opponent, uint256 stake) external returns (uint256) {
        require(stake > 0, MustStakeTokens());
        require(opponent != msg.sender, CannotPlayYourself());
        require(balanceOf(msg.sender) >= stake, InsufficientBalance());

        _transfer(msg.sender, address(this), stake);

        uint256 newGameId = gameCount++;
        Game storage newGame = games[newGameId];
        newGame.player0 = msg.sender;
        newGame.player1 = opponent;
        newGame.stake = stake;
        newGame.active = true;
        newGame.winner = address(0);
        newGame.moveCount = 0;

        emit GameCreated(newGameId, msg.sender, opponent, stake);
        return newGameId;
    }

    /// @inheritdoc ITikTakToeGame
    function joinGame(uint256 gameId) external {
        Game storage currentGame = games[gameId];
        require(currentGame.active, GameNotActive());
        require(msg.sender == currentGame.player1, NotAPlayer());
        require(balanceOf(msg.sender) >= currentGame.stake, InsufficientBalance());

        _transfer(msg.sender, address(this), currentGame.stake);
    }

    /// @inheritdoc ITikTakToeGame
    function commitMove(uint256 gameId, bytes32 moveCommitment) external {
        Game storage currentGame = games[gameId];
        require(currentGame.active, GameNotActive());
        require(
            msg.sender == currentGame.player0 || msg.sender == currentGame.player1, NotAPlayer()
        );

        currentGame.moveCommitments.push(moveCommitment);
        currentGame.moveCount++;

        emit MoveCommitted(gameId, currentGame.moveCount, moveCommitment);
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
        Game storage currentGame = games[gameId];

        require(currentGame.active, GameNotActive());
        require(
            msg.sender == currentGame.player0 || msg.sender == currentGame.player1, NotAPlayer()
        );
        require(currentGame.winner == address(0), WinnerAlreadyDeclared());
        require(moves.length == currentGame.moveCommitments.length, InvalidMoveSequence());

        for (uint256 moveIndex = 0; moveIndex < moves.length; moveIndex++) {
            bytes32 expectedCommitment = keccak256(
                abi.encode(
                    moves[moveIndex].row,
                    moves[moveIndex].col,
                    moves[moveIndex].player,
                    moves[moveIndex].salt
                )
            );
            require(
                expectedCommitment == currentGame.moveCommitments[moveIndex], InvalidMoveSequence()
            );
        }

        uint256[9] memory reconstructedBoard = _reconstructBoard(moves);
        // Public signals structure from circuit:
        // [1-9]: board (9 cells)
        // [10]: player
        // Note: has_won is NOT in public signals (it's signal 12 in witness but not exported)
        // Verify reconstructed board matches circuit output (offset by 1 due to mystery signal)
        for (uint256 i = 0; i < 9; i++) {
            require(reconstructedBoard[i] == publicSignals[i + 1], InvalidMoveSequence());
        }

        // Verify player from circuit matches caller
        uint256 circuitPlayer = publicSignals[10];
        require(circuitPlayer == 0 || circuitPlayer == 1, InvalidProof());

        if (circuitPlayer == 0) {
            require(msg.sender == currentGame.player0, PlayerMismatch());
        } else {
            require(msg.sender == currentGame.player1, PlayerMismatch());
        }

        // Verify the zero-knowledge proof
        // The proof verification guarantees that has_won=1 was correctly computed by the circuit
        require(verifier.verifyProof(proofA, proofB, proofC, publicSignals), InvalidProof());

        currentGame.winner = msg.sender;
        currentGame.active = false;

        uint256 payoutAmount = currentGame.stake * 2;
        _transfer(address(this), msg.sender, payoutAmount);

        emit WinClaimed(gameId, msg.sender, payoutAmount);
    }

    /// @inheritdoc ITikTakToeGame
    function cancelGame(uint256 gameId) external {
        Game storage currentGame = games[gameId];

        require(currentGame.active, GameNotActive());
        require(
            msg.sender == currentGame.player0 || msg.sender == currentGame.player1, NotAPlayer()
        );
        require(balanceOf(address(this)) < currentGame.stake * 2, GameNotActive());

        currentGame.active = false;
        _transfer(address(this), currentGame.player0, currentGame.stake);
        emit GameCancelled(gameId, msg.sender);
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
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");

        emit Unwrapped(msg.sender, amount);
    }

    /// @notice Reconstruct board state from move sequence
    /// @param moves Array of revealed moves
    /// @return board Array of 9 cell values (0=player0, 1=player1, 2=empty)
    function _reconstructBoard(Move[] calldata moves) internal pure returns (uint256[9] memory) {
        uint256[9] memory board;
        for (uint256 i = 0; i < 9; i++) {
            board[i] = 2;
        }

        for (uint256 moveIndex = 0; moveIndex < moves.length; moveIndex++) {
            require(moves[moveIndex].row < 3 && moves[moveIndex].col < 3, InvalidMove());
            require(moves[moveIndex].player < 2, InvalidMove());

            uint256 boardPosition = moves[moveIndex].row * 3 + moves[moveIndex].col;
            require(board[boardPosition] == 2, InvalidMove());
            board[boardPosition] = moves[moveIndex].player;
        }

        return board;
    }

    /// @notice Authorize contract upgrades
    /// @dev Only the owner can authorize upgrades
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Receive ETH and wrap into tokens
    receive() external payable {
        _mint(msg.sender, msg.value);
        emit Wrapped(msg.sender, msg.value);
    }
}
