.PHONY: help bootstrap build test lint format probe arrange release-dry runner runner-remove github-setup

TAG ?= v0.0.0-dev

help:            ## List targets
	@grep -E '^[a-z-]+:.*##' Makefile | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

bootstrap:       ## Install git hooks
	git config core.hooksPath .githooks
	chmod +x .githooks/* scripts/*.sh
	@echo "Hooks installed."

build:           ## Debug build
	swift build

test:            ## Run all tests
	swift test --parallel

lint:            ## Check formatting
	swift format lint --strict --recursive --parallel Package.swift Sources Tests

format:          ## Fix formatting in place
	swift format --in-place --recursive --parallel Package.swift Sources Tests

probe:           ## Dry run: show what would be arranged
	swift run ordino-probe

arrange:         ## Arrange the display under the mouse
	swift run ordino-probe --apply

release-dry:     ## Build release artifacts locally without publishing (TAG=v0.0.0-dev)
	DRY_RUN=1 scripts/release.sh $(TAG)

runner:          ## Register this Mac as the self-hosted GitHub Actions runner
	scripts/setup-runner.sh

runner-remove:   ## Unregister and uninstall the runner
	scripts/setup-runner.sh --remove

github-setup:    ## Apply repo security settings, rulesets and variables
	scripts/setup-github.sh
