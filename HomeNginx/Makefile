SHELL := /bin/bash
export $(shell sed 's/=.*//' .env)  # This exports all variables in .env

# Define variables
ENV_FILE = .env
YAML_FILE = deployment.yaml

build-image:
	docker build -t ${IMAGE_NAME} .
	docker push ${IMAGE_NAME}

# Target to deploy the application
deploy:
	# Load environment variables from .env and apply the YAML
	set -a; source $(ENV_FILE); set +a; envsubst < $(YAML_FILE) | kubectl apply -f -