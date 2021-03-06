# Copyright 2018 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# If you update this file, please follow
# https://suva.sh/posts/well-documented-makefiles

.DEFAULT_GOAL:=help

# Default timeout for starting/stopping the Kubebuilder test control plane
export KUBEBUILDER_CONTROLPLANE_START_TIMEOUT ?=60s
export KUBEBUILDER_CONTROLPLANE_STOP_TIMEOUT ?=60s

# Image URL to use all building/pushing image targets
export CONTROLLER_IMG ?= gcr.io/k8s-cluster-api/cluster-api-controller:0.1.0
export EXAMPLE_PROVIDER_IMG ?= gcr.io/k8s-cluster-api/example-provider-controller:latest

GO111MODULE = on
export GO111MODULE
GOFLAGS = -mod=vendor
export GOFLAGS

all: test manager clusterctl

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: vendor
vendor: ## Runs vendor.
	go mod tidy
	go mod vendor
	go mod verify

.PHONY: test
test: verify generate fmt vet manifests ## Run tests
	go test -v -timeout=20m -tags=integration ./pkg/... ./cmd/manager/...

.PHONY: manager
manager: generate fmt vet ## Build manager binary
	go build -o bin/manager github.com/openshift/cluster-api/cmd/manager

.PHONY: clusterctl
clusterctl: generate fmt vet ## Build clusterctl binary
	go build -o bin/clusterctl github.com/openshift/cluster-api/cmd/clusterctl

.PHONY: run
run: generate fmt vet ## Run against the configured Kubernetes cluster in ~/.kube/config
	go run ./cmd/manager/main.go

.PHONY: deploy
deploy: manifests ## Deploy controller in the configured Kubernetes cluster in ~/.kube/config
	kustomize build config | kubectl apply -f -

.PHONY: manifests
manifests: ## Generate manifests e.g. CRD, RBAC etc.
	go run vendor/sigs.k8s.io/controller-tools/cmd/controller-gen/main.go crd \
	    paths=./pkg/apis/machine/... \
	    output:crd:dir=./config/crds

.PHONY: fmt
fmt: ## Run go fmt against code
	test -z $$(gofmt -s -l  ./pkg/ ./cmd/)

.PHONY: goimports
goimports: ## Go fmt your code
	hack/goimports.sh .

.PHONY: vet
vet: ## Run go vet against code
	go vet ./pkg/... ./cmd/...

.PHONY: generate
generate: clientset ## Generate code
	go generate ./pkg/... ./cmd/...

.PHONY: clientset
clientset: ## Generate a typed clientset
	go run ./vendor/k8s.io/code-generator/cmd/client-gen --clientset-name clientset --input-base github.com/openshift/cluster-api/pkg/apis \
		--input cluster/v1alpha1,machine/v1beta1 --output-package github.com/openshift/cluster-api/pkg/client/clientset_generated \
		--go-header-file=./hack/boilerplate.go.txt
	go run ./vendor/k8s.io/code-generator/cmd/lister-gen --input-dirs github.com/openshift/cluster-api/pkg/apis/cluster/v1alpha1,github.com/openshift/cluster-api/pkg/apis/machine/v1beta1 \
		--output-package github.com/openshift/cluster-api/pkg/client/listers_generated \
		--go-header-file=./hack/boilerplate.go.txt
	go run ./vendor/k8s.io/code-generator/cmd/informer-gen --input-dirs github.com/openshift/cluster-api/pkg/apis/cluster/v1alpha1,github.com/openshift/cluster-api/pkg/apis/machine/v1beta1 \
		--versioned-clientset-package github.com/openshift/cluster-api/pkg/client/clientset_generated/clientset \
		--listers-package github.com/openshift/cluster-api/pkg/client/listers_generated \
		--output-package github.com/openshift/cluster-api/pkg/client/informers_generated \
		--go-header-file=./hack/boilerplate.go.txt


.PHONY: docker-build
docker-build: generate fmt vet manifests ## Build the docker image for controller-manager
	docker build . -t ${CONTROLLER_IMG}
	@echo "updating kustomize image patch file for manager resource"
	sed -i.tmp -e 's@image: .*@image: '"${CONTROLLER_IMG}"'@' ./config/default/manager_image_patch.yaml

.PHONY: docker-push
docker-push: docker-build ## Push the docker image
	docker push "$(CONTROLLER_IMG)"

.PHONY: docker-build-ci
docker-build-ci: generate fmt vet manifests ## Build the docker image for example provider
	docker build . -f ./pkg/provider/example/container/Dockerfile -t ${EXAMPLE_PROVIDER_IMG}
	@echo "updating kustomize image patch file for ci"
	sed -i.tmp -e 's@image: .*@image: '"${EXAMPLE_PROVIDER_IMG}"'@' ./config/ci/manager_image_patch.yaml

.PHONY: docker-push-ci
docker-push-ci: docker-build-ci  ## Build the docker image for ci
	docker push "$(EXAMPLE_PROVIDER_IMG)"

.PHONY: verify
verify:
	./hack/verify_boilerplate.py
	./hack/verify_clientset.sh
