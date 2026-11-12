#!/bin/sh
# Chạy MỘT LẦN khi volume dữ liệu còn trống.
# Tạo user "team" (không phải superuser) và database "team" do user này sở hữu.
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE ROLE team LOGIN PASSWORD '$TEAM_PASSWORD';
CREATE DATABASE team OWNER team;
EOSQL
