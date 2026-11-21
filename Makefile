.PHONY: help bootstrap build test lint format probe arrange app run-app test-update release-dry runner runner-remove github-setup

RELEASE_TAG ?= v0.0.0-beta.1

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

app:             ## Build build/ordino.app (debug)
	scripts/bundle-app.sh

run-app:         ## Build and launch ordino.app
	scripts/bundle-app.sh
	open build/ordino.app

test-update:     ## End-to-end Sparkle update test on localhost (0.1.0 -> 0.1.1)
	scripts/test-update.sh

release-dry:     ## Build release artifacts locally without publishing (RELEASE_TAG=v0.0.0-beta.1)
	DRY_RUN=1 scripts/release.sh $(RELEASE_TAG)

runner:          ## Register this Mac as the self-hosted GitHub Actions runner
	scripts/setup-runner.sh

runner-remove:   ## Unregister and uninstall the runner
	scripts/setup-runner.sh --remove

github-setup:    ## Apply repo security settings, rulesets and variables
	scripts/setup-github.sh
