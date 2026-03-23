#!/bin/bash
pkill -f "server:run" || true
redis-cli shutdown || true
pg_ctlcluster 15 main stop 2>/dev/null || service postgresql stop 2>/dev/null || true
echo "Preview environment stopped."
