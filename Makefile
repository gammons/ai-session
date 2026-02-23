.PHONY: test

test:
	@./test/test-helpers.sh
	@./test/test-commands.sh
	@./test/test-scrub-secrets.sh
