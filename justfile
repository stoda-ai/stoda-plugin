# Free checks; CI runs this.
test: validate lint bats

validate:
    claude plugin validate --strict .
    claude plugin validate --strict plugins/stoda

lint:
    shellcheck -x scripts/*.sh plugins/stoda/scripts/*.sh

bats:
    bats tests
