.PHONY: all compile powers-of-tau setup verifier create-fixture generate-all-fixtures verify-fixture calldata-fixture calldata-all clean help

all: compile powers-of-tau setup verifier generate-all-fixtures calldata-all

compile:
	@echo "==> Compiling circuit..."
	npx circom circuits/tic_tak_toe.circom --r1cs --wasm --sym -l node_modules

powers-of-tau:
	@echo "==> Generating Powers of Tau..."
	npx snarkjs powersoftau new bn128 12 pot12_0000.ptau -v
	npx snarkjs powersoftau contribute pot12_0000.ptau pot12_0001.ptau --name="First contribution" -v -e="random entropy"
	npx snarkjs powersoftau contribute pot12_0001.ptau pot12_0002.ptau --name="Second contribution" -v -e="more random entropy"
	npx snarkjs powersoftau prepare phase2 pot12_0002.ptau pot12_final.ptau -v
	npx snarkjs powersoftau verify pot12_final.ptau

setup:
	@echo "==> Setting up circuit..."
	npx snarkjs groth16 setup tic_tak_toe.r1cs pot12_final.ptau circuit_0000.zkey
	npx snarkjs zkey contribute circuit_0000.zkey circuit_final.zkey --name="Circuit contribution" -v -e="circuit random entropy"
	npx snarkjs zkey verify tic_tak_toe.r1cs pot12_final.ptau circuit_final.zkey
	npx snarkjs zkey export verificationkey circuit_final.zkey verification_key.json

verifier:
	@echo "==> Generating Solidity verifier..."
	@mkdir -p src
	npx snarkjs zkey export solidityverifier circuit_final.zkey src/TikTakToeVerifier.sol

create-fixture:
	@if [ -z "$(NAME)" ] || [ -z "$(PLAYER)" ] || [ -z "$(MOVES)" ]; then \
		echo "Usage: make create-fixture NAME=name PLAYER=0 MOVES='[[r,c,p],...]'"; \
		exit 1; \
	fi
	@echo "==> Creating fixture: $(NAME)"
	@mkdir -p test/fixtures/$(NAME)
	@NAME=$(NAME) PLAYER=$(PLAYER) MOVES='$(MOVES)' node -e 'const fs=require("fs");const path=require("path");const moves=JSON.parse(process.env.MOVES);const b=Array(9).fill(2);moves.forEach(([r,c,p])=>{b[r*3+c]=p});const board=[b.slice(0,3),b.slice(3,6),b.slice(6,9)];const player=Number(process.env.PLAYER);const name=process.env.NAME;const fixturePath=path.join("test","fixtures",name);fs.writeFileSync(path.join(fixturePath,"input.json"),JSON.stringify({board,player}));fs.writeFileSync(path.join(fixturePath,"moves.json"),process.env.MOVES);'
	@npx snarkjs groth16 fullprove \
		test/fixtures/$(NAME)/input.json \
		tic_tak_toe_js/tic_tak_toe.wasm \
		circuit_final.zkey \
		test/fixtures/$(NAME)/proof.json \
		test/fixtures/$(NAME)/public.json

generate-all-fixtures:
	@echo "==> Generating all fixtures..."
	@$(MAKE) create-fixture NAME=player0_wins_row0     PLAYER=0 MOVES="[[0,0,0],[1,0,1],[0,1,0],[1,1,1],[0,2,0]]"
	@$(MAKE) create-fixture NAME=player0_wins_col0     PLAYER=0 MOVES="[[0,0,0],[0,1,1],[1,0,0],[1,1,1],[2,0,0]]"
	@$(MAKE) create-fixture NAME=player0_wins_diag     PLAYER=0 MOVES="[[0,0,0],[0,1,1],[1,1,0],[1,2,1],[2,2,0]]"
	@$(MAKE) create-fixture NAME=player0_wins_antidiag PLAYER=0 MOVES="[[1,1,0],[0,1,1],[0,2,0],[1,2,1],[2,0,0]]"
	@$(MAKE) create-fixture NAME=player1_wins_row0     PLAYER=1 MOVES="[[1,0,0],[0,0,1],[1,2,0],[0,1,1],[2,1,0],[0,2,1]]"
	@$(MAKE) create-fixture NAME=player1_wins_col1     PLAYER=1 MOVES="[[0,0,0],[0,1,1],[1,2,0],[1,1,1],[2,0,0],[2,1,1]]"
	@$(MAKE) create-fixture NAME=player1_wins_diag     PLAYER=1 MOVES="[[0,1,0],[0,0,1],[2,0,0],[1,1,1],[1,2,0],[2,2,1]]"
	@$(MAKE) create-fixture NAME=player1_wins_antidiag PLAYER=1 MOVES="[[2,2,0],[0,2,1],[2,0,0],[1,1,1],[0,1,0],[2,0,1]]"

