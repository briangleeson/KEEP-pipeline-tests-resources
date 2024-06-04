#!/bin/bash

HELM_VERSION=3.5.3
DEPLOYMENT_FILE_HELM="deployment.helm.yaml"
DEPLOYMENT_FILE="deployment.yaml"
BUILD_VERSION=$BUILD_NUMBER.$BUILD_ID
EXIT=0;

if [[ -d "helm/$APP_KEY" ]]; then
  if [[ -f "helm/$APP_KEY/.settings" ]]; then
    source helm/$APP_KEY/.settings
  fi

  HELM_DIR="./helm/$APP_KEY"
  HELM_NAMESPACE="${DEFAULT_NAMESPACE:-dx-platform}"

  curl -s -L https://get.helm.sh/helm-v$HELM_VERSION-linux-amd64.tar.gz -o helm.tar.gz
  tar -xzf helm.tar.gz

  HELM="./linux-amd64/helm"
  echo "helm version"
  $HELM version;

  ENVIRONMENT=`echo "$CLUSTER_NAME" | tr '[:upper:]' '[:lower:]'`
  ADDITIONAL_VALUES=""
  if [ -f $HELM_DIR/env/$ENVIRONMENT.yaml ]; then
    ADDITIONAL_VALUES="-f $HELM_DIR/env/$ENVIRONMENT.yaml";
  fi;

  cat << EOF > $HELM_DIR/global.yaml
environment: $ENVIRONMENT
appKey: "$APP_KEY"
buildVersion: "$BUILD_VERSION"
image: $IMAGE
region: $REGION
clusterName: $CLUSTER_NAME
imagePullSecrets: $IMAGE_PULL_SECRETS
namespace: $HELM_NAMESPACE
deployment:
  deadlineSeconds: "$DEADLINE_SECONDS"
EOF

  echo "Global Values:"
  echo "--------------------";
  cat $HELM_DIR/global.yaml
  echo "--------------------";
  echo ""

  echo "Installing or upgrading helm chart..."
  $HELM template --namespace $HELM_NAMESPACE "$HELM_DIR" $ADDITIONAL_VALUES -f ./$HELM_DIR/global.yaml > $DEPLOYMENT_FILE_HELM
  EXIT=$?

  if [ $EXIT -ne 0 ]; then
    exit $EXIT;
  fi
fi

if [[ -f  "$DEPLOYMENT_FILE" ]]; then
  # Substitute the variables
  sed -i 's=$IMAGE_PULL_SECRETS='"$IMAGE_PULL_SECRETS"'=g' $DEPLOYMENT_FILE
  sed -i 's=$REGION='"$REGION"'=g' $DEPLOYMENT_FILE
  sed -i 's=$CLUSTER_NAME='"$CLUSTER_NAME"'=g' $DEPLOYMENT_FILE
  sed -i 's=$DEADLINE_SECONDS='"$DEADLINE_SECONDS"'=g' $DEPLOYMENT_FILE
  sed -i 's=$BUILD_VERSION='"ver-$(date +%s)"'=g' $DEPLOYMENT_FILE
  sed -i 's=$IMAGE='"$IMAGE"'=g' $DEPLOYMENT_FILE
  sed -i 's/$APP_KEY/'"$APP_KEY"'/g' $DEPLOYMENT_FILE

  # Show the file that is about to be executed
  echo ""
  echo "DEPLOYING USING MANIFEST:"
  cat $DEPLOYMENT_FILE
  echo ""

  # Execute the file
  echo "KUBERNETES COMMAND:"
  echo "kubectl apply -n $NAMESPACE -f $DEPLOYMENT_FILE"
  kubectl apply -n $NAMESPACE -f $DEPLOYMENT_FILE
  EXIT=$?

  # Monitor the rollout
  if [ $EXIT -eq 0 ]; then
    echo "kubectl -n $NAMESPACE get deployment $APP_KEY"
    kubectl -n $NAMESPACE get deployment $APP_KEY
    if [ $? -eq 0 ]; then
      echo "kubectl -n $NAMESPACE rollout status deployment/$APP_KEY"
      kubectl -n $NAMESPACE rollout status deployment/$APP_KEY
      EXIT=$?
    else
      echo "No Deployments Found"
    fi
  fi
fi

# If we're doing a helm based rollout, do that as well
if [[ -f  "$DEPLOYMENT_FILE_HELM" && $EXIT -eq 0 ]]; then
  # Show the file that is about to be executed
  echo ""
  echo "DEPLOYING USING HELM TEMPLATE:"
  cat $DEPLOYMENT_FILE_HELM
  echo ""

  echo "KUBERNETES COMMAND:"
  echo "kubectl apply -n $HELM_NAMESPACE -f $DEPLOYMENT_FILE_HELM"
  kubectl apply -n $HELM_NAMESPACE -f $DEPLOYMENT_FILE_HELM
  EXIT=$?

  # Monitor the rollout
  kubectl -n $HELM_NAMESPACE get deployment $APP_KEY
  if [ $? -eq 0 ]; then
    kubectl -n $HELM_NAMESPACE rollout status deployment/$APP_KEY
    EXIT=$?
  else
    echo "No Deployments Found"
  fi  
  
fi

# Update Insights
if [ $EXIT -eq 0 ]; then STATUS=pass; else STATUS=fail; fi;

ibmcloud login --apikey $PIPELINE_BLUEMIX_API_KEY --no-region
# ibmcloud doi publishdeployrecord --logicalappname="$APP_KEY" --buildnumber="$BUILD_VERSION" --env="$CLUSTER_NAME:$REGION" --status=$STATUS

exit $EXIT
