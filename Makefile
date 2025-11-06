.PHONY: test help

# Default target
.DEFAULT_GOAL := help

# Subdirectories with Makefiles
SUBDIRS := kustomize/base/helmapp

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@echo '  test            Run all tests for all compositions'
	@echo '  help            Show this help message'

test: ## Run all tests for all compositions
	@echo "🚀 Running tests for all compositions..."
	@for dir in $(SUBDIRS); do \
		echo ""; \
		echo "Testing $$dir..."; \
		$(MAKE) -C $$dir test || exit 1; \
	done
	@echo ""
	@echo "✅ All composition tests passed!"
