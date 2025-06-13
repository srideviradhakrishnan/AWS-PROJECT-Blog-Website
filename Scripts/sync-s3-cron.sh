#!/bin/bash
# Script to sync WordPress content from EC2 to S3 (for DR)

# Define variables
SOURCE_DIR="/var/www/html/wp-content"
S3_BUCKET="s3://your-wordpress-backup-bucket"

echo "Starting S3 sync from ${SOURCE_DIR} to ${S3_BUCKET}..."

aws s3 sync $SOURCE_DIR $S3_BUCKET --delete

echo "✅ S3 sync completed at $(date)."
