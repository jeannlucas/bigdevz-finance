.PHONY: check-environment test-domain

check-environment:
	sh scripts/check-environment.sh

test-domain:
	php apps/api/tests/domain.php
