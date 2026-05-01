-- 001_enable_extensions.sql
-- Enable required UUID/crypto extensions for GRAPPL schema.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
