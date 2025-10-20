// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ITikTakToeVerifier
/// @author brianspha
/// @notice Interface for ZK proof verification of tic-tac-toe win conditions
interface ITikTakToeVerifier {
    /// @notice Verifies a Groth16 proof for a tic-tac-toe win
    /// @param a First component of the proof
    /// @param b Second component of the proof
    /// @param c Third component of the proof
    /// @param input Public signals: board state (9 cells) + player (1) + has_won (1)
    /// @return True if proof is valid, false otherwise
    function verifyProof(
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[11] memory input
    )
        external
        view
        returns (bool);
}
