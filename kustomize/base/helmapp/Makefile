.PHONY: test validate render clean help

# Default target
.DEFAULT_GOAL := help

# Base directory for helmapp
BASE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Test examples
EXAMPLES := $(wildcard $(BASE_DIR)examples/*.yaml)

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

test: validate render ## Run all tests (validate + render)
	@echo "✅ All helmapp tests passed!"

validate: ## Validate the composition and XRD using crossplane beta validate
	@echo "🔍 Validating HelmApplication XRD and Composition..."
	@crossplane beta validate \
		$(BASE_DIR)helmapp-xrd.yaml,$(BASE_DIR)functions.yaml \
		$(BASE_DIR)helmapp-composition.yaml
	@echo "✅ Validation passed!"

render: ## Render compositions with example HelmApplications
	@echo "🎨 Rendering HelmApplication compositions with examples..."
	@for example in $(EXAMPLES); do \
		echo ""; \
		echo "Testing $$(basename $$example)..."; \
		crossplane render \
			$$example \
			$(BASE_DIR)helmapp-composition.yaml \
			$(BASE_DIR)functions.yaml \
			--xrd=$(BASE_DIR)helmapp-xrd.yaml \
			--required-resources=$(BASE_DIR)test-environment-config.yaml \
			|| exit 1; \
		echo "✅ $$(basename $$example) rendered successfully"; \
	done
	@echo ""
	@echo "✅ All examples rendered successfully!"

clean: ## Clean up any generated files
	@echo "🧹 Cleaning up helmapp test artifacts..."
	@rm -f $(BASE_DIR).crossplane-render-*
	@echo "✅ Clean complete!"
