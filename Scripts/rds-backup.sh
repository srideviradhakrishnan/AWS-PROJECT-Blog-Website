#!/bin/bash
# Script to create a snapshot of the production RDS database

RDS_INSTANCE_ID="prod-db-instance"
SNAPSHOT_ID="prod-db-snapshot-$(date +'%Y-%m-%d-%H-%M')"

echo "Creating snapshot ${SNAPSHOT_ID} for RDS instance ${RDS_INSTANCE_ID}..."

aws rds create-db-snapshot \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --db-snapshot-identifier $SNAPSHOT_ID

echo "✅ RDS snapshot ${SNAPSHOT_ID} creation initiated."
