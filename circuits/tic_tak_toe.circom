pragma circom 2.1.9;

include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/bitify.circom";

/// @title Tic-Tac-Toe Win Verification Circuit
/// @notice Computes whether the specified player has a winning line.
/// @dev Public signals are [has_won, nine row-major board cells, player]. Boards are public.
///      A valid proof may have has_won=0. Win claims must require has_won=1, authenticate
///      legal play and funding, and bind the public board and player to the recorded game.
///
/// Board encoding: Each cell ∈ {0, 1, 2} where:
///   - 0 = player 0's mark
///   - 1 = player 1's mark
///   - 2 = empty cell
///
/// Win conditions: A player wins by placing their mark in all cells of any:
///   - Horizontal row
///   - Vertical column
///   - Main diagonal (top-left to bottom-right)
///   - Anti-diagonal (top-right to bottom-left)
template CheckBoard(board_size) {
    signal input board[board_size][board_size];
    signal input player;
    signal output row_wins[board_size];
    signal output col_wins[board_size];
    signal output diag1_win;
    signal output diag2_win;

    component eq[board_size][board_size];

    signal row_products[board_size][board_size+1];
    signal col_products[board_size][board_size+1];

    signal diag1_products[board_size+1];
    signal diag2_products[board_size+1];

    for (var i = 0; i < board_size; i++) {
        for (var j = 0; j < board_size; j++) {
            eq[i][j] = IsEqual();
            eq[i][j].in[0] <== board[i][j];
            eq[i][j].in[1] <== player;
        }
    }

    for (var i = 0; i < board_size; i++) {
        row_products[i][0] <== 1;
        for (var j = 0; j < board_size; j++) {
            row_products[i][j+1] <== row_products[i][j] * eq[i][j].out;
        }
        row_wins[i] <== row_products[i][board_size];
    }

    for (var j = 0; j < board_size; j++) {
        col_products[j][0] <== 1;
        for (var i = 0; i < board_size; i++) {
            col_products[j][i+1] <== col_products[j][i] * eq[i][j].out;
        }
        col_wins[j] <== col_products[j][board_size];
    }

    diag1_products[0] <== 1;
    for (var i = 0; i < board_size; i++) {
        diag1_products[i+1] <== diag1_products[i] * eq[i][i].out;
    }
    diag1_win <== diag1_products[board_size];

    diag2_products[0] <== 1;
    for (var i = 0; i < board_size; i++) {
        diag2_products[i+1] <== diag2_products[i] * eq[i][board_size-1-i].out;
    }
    diag2_win <== diag2_products[board_size];
}

template IsNonZero() {
    signal input in;
    signal output out;
    component iz = IsZero();
    iz.in <== in;
    out <== 1 - iz.out;
}

template TikTakToe(board_size) {
    signal input board[board_size][board_size];
    signal input player;
    signal output has_won;

    // We need to constraint the player value
    // player ∈ {0,1}
    player * (player - 1) === 0;

    component decomp[board_size][board_size];
    signal b0[board_size][board_size];
    signal b1[board_size][board_size];

    for (var i = 0; i < board_size; i++) {
        for (var j = 0; j < board_size; j++) {
            decomp[i][j] = Num2Bits(2);
            decomp[i][j].in <== board[i][j];
            b0[i][j] <== decomp[i][j].out[0];
            b1[i][j] <== decomp[i][j].out[1];
            b0[i][j] * b1[i][j] === 0;
        }
    }

    component boardChecker = CheckBoard(board_size);
    boardChecker.board <== board;
    boardChecker.player <== player;

    signal win_accumulator[2*board_size+3];
    win_accumulator[0] <== 0;

    for (var i = 0; i < board_size; i++) {
        win_accumulator[i+1] <== win_accumulator[i] + boardChecker.row_wins[i];
    }
    for (var j = 0; j < board_size; j++) {
        win_accumulator[board_size + j + 1] <== win_accumulator[board_size + j] + boardChecker.col_wins[j];
    }
    win_accumulator[2*board_size + 1] <== win_accumulator[2*board_size] + boardChecker.diag1_win;
    win_accumulator[2*board_size + 2] <== win_accumulator[2*board_size + 1] + boardChecker.diag2_win;

    signal final_sum <== win_accumulator[2*board_size + 2];

    // has_won = 1 iff final_sum != 0
    component isNonZero = IsNonZero();
    isNonZero.in <== final_sum;
    has_won <== isNonZero.out;
}

component main { public [board, player] } = TikTakToe(3);
