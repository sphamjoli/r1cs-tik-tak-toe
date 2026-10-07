use crate::Error;

const LINES: [[usize; 3]; 8] = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
];

/// A validated public player marker, either 0 or 1.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Player(u8);

impl Player {
    /// Validates the circuit's player domain.
    ///
    /// # Errors
    /// Returns [`Error::InvalidPlayer`] for a value other than 0 or 1.
    pub fn new(value: u8) -> Result<Self, Error> {
        if value > 1 {
            return Err(Error::InvalidPlayer(value));
        }
        Ok(Self(value))
    }

    /// Returns the public circuit encoding.
    pub fn marker(self) -> u8 {
        self.0
    }
}

/// Nine row-major cells: 0 and 1 are player marks; 2 is empty.
///
/// Validation establishes the cell domain, not legal move history.
///
/// ```
/// use tic_tac_toe_proof_boundary::{Board, Player};
/// let board = Board::new([0, 0, 0, 1, 1, 2, 2, 2, 2])?;
/// assert!(board.wins(Player::new(0)?));
/// assert!(!board.wins(Player::new(1)?));
/// # Ok::<(), tic_tac_toe_proof_boundary::Error>(())
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Board([u8; 9]);

impl Board {
    /// Validates all cells without imposing legal-play requirements.
    ///
    /// # Errors
    /// Returns [`Error::InvalidCell`] for the first cell exceeding 2.
    pub fn new(cells: [u8; 9]) -> Result<Self, Error> {
        for cell in cells {
            if cell > 2 {
                return Err(Error::InvalidCell(cell));
            }
        }
        Ok(Self(cells))
    }

    /// Borrows all nine cells in row-major order.
    pub fn cells(&self) -> &[u8; 9] {
        &self.0
    }

    /// Checks the detector's eight lines in bounded constant time.
    pub fn wins(&self, player: Player) -> bool {
        LINES
            .iter()
            .any(|line| line.iter().all(|&index| self.0[index] == player.0))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detector_matches_independent_oracle_on_entire_domain() -> Result<(), Error> {
        for encoding in 0..3u32.pow(9) {
            let mut remaining = encoding;
            let mut cells = [2; 9];
            for cell in &mut cells {
                *cell = (remaining % 3) as u8;
                remaining /= 3;
            }
            let board = Board::new(cells)?;
            for marker in 0..=1 {
                let row = (0..3).any(|r| (0..3).all(|c| cells[3 * r + c] == marker));
                let column = (0..3).any(|c| (0..3).all(|r| cells[3 * r + c] == marker));
                let diagonals = (0..3).all(|i| cells[4 * i] == marker)
                    || (0..3).all(|i| cells[2 + 2 * i] == marker);
                assert_eq!(board.wins(Player::new(marker)?), row || column || diagonals);
            }
        }
        Ok(())
    }

    #[test]
    fn rejects_invalid_domains() {
        assert!(matches!(Player::new(2), Err(Error::InvalidPlayer(2))));
        assert!(matches!(Board::new([3; 9]), Err(Error::InvalidCell(3))));
        assert!(matches!(Board::new([255; 9]), Err(Error::InvalidCell(255))));
    }
}
