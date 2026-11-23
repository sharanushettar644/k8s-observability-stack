.PHONY: up monitoring logging demo all test-rules render e2e-metrics e2e-logging down

up:
	bash scripts/kind-up.sh

monitoring:
	bash scripts/install-monitoring.sh

logging:
	bash scripts/install-logging.sh

demo:
	bash scripts/deploy-demo.sh

all: up monitoring logging demo

test-rules:
	promtool check rules prometheus/rules/*.rules.yaml
	promtool test rules prometheus/tests/*.test.yaml

render:
	python3 scripts/render-rules.py

e2e-metrics:
	bash scripts/e2e-metrics.sh

e2e-logging:
	bash scripts/e2e-logging.sh

down:
	kind delete cluster --name observability
