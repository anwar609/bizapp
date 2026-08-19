#!/usr/bin/env bash
set -euo pipefail

GROUP="${1:?usage: deploy-wave.sh <group> <jar-uri> <script-uri> <version>}"
JAR_URI="${2:?jar s3 uri required}"
SCRIPT_URI="${3:?script s3 uri required}"
VERSION="${4:?version required}"

TG_ARN="${TG_ARN:?TG_ARN not set}"
SECRET_NAME="${SECRET_NAME:?SECRET_NAME not set}"
APP_PORT="${APP_PORT:-2330}"
REGION="${AWS_REGION:-us-east-1}"

echo "::group::Discover deployment group ${GROUP}"
IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:DeploymentGroup,Values=${GROUP}" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

if [ -z "${IDS}" ]; then
  echo "No running instances in group ${GROUP}"
  exit 1
fi
echo "Targets: ${IDS}"
echo "::endgroup::"

echo "::group::Drain from load balancer"
for ID in ${IDS}; do
  echo "Deregistering ${ID}"
  aws elbv2 deregister-targets --target-group-arn "${TG_ARN}" --targets "Id=${ID}"
done
for ID in ${IDS}; do
  aws elbv2 wait target-deregistered --target-group-arn "${TG_ARN}" --targets "Id=${ID}"
  echo "${ID} drained"
done
echo "::endgroup::"

echo "::group::Deploy ${VERSION}"
CMD=$(aws ssm send-command \
  --document-name AWS-RunShellScript \
  --targets "Key=tag:DeploymentGroup,Values=${GROUP}" \
  --timeout-seconds 900 \
  --parameters commands="[\
\"set -e\",\
\"aws s3 cp ${SCRIPT_URI} /tmp/remote-deploy.sh --region ${REGION}\",\
\"chmod +x /tmp/remote-deploy.sh\",\
\"JAR_URI=${JAR_URI} SECRET_NAME=${SECRET_NAME} APP_PORT=${APP_PORT} VERSION=${VERSION} AWS_REGION=${REGION} /tmp/remote-deploy.sh\"\
]" \
  --query 'Command.CommandId' --output text)

echo "Command: ${CMD}"

STATUSES=""
for _ in $(seq 1 40); do
  sleep 15
  STATUSES=$(aws ssm list-command-invocations --command-id "${CMD}" \
    --query 'CommandInvocations[].Status' --output text)
  echo "  ${STATUSES:-dispatching}"
  if [ -n "${STATUSES}" ] && ! grep -qE 'Pending|InProgress|Delayed' <<< "${STATUSES}"; then
    break
  fi
done

echo "--- output ---"
aws ssm list-command-invocations --command-id "${CMD}" --details \
  --query 'CommandInvocations[].CommandPlugins[].Output' --output text | tail -40

if grep -qE 'Failed|TimedOut|Cancelled' <<< "${STATUSES}"; then
  echo "Deploy failed on group ${GROUP} - nodes stay out of rotation"
  exit 1
fi
echo "::endgroup::"

echo "::group::Cut over"
for ID in ${IDS}; do
  aws elbv2 register-targets --target-group-arn "${TG_ARN}" --targets "Id=${ID}"
done
for ID in ${IDS}; do
  aws elbv2 wait target-in-service --target-group-arn "${TG_ARN}" --targets "Id=${ID}"
  echo "${ID} healthy and serving ${VERSION}"
done
echo "::endgroup::"

echo "Group ${GROUP} deployed at ${VERSION}."