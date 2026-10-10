.PHONY: check-environment test-domain up down migrate seed test-api lint-api smoke-api test mobile-deps test-mobile analyze-mobile run-ios run-android build-android-debug

FLUTTER ?= $(shell command -v flutter 2>/dev/null || echo $(HOME)/development/flutter/bin/flutter)
COMPOSE = docker compose

check-environment:
	sh scripts/check-environment.sh

test-domain:
	php apps/api/tests/domain.php

# Backend: PostgreSQL e API em Docker (sem apagar volumes).
up:
	$(COMPOSE) up -d --build --wait

down:
	$(COMPOSE) stop

migrate:
	$(COMPOSE) exec -T api php artisan migrate

seed:
	$(COMPOSE) exec -T api php artisan db:seed

# Suíte da API no host, contra o banco bigdevz_finance_test do Compose.
test-api:
	cd apps/api && composer install --no-interaction --quiet && php artisan test

lint-api:
	cd apps/api && vendor/bin/pint --test

smoke-api:
	sh scripts/smoke-api.sh

test: test-domain test-api

# Aplicativo Flutter.
mobile-deps:
	cd apps/mobile && $(FLUTTER) pub get

analyze-mobile:
	cd apps/mobile && $(FLUTTER) analyze

test-mobile:
	cd apps/mobile && $(FLUTTER) test

run-ios:
	cd apps/mobile && $(FLUTTER) run -d "$${DEVICE:-iPhone}" --dart-define=API_BASE_URL=$${API_BASE_URL:-http://127.0.0.1:8000/api}

run-android:
	cd apps/mobile && $(FLUTTER) run -d "$${DEVICE:-android}" --dart-define=API_BASE_URL=$${API_BASE_URL:-http://10.0.2.2:8000/api}

build-android-debug:
	cd apps/mobile && $(FLUTTER) build apk --debug
