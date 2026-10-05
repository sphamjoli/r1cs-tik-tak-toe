// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ITikTakToeVerifier
/// @author brianspha
/// @notice Interface for ZK proof verification of tic-tac-toe win conditions
interface ITikTakToeVerifier {
    /// @notice Verifies the Groth16 board detector relation.
    /// @dev Non-winning boards also have valid proofs.
    ///      Callers claiming a win must require input[0]=1.
    /// @param a First component of the proof
    /// @param b Second component of the proof
    /// @param c Third component of the proof
    /// @param input Public signals: [has_won, nine row-major board cells, player]
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
