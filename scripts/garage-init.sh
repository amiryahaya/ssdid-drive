#!/bin/bash
# Garage Initialization Script
# Run this after starting the Garage container for the first time
#
# Usage: ./scripts/garage-init.sh

set -e

GARAGE_ADMIN_TOKEN="securesharing-admin-token"
GARAGE_ADMIN_API="http://localhost:3903"
GARAGE_S3_API="http://localhost:3900"

echo "=== Garage Initialization ==="
echo ""

# Wait for Garage to be ready
echo "Waiting for Garage to be ready..."
until curl -sf "$GARAGE_ADMIN_API/health" > /dev/null 2>&1; do
    sleep 1
done
echo "Garage is ready!"
echo ""

# Get node ID
echo "Getting node information..."
NODE_ID=$(curl -sf -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
    "$GARAGE_ADMIN_API/v1/status" | jq -r '.node')
echo "Node ID: $NODE_ID"
echo ""

# Check if layout is already configured
LAYOUT=$(curl -sf -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" "$GARAGE_ADMIN_API/v1/layout")
ROLES_COUNT=$(echo "$LAYOUT" | jq -r '.roles | length')
STAGED_COUNT=$(echo "$LAYOUT" | jq -r '.stagedRoleChanges | length')

if [ "$ROLES_COUNT" = "0" ] && [ "$STAGED_COUNT" = "0" ]; then
    echo "Configuring cluster layout..."

    # Assign role to the node (Garage v1 uses array format)
    # Capacity is in bytes - using 1GB for development
    curl -sf -X POST -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "[{\"id\": \"$NODE_ID\", \"zone\": \"dc1\", \"capacity\": 1073741824, \"tags\": [\"dev\"]}]" \
        "$GARAGE_ADMIN_API/v1/layout" > /dev/null

    echo "Applying layout..."
    LAYOUT_VERSION=$(curl -sf -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
        "$GARAGE_ADMIN_API/v1/layout" | jq -r '.version')
    NEXT_VERSION=$((LAYOUT_VERSION + 1))

    RESULT=$(curl -sf -X POST -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"version\": $NEXT_VERSION}" \
        "$GARAGE_ADMIN_API/v1/layout/apply")

    echo "Layout configured!"
elif [ "$STAGED_COUNT" != "0" ]; then
    echo "Layout changes pending, applying..."
    LAYOUT_VERSION=$(echo "$LAYOUT" | jq -r '.version')
    NEXT_VERSION=$((LAYOUT_VERSION + 1))

    curl -sf -X POST -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"version\": $NEXT_VERSION}" \
        "$GARAGE_ADMIN_API/v1/layout/apply" > /dev/null
    echo "Layout applied!"
else
    echo "Cluster layout already configured."
fi
echo ""

# Check if key already exists
EXISTING_KEYS=$(curl -sf -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" "$GARAGE_ADMIN_API/v1/key")
KEY_EXISTS=$(echo "$EXISTING_KEYS" | jq -r '.[] | select(.name == "securesharing-dev") | .id' 2>/dev/null || echo "")

if [ -z "$KEY_EXISTS" ]; then
    # Create access key
    echo "Creating access key..."
    KEY_RESPONSE=$(curl -sf -X POST -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name": "securesharing-dev"}' \
        "$GARAGE_ADMIN_API/v1/key")

    ACCESS_KEY=$(echo "$KEY_RESPONSE" | jq -r '.accessKeyId')
    SECRET_KEY=$(echo "$KEY_RESPONSE" | jq -r '.secretAccessKey')

    echo ""
    echo "=== Access Key Created ==="
    echo "Access Key ID: $ACCESS_KEY"
    echo "Secret Key:    $SECRET_KEY"
else
    ACCESS_KEY="$KEY_EXISTS"
    echo "Access key already exists: $ACCESS_KEY"
    echo "(Secret key not shown for existing keys)"
fi
echo ""

# Create dev bucket if it doesn't exist
DEV_BUCKET_EXISTS=$(curl -sf -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
    "$GARAGE_ADMIN_API/v1/bucket?globalAlias=securesharing-dev" 2>/dev/null | jq -r '.id' 2>/dev/null || echo "")

if [ -z "$DEV_BUCKET_EXISTS" ] || [ "$DEV_BUCKET_EXISTS" = "null" ]; then
    echo "Creating bucket 'securesharing-dev'..."
    BUCKET_RESPONSE=$(curl -sf -X POST -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"globalAlias": "securesharing-dev"}' \
        "$GARAGE_ADMIN_API/v1/bucket")

    BUCKET_ID=$(echo "$BUCKET_RESPONSE" | jq -r '.id')
    echo "Bucket created: $BUCKET_ID"

    # Grant access to the key
    if [ -n "$ACCESS_KEY" ]; then
        echo "Granting key access to bucket..."
        curl -sf -X POST -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"bucketId\": \"$BUCKET_ID\", \"accessKeyId\": \"$ACCESS_KEY\", \"permissions\": {\"read\": true, \"write\": true, \"owner\": true}}" \
            "$GARAGE_ADMIN_API/v1/bucket/allow" > /dev/null
    fi
else
    echo "Bucket 'securesharing-dev' already exists."
fi
echo ""

# Create test bucket if it doesn't exist
TEST_BUCKET_EXISTS=$(curl -sf -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
    "$GARAGE_ADMIN_API/v1/bucket?globalAlias=securesharing-test" 2>/dev/null | jq -r '.id' 2>/dev/null || echo "")

if [ -z "$TEST_BUCKET_EXISTS" ] || [ "$TEST_BUCKET_EXISTS" = "null" ]; then
    echo "Creating bucket 'securesharing-test'..."
    BUCKET_RESPONSE=$(curl -sf -X POST -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"globalAlias": "securesharing-test"}' \
        "$GARAGE_ADMIN_API/v1/bucket")

    BUCKET_ID=$(echo "$BUCKET_RESPONSE" | jq -r '.id')
    echo "Bucket created: $BUCKET_ID"

    # Grant access to the key
    if [ -n "$ACCESS_KEY" ]; then
        echo "Granting key access to bucket..."
        curl -sf -X POST -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"bucketId\": \"$BUCKET_ID\", \"accessKeyId\": \"$ACCESS_KEY\", \"permissions\": {\"read\": true, \"write\": true, \"owner\": true}}" \
            "$GARAGE_ADMIN_API/v1/bucket/allow" > /dev/null
    fi
else
    echo "Bucket 'securesharing-test' already exists."
fi
echo ""

echo "=== Garage Setup Complete ==="
echo ""
echo "Add these to your .env file:"
echo ""
echo "S3_ENDPOINT=http://localhost:3900"
echo "S3_ACCESS_KEY_ID=$ACCESS_KEY"
if [ -n "$SECRET_KEY" ]; then
    echo "S3_SECRET_ACCESS_KEY=$SECRET_KEY"
else
    echo "S3_SECRET_ACCESS_KEY=<secret-from-initial-setup>"
fi
echo "S3_BUCKET=securesharing-dev"
echo "S3_REGION=garage"
echo ""