verify-fixture:
	@if [ -z "$(NAME)" ]; then \
		echo "Usage: make verify-fixture NAME=fixture_name"; \
		exit 1; \
	fi
	@echo "==> Verifying fixture: $(NAME)"
	@npx snarkjs groth16 verify \
		verification_key.json \
		test/fixtures/$(NAME)/public.json \
		test/fixtures/$(NAME)/proof.json

calldata-fixture:
	@if [ -z "$(NAME)" ]; then \
		echo "Usage: make calldata-fixture NAME=fixture_name"; \
		exit 1; \
	fi
	@echo "==> Exporting solidity calldata for fixture: $(NAME)"
	npx snarkjs zkey export soliditycalldata \
		test/fixtures/$(NAME)/public.json \
		test/fixtures/$(NAME)/proof.json
	@node -e 'const fs=require("fs"); \
const proof=JSON.parse(fs.readFileSync("test/fixtures/$(NAME)/proof.json")); \
const pub=JSON.parse(fs.readFileSync("test/fixtures/$(NAME)/public.json")); \
const dec=x=>BigInt(x).toString(); \
const out={ \
  a:[dec(proof.pi_a[0]),dec(proof.pi_a[1])], \
  b:[ \
    [dec(proof.pi_b[0][1]),dec(proof.pi_b[0][0])], \
    [dec(proof.pi_b[1][1]),dec(proof.pi_b[1][0])] \
  ], \
  c:[dec(proof.pi_c[0]),dec(proof.pi_c[1])], \
  publicSignals: pub.map(dec) \
}; \
fs.writeFileSync("test/fixtures/$(NAME)/calldata.json", JSON.stringify(out)); \
console.log("Wrote test/fixtures/$(NAME)/calldata.json");'

calldata-all:
	@echo "==> Generating calldata.json for all fixtures..."
	@$(MAKE) calldata-fixture NAME=player0_wins_row0
	@$(MAKE) calldata-fixture NAME=player0_wins_col0
	@$(MAKE) calldata-fixture NAME=player0_wins_diag
	@$(MAKE) calldata-fixture NAME=player0_wins_antidiag
	@$(MAKE) calldata-fixture NAME=player1_wins_row0
	@$(MAKE) calldata-fixture NAME=player1_wins_col1
	@$(MAKE) calldata-fixture NAME=player1_wins_diag
	@$(MAKE) calldata-fixture NAME=player1_wins_antidiag

clean:
	@echo "==> Cleaning all generated files..."
	rm -rf tic_tak_toe_js
	rm -rf test/fixtures
	rm -f pot12_*.ptau
	rm -f circuit_*.zkey
	rm -f tic_tak_toe.r1cs
	rm -f tic_tak_toe.sym
	rm -f verification_key.json

help:
	@echo "Targets:"
	@echo "  make all"
	@echo "  make compile"
	@echo "  make powers-of-tau"
	@echo "  make setup"
	@echo "  make verifier"
	@echo "  make create-fixture"
	@echo "  make generate-all-fixtures"
	@echo "  make verify-fixture"
	@echo "  make calldata-fixture"
	@echo "  make calldata-all"
	@echo "  make clean"
	@echo "  make help"
