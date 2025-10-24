test:
	sui move test --coverage
test-summary:
	sui move coverage summary
test-summary-full:
	sui move coverage summary --summarize-functions