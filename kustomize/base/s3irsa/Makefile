.PHONY: test validate render clean help

# Default target
.DEFAULT_GOAL := help

# Base directory for s3irsa
BASE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Test examples
EXAMPLES := $(wildcard $(BASE_DIR)examples/*.yaml)

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

test: validate render ## Run all tests (validate + render)
	@echo "✅ All s3irsa tests passed!"

validate: ## Validate the composition and XRD using crossplane beta validate
	@echo "🔍 Validating S3IRSA XRD and Composition..."
	@crossplane beta validate \
		$(BASE_DIR)s3irsa-xrd.yaml,$(BASE_DIR)functions-only.yaml \
		$(BASE_DIR)s3irsa-composition.yaml
	@echo "✅ Validation passed!"

render: ## Render compositions with example S3IRSA resources
	@echo "🎨 Rendering S3IRSA compositions with examples..."
	@for example in $(EXAMPLES); do \
		echo ""; \
		echo "Testing $$(basename $$example)..."; \
		crossplane render \
			$$example \
			$(BASE_DIR)s3irsa-composition.yaml \
			$(BASE_DIR)functions-only.yaml \
			--xrd=$(BASE_DIR)s3irsa-xrd.yaml \
			--required-resources=$(BASE_DIR)test-environment-config.yaml \
			|| exit 1; \
		echo "✅ $$(basename $$example) rendered successfully"; \
	done
	@echo ""
	@echo "✅ All examples rendered successfully!"

clean: ## Clean up any generated files
	@echo "🧹 Cleaning up s3irsa test artifacts..."
	@rm -f $(BASE_DIR).crossplane-render-*
	@echo "✅ Clean complete!"
