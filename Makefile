# SecureSharing Development Makefile
#
# Usage:
#   make setup     - First-time setup
#   make dev       - Start development environment
#   make test      - Run tests
#   make stop      - Stop Docker services

.PHONY: help setup dev stop test test.watch lint format deps db.setup db.reset db.migrate clean

# Backend service directory
BACKEND_DIR := services/securesharing

# Default target
help:
	@echo "SecureSharing Development Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make setup        - First-time project setup"
	@echo "  make deps         - Install Elixir dependencies"
	@echo ""
	@echo "Development:"
	@echo "  make dev          - Start Docker + Elixir server"
	@echo "  make dev.docker   - Start Docker services only"
	@echo "  make dev.server   - Start Elixir server only"
	@echo "  make stop         - Stop Docker services"
	@echo "  make iex          - Start IEx session with app loaded"
	@echo ""
	@echo "Database:"
	@echo "  make db.setup     - Create and migrate database"
	@echo "  make db.reset     - Drop, create, and migrate database"
	@echo "  make db.migrate   - Run pending migrations"
	@echo ""
	@echo "Testing:"
	@echo "  make test         - Run all tests"
	@echo "  make test.watch   - Run tests in watch mode"
	@echo "  make test.cover   - Run tests with coverage"
	@echo ""
	@echo "Quality:"
	@echo "  make lint         - Run Credo linter"
	@echo "  make format       - Format code"
	@echo "  make dialyzer     - Run Dialyzer type checker"
	@echo "  make check        - Run all quality checks"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make clean.all    - Clean everything including Docker volumes"

# =============================================================================
# Setup
# =============================================================================

setup: deps dev.docker db.setup
	@echo ""
	@echo "Setup complete! Run 'make dev.server' to start the application."

deps:
	cd $(BACKEND_DIR) && mix deps.get
	cd $(BACKEND_DIR) && mix deps.compile

# =============================================================================
# Development
# =============================================================================

dev: dev.docker dev.server

dev.docker:
	docker-compose up -d postgres garage
	@echo "Waiting for services to be healthy..."
	@sleep 5
	@docker-compose ps
	@echo ""
	@echo "Run 'make garage.init' to initialize Garage (first time only)"

garage.init:
	@./scripts/garage-init.sh

dev.server:
	cd $(BACKEND_DIR) && mix phx.server

dev.email:
	docker-compose --profile email up -d mailhog
	@echo "MailHog UI available at http://localhost:8025"

dev.redis:
	docker-compose --profile distributed up -d redis

stop:
	docker-compose down

stop.all:
	docker-compose --profile email --profile distributed down

iex:
	cd $(BACKEND_DIR) && iex -S mix phx.server

# =============================================================================
# Database
# =============================================================================

db.setup:
	cd $(BACKEND_DIR) && mix ecto.setup

db.reset:
	cd $(BACKEND_DIR) && mix ecto.reset

db.migrate:
	cd $(BACKEND_DIR) && mix ecto.migrate

db.rollback:
	cd $(BACKEND_DIR) && mix ecto.rollback

db.seed:
	cd $(BACKEND_DIR) && mix run priv/repo/seeds.exs

# =============================================================================
# Testing
# =============================================================================

test:
	cd $(BACKEND_DIR) && mix test

test.watch:
	cd $(BACKEND_DIR) && mix test.watch

test.cover:
	cd $(BACKEND_DIR) && mix test --cover

test.integration:
	cd $(BACKEND_DIR) && mix test test/integration

test.failed:
	cd $(BACKEND_DIR) && mix test --failed

# =============================================================================
# Quality
# =============================================================================

lint:
	cd $(BACKEND_DIR) && mix credo --strict

format:
	cd $(BACKEND_DIR) && mix format

format.check:
	cd $(BACKEND_DIR) && mix format --check-formatted

dialyzer:
	cd $(BACKEND_DIR) && mix dialyzer

check: format.check lint test
	@echo "All checks passed!"

# =============================================================================
# Cleanup
# =============================================================================

clean:
	rm -rf $(BACKEND_DIR)/_build
	rm -rf $(BACKEND_DIR)/deps
	rm -rf $(BACKEND_DIR)/priv/static/assets

clean.all: stop.all clean
	docker-compose down -v
	@echo "All cleaned up, including Docker volumes"

# =============================================================================
# Production
# =============================================================================

release:
	cd $(BACKEND_DIR) && MIX_ENV=prod mix release

release.docker:
	docker build -t securesharing:latest $(BACKEND_DIR)
