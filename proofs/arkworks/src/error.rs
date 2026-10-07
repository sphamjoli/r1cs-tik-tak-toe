use std::{error::Error as StdError, fmt};

/// Recoverable domain, assembly or cryptographic failure.
#[derive(Debug)]
pub enum Error {
    /// A cell is outside the circuit domain 0, 1, 2.
    InvalidCell(u8),
    /// A player is outside the circuit domain 0, 1.
    InvalidPlayer(u8),
    /// The required sixteen-point interpolation domain is unavailable.
    DomainUnavailable,
    /// An upstream operation returned an unexpected collection size.
    InvalidAssembly,
    /// The cryptographic backend failed; the source retains its diagnosis.
    Backend(Box<dyn StdError>),
    /// Canonical commitment encoding failed.
    Serialisation(ark_serialize::SerializationError),
}

impl Error {
    pub(crate) fn backend(error: impl StdError + 'static) -> Self {
        Self::Backend(Box::new(error))
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidCell(value) => write!(f, "invalid board cell: {value}"),
            Self::InvalidPlayer(value) => write!(f, "invalid player: {value}"),
            Self::DomainUnavailable => write!(f, "sixteen-point domain unavailable"),
            Self::InvalidAssembly => write!(f, "unexpected cryptographic assembly size"),
            Self::Backend(error) => write!(f, "cryptographic backend: {error}"),
            Self::Serialisation(error) => write!(f, "commitment serialisation: {error}"),
        }
    }
}

impl StdError for Error {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Backend(error) => Some(error.as_ref()),
            Self::Serialisation(error) => Some(error),
            _ => None,
        }
    }
}
