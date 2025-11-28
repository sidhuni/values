#!/bin/bash
set -euo

# -------------------------
# Configuration  this section defines variables that configure the script.
# -------------------------
APPS=("app1" "app2" "app3" "app4" "app5")
TEMPLATE_CHART="./template/Chart.yaml"
CHARTMUSEUM_URL="http://192.168.64.2:30080"
ARGOCD_LOCAL="$HOME/argo-apps"  # Local clone of ArgoCD apps repo

echo "======================================="
echo " STARTING AUTO UPDATE SCRIPT FOR APP1 & APP2 "
echo "======================================="

# Read base version from template
TEMPLATE_VERSION=$(grep "^version:" "$TEMPLATE_CHART" | awk '{print $2}')
# This line splits the version number (e.g., 1.2.3) into its major, minor, and patch components.  IFS is the Internal Field Separator, which is set to '.' to split the string.  read reads the values into the variables BASEMAJOR, BASEMINOR, and BASEPATCH.  The -r option prevents backslash escapes from being interpreted.
IFS='.' read -r BASE_MAJOR BASE_MINOR BASE_PATCH <<< "$TEMPLATE_VERSION"


#This line starts a loop that iterates through the indices of the APPS array.  ${!APPS[@]} expands to the indices (0, 1, 2, etc.).
for i in "${!APPS[@]}"; do
    APP_NAME="${APPS[$i]}"
    APP_DIR="./$APP_NAME"   #This line defines the directory where the application's chart files will be created.

    # -------------------------
    # Calculate new version per app
    # -------------------------
    PATCH=$((BASE_PATCH + i + 1))  # Increment patch uniquely per app
    NEW_VERSION="$BASE_MAJOR.$BASE_MINOR.$PATCH"

    # Read base chart name from template
    BASE_CHART_NAME=$(grep "^name:" "$TEMPLATE_CHART" | awk '{print $2}')
    NEW_CHART_NAME="${BASE_CHART_NAME}$((i+1))"

    echo "---------------------------------------"
    echo "Processing $APP_NAME..."
    echo "New version to apply: $NEW_VERSION"
    echo "New chart name: $NEW_CHART_NAME"

    # -------------------------
    # Prepare app folder
    # -------------------------
    mkdir -p "$APP_DIR/charts"
    cp "$TEMPLATE_CHART" "$APP_DIR/Chart.yaml"

    # -------------------------
    # Update version & name in Chart.yaml
    # -------------------------
    sed -i '' "s/^version:.*/version: $NEW_VERSION/" "$APP_DIR/Chart.yaml"
    sed -i '' "s/^name:.*/name: $NEW_CHART_NAME/" "$APP_DIR/Chart.yaml"

    # -------------------------
    # Build Helm dependencies
    # -------------------------
    cd "$APP_DIR"
    echo "Building Helm dependencies..."
    helm dependency update
    cd - >/dev/null

    # -------------------------
    # Package Helm chart
    # -------------------------
    echo "Packaging chart..."
    PACKAGE_FILE=$(helm package "$APP_DIR" --destination "$APP_DIR" | awk '{print $NF}')
    echo "Successfully packaged chart: $PACKAGE_FILE"

    # -------------------------
    # Upload chart to ChartMuseum
    # -------------------------
    echo "Uploading chart to ChartMuseum..."
    curl --fail --silent --show-error --data-binary "@$PACKAGE_FILE" "$CHARTMUSEUM_URL/api/charts"
    echo "Upload complete!"

    # -------------------------
    # Update ArgoCD app YAML
    # -------------------------
    APP_FILE="$ARGOCD_LOCAL/application/$APP_NAME.yaml"
    if [ ! -f "$APP_FILE" ]; then
        echo "❌ Error: ArgoCD app file not found: $APP_FILE"
        exit 1
    fi
    sed -i '' "s/targetRevision:.*/targetRevision: $NEW_VERSION/" "$APP_FILE"
    sed -i '' "s/chart:.*/chart: $NEW_CHART_NAME/" "$APP_FILE"

    # -------------------------
    # Commit & push changes
    # -------------------------
    cd "$ARGOCD_LOCAL"
    git add "$APP_FILE"
    git commit -m "Automated update: $APP_NAME version $NEW_VERSION"
    git push
    cd - >/dev/null

    # -------------------------
    # Cleanup app folder (keep only values.yaml)
    # -------------------------
    rm -rf "$APP_DIR/Chart.yaml" "$APP_DIR/Chart.lock" "$PACKAGE_FILE" "$APP_DIR/charts"

    echo "✅ $APP_NAME updated successfully!"
done

echo "======================================="
echo "APP1 & APP2 UPDATED SUCCESSFULLY!"
echo "======================================="
