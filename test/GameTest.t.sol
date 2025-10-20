// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TikTakToeGame} from "../src/TikTakToeGame.sol";
import {Groth16Verifier} from "../src/TikTakToeVerifier.sol";
import {ITikTakToeGame} from "../src/ITikTakToeGame.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @notice We keeping the tests simple
/// @dev PLEASE ENSURE YOU RUN make all before running any tests
contract GameTest is Test {
    using stdJson for string;

    TikTakToeGame public game;
    Groth16Verifier public verifier;
    address public proxy;
    Options public options;

    uint256 public immutable DEFAULT_TOKEN_BALANCE = 1000 ether;
    address public owner;
    address public alice;
    address public bob;

    struct ProofData {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
        uint256[11] publicSignals;
    }

    event GameCreated(
        uint256 indexed gameId, address indexed player0, address indexed player1, uint256 stake
    );
    event WinClaimed(uint256 indexed gameId, address indexed winner, uint256 payout);
    event MoveCommitted(uint256 indexed gameId, uint8 moveNumber, bytes32 commitment);

    function setUp() public noGasMetering {
        owner = _createUser("Owner");
        alice = _createUser("Alice");
        bob = _createUser("Bob");

        vm.startPrank(owner);
        options.unsafeSkipAllChecks = true;
        verifier = new Groth16Verifier();

        proxy = Upgrades.deployUUPSProxy(
            "TikTakToeGame.sol",
            abi.encodeCall(TikTakToeGame.initialize, (owner, address(verifier))),
            options
        );
        game = TikTakToeGame(payable(proxy));
        vm.stopPrank();
    }

    function _createUser(string memory name) internal returns (address payable user) {
        user = payable(makeAddr(name));
        vm.deal({account: user, newBalance: DEFAULT_TOKEN_BALANCE});
        vm.label(user, name);
    }

    function test_Player0WinsRow0() public {
        _runFixtureTest("player0_wins_row0", alice);
    }

    function test_Player0WinsCol0() public {
        _runFixtureTest("player0_wins_col0", alice);
    }

    function test_Player0WinsDiag() public {
        _runFixtureTest("player0_wins_diag", alice);
    }

    function test_Player1WinsRow0() public {
        _runFixtureTest("player1_wins_row0", bob);
    }

    function _runFixtureTest(string memory fixtureName, address expectedWinner) internal {
        vm.prank(alice);
        game.wrap{value: 10 ether}();
        vm.prank(bob);
        game.wrap{value: 10 ether}();

        vm.prank(alice);
        uint256 gameId = game.createGame(bob, 5 ether);
        vm.prank(bob);
        game.joinGame(gameId);

        ITikTakToeGame.Move[] memory moves = _loadMoves(fixtureName);

        for (uint256 i = 0; i < moves.length; i++) {
            bytes32 commitment = keccak256(
                abi.encode(
                    uint8(moves[i].row),
                    uint8(moves[i].col),
                    uint8(moves[i].player),
                    bytes32(moves[i].salt)
                )
            );
            vm.prank(i % 2 == 0 ? alice : bob);
            game.commitMove(gameId, commitment);
        }

        ProofData memory proof = _loadProof(fixtureName);

        vm.prank(expectedWinner);
        game.revealAndClaimWin(gameId, moves, proof.a, proof.b, proof.c, proof.publicSignals);

        (,,, address winner, bool active,) = game.games(gameId);
        assertEq(winner, expectedWinner);
        assertFalse(active);
    }

    function _loadMoves(string memory fixtureName)
        internal
        view
        returns (ITikTakToeGame.Move[] memory)
    {
        string memory movesPath =
            string.concat(vm.projectRoot(), "/test/fixtures/", fixtureName, "/moves.json");
        string memory movesJson = vm.readFile(movesPath);
        uint256[][] memory rawMoves = abi.decode(movesJson.parseRaw("$"), (uint256[][]));

        ITikTakToeGame.Move[] memory moves = new ITikTakToeGame.Move[](rawMoves.length);
        for (uint256 i = 0; i < rawMoves.length; i++) {
            moves[i] = ITikTakToeGame.Move({
                row: uint8(rawMoves[i][0]),
                col: uint8(rawMoves[i][1]),
                player: uint8(rawMoves[i][2]),
                salt: bytes32(i + 1)
            });
        }
        return moves;
    }

    function _loadProof(string memory fixtureName) internal view returns (ProofData memory) {
        string memory base = string.concat(vm.projectRoot(), "/test/fixtures/", fixtureName);
        string memory calldataJson = vm.readFile(string.concat(base, "/calldata.json"));

        string[] memory aStr = abi.decode(stdJson.parseRaw(calldataJson, ".a"), (string[]));
        string[][] memory bStr = abi.decode(stdJson.parseRaw(calldataJson, ".b"), (string[][]));
        string[] memory cStr = abi.decode(stdJson.parseRaw(calldataJson, ".c"), (string[]));
        string[] memory pubStr =
            abi.decode(stdJson.parseRaw(calldataJson, ".publicSignals"), (string[]));

        ProofData memory proof;
        proof.a = [vm.parseUint(aStr[0]), vm.parseUint(aStr[1])];

        proof.b[0][0] = vm.parseUint(bStr[0][0]);
        proof.b[0][1] = vm.parseUint(bStr[0][1]);
        proof.b[1][0] = vm.parseUint(bStr[1][0]);
        proof.b[1][1] = vm.parseUint(bStr[1][1]);

        proof.c = [vm.parseUint(cStr[0]), vm.parseUint(cStr[1])];

        require(pubStr.length == 11, "publicSignals length");
        for (uint256 i = 0; i < 11; i++) {
            proof.publicSignals[i] = vm.parseUint(pubStr[i]);
        }
        return proof;
    }
}
