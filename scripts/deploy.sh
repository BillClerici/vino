#!/bin/bash
set -euo pipefail

APP_NAME="vino"
ENV="${1:-dev}"
AWS_PROFILE="${APP_NAME}-${ENV}"
AWS_ACCOUNT=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
AWS_REGION="us-east-1"
ECR_BASE="${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"
GIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG="${ENV}-${GIT_SHA}"

echo "Deploying ${APP_NAME} to ${ENV} | tag: ${IMAGE_TAG}"

# Login to ECR
aws ecr get-login-password --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${ECR_BASE}"

# Build
docker build -t "${ECR_BASE}/web:${IMAGE_TAG}" \
             -t "${ECR_BASE}/web:${ENV}-latest" \
             --build-arg ENV="$ENV" .

# Push
docker push "${ECR_BASE}/web:${IMAGE_TAG}"
docker push "${ECR_BASE}/web:${ENV}-latest"

# Trigger ECS rolling deploy
aws ecs update-service \
  --profile "$AWS_PROFILE" \
  --cluster "${APP_NAME}-${ENV}" \
  --service "${APP_NAME}-web" \
  --force-new-deployment \
  --region "$AWS_REGION"

echo "Deploy triggered. Monitor: https://console.aws.amazon.com/ecs"
