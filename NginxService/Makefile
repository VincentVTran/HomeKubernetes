SHELL := /bin/bash

# Define variables
ENV_FILE = .env
YAML_FILE = deployment.yaml

# Load environment variables from .env file
ifneq (,$(wildcard $(ENV_FILE)))
    include $(ENV_FILE)
    export $(shell sed 's/=.*//' $(ENV_FILE))
endif

# Build and push Docker image
build-image:
	docker build -t ${IMAGE_NAME} .
	docker push ${IMAGE_NAME}

# Deploy application
deploy:
	# Apply the YAML file with environment variable substitution
	-@kubectl delete -f ./ || true
	envsubst < $(YAML_FILE) | kubectl apply -f -
