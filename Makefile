TAG?=latest
VERSION?=$(shell grep 'VERSION' pkg/version/version.go | awk '{ print $$4 }' | tr -d '"')
VERSION_MINOR:=$(shell grep 'VERSION' pkg/version/version.go | awk '{ print $$4 }' | tr -d '"' | rev | cut -d'.' -f2- | rev)
PATCH:=$(shell grep 'VERSION' pkg/version/version.go | awk '{ print $$4 }' | tr -d '"' | awk -F. '{print $$NF}')
SOURCE_DIRS = cmd pkg/apis pkg/controller pkg/server pkg/logging pkg/version
LT_VERSION?=$(shell grep 'VERSION' cmd/loadtester/main.go | awk '{ print $$4 }' | tr -d '"' | head -n1)
TS=$(shell date +%Y-%m-%d_%H-%M-%S)

run:
	go run cmd/flagger/* -kubeconfig=$$HOME/.kube/config -log-level=info -mesh-provider=istio -namespace=test \
	-metrics-server=https://prometheus.istio.weavedx.com \
	-slack-url=https://hooks.slack.com/services/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 \
	-slack-channel="devops-alerts"

run-appmesh:
	go run cmd/flagger/* -kubeconfig=$$HOME/.kube/config -log-level=info -mesh-provider=appmesh \
	-metrics-server=http://acfc235624ca911e9a94c02c4171f346-1585187926.us-west-2.elb.amazonaws.com:9090 \
	-slack-url=https://hooks.slack.com/services/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 \
	-slack-channel="devops-alerts"

run-nginx:
	go run cmd/flagger/* -kubeconfig=$$HOME/.kube/config -log-level=info -mesh-provider=nginx -namespace=nginx \
	-metrics-server=http://prometheus-weave.istio.weavedx.com \
	-slack-url=https://hooks.slack.com/services/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 \
	-slack-channel="devops-alerts"

run-smi:
	go run cmd/flagger/* -kubeconfig=$$HOME/.kube/config -log-level=info -mesh-provider=smi:istio -namespace=smi \
	-metrics-server=https://prometheus.istio.weavedx.com \
	-slack-url=https://hooks.slack.com/services/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 \
	-slack-channel="devops-alerts"

run-gloo:
	go run cmd/flagger/* -kubeconfig=$$HOME/.kube/config -log-level=info -mesh-provider=gloo -namespace=gloo \
	-metrics-server=https://prometheus.istio.weavedx.com \
	-slack-url=https://hooks.slack.com/services/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 \
	-slack-channel="devops-alerts"

build:
	docker build -t weaveworks/flagger:$(TAG) . -f Dockerfile

push:
	docker tag weaveworks/flagger:$(TAG) weaveworks/flagger:$(VERSION)
	docker push weaveworks/flagger:$(VERSION)

fmt:
	gofmt -l -s -w $(SOURCE_DIRS)

test-fmt:
	gofmt -l -s $(SOURCE_DIRS) | grep ".*\.go"; if [ "$$?" = "0" ]; then exit 1; fi

test-codegen:
	./hack/verify-codegen.sh

test: test-fmt test-codegen
	go test ./...

helm-package:
	cd charts/ && helm package ./*
	mv charts/*.tgz docs/
	helm repo index docs --url https://weaveworks.github.io/flagger --merge ./docs/index.yaml

helm-up:
	helm upgrade --install flagger ./charts/flagger --namespace=istio-system --set crd.create=false
	helm upgrade --install flagger-grafana ./charts/grafana --namespace=istio-system

version-set:
	@next="$(TAG)" && \
	current="$(VERSION)" && \
	sed -i '' "s/$$current/$$next/g" pkg/version/version.go && \
	sed -i '' "s/flagger:$$current/flagger:$$next/g" artifacts/flagger/deployment.yaml && \
	sed -i '' "s/tag: $$current/tag: $$next/g" charts/flagger/values.yaml && \
	sed -i '' "s/appVersion: $$current/appVersion: $$next/g" charts/flagger/Chart.yaml && \
	sed -i '' "s/version: $$current/version: $$next/g" charts/flagger/Chart.yaml && \
	echo "Version $$next set in code, deployment and charts"

version-up:
	@next="$(VERSION_MINOR).$$(($(PATCH) + 1))" && \
	current="$(VERSION)" && \
	sed -i '' "s/$$current/$$next/g" pkg/version/version.go && \
	sed -i '' "s/flagger:$$current/flagger:$$next/g" artifacts/flagger/deployment.yaml && \
	sed -i '' "s/tag: $$current/tag: $$next/g" charts/flagger/values.yaml && \
	sed -i '' "s/appVersion: $$current/appVersion: $$next/g" charts/flagger/Chart.yaml && \
	echo "Version $$next set in code, deployment and chart"

dev-up: version-up
	@echo "Starting build/push/deploy pipeline for $(VERSION)"
	docker build -t quay.io/stefanprodan/flagger:$(VERSION) . -f Dockerfile
	docker push quay.io/stefanprodan/flagger:$(VERSION)
	kubectl apply -f ./artifacts/flagger/crd.yaml
	helm upgrade -i flagger ./charts/flagger --namespace=istio-system --set crd.create=false

release:
	git tag $(VERSION)
	git push origin $(VERSION)

release-set: fmt version-set helm-package
	git add .
	git commit -m "Release $(VERSION)"
	git push origin master
	git tag $(VERSION)
	git push origin $(VERSION)

reset-test:
	kubectl delete -f ./artifacts/namespaces
	kubectl apply -f ./artifacts/namespaces
	kubectl apply -f ./artifacts/canaries

loadtester-run:
	docker build -t weaveworks/flagger-loadtester:$(LT_VERSION) . -f Dockerfile.loadtester
	docker rm -f tester || true
	docker run -dp 8888:9090 --name tester weaveworks/flagger-loadtester:$(LT_VERSION)

loadtester-push:
	docker build -t weaveworks/flagger-loadtester:$(LT_VERSION) . -f Dockerfile.loadtester
	docker push weaveworks/flagger-loadtester:$(LT_VERSION)
